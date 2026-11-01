extends Node
## Общий огород по сети. Хозяин игры хранит состояние огорода и сам применяет все действия:
## остальные просят его («вскопай клетку 20,15»), он проверяет, меняет огород и рассылает результат всем.
## Когда играешь один, ты и есть хозяин — всё работает так же, только без сети.

const Farm := preload("res://scripts/farm.gd")
const Location := preload("res://scripts/location.gd")
const Weather := preload("res://scripts/weather.gd")

var main: Node
var farm := Farm.new()
## Свой инвентарь (копия от хозяина), выбранная ячейка и ряд панели быстрого доступа.
var my_inv: Array = Farm.new_inventory()
var sel := 0
var row := 0
var my_water := Farm.CAN_CAP
var sleeping := {}           # у хозяина: id игрока -> лёг спать
var _picking := {}           # id предметов, которые мы уже попросили подобрать
var _full: Array = []        # что не влезло в инвентарь: не тянем к себе, пока не отойдём

## Постоянный номер игрока на этом устройстве: по нему хозяин узнаёт его при следующем подключении.
var uid := ""
var peer_uid := {}           # у хозяина: id в сети -> постоянный номер
var saved_invs := {}         # у хозяина: постоянный номер -> инвентарь (и тех, кто сейчас не в игре)
var saved_water := {}
const SAVE_PATH := "user://save.json"
const PLAYER_PATH := "user://player.cfg"


func setup(p_main: Node) -> void:
	main = p_main
	name = "FarmNet"
	farm.inv[1] = my_inv
	uid = _load_uid()


static func _load_uid() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PLAYER_PATH) == OK and cfg.has_section_key("player", "uid"):
		return cfg.get_value("player", "uid")
	var id := "%08x%08x" % [randi(), randi()]
	cfg.set_value("player", "uid", id)
	cfg.save(PLAYER_PATH)
	return id


# ---------- сохранение ----------
# Сохраняет только хозяин игры (или тот, кто играет один): огород, изменения карт, предметы на земле,
# день и время, инвентари всех игроков по их постоянным номерам. Кто подключался к другу, его мир не трогает.

func save_game() -> void:
	if main.net_mode() == "client":
		return
	_remember_players()
	var data := farm.to_dict()
	data["version"] = 1
	data["minutes"] = main.minutes
	data["invs"] = saved_invs
	data["water"] = saved_water
	data["loc"] = main.loc_id
	data["pos"] = [main.me.position.x, main.me.position.z]
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))


## Переписать инвентари тех, кто сейчас в игре, в общий список по постоянным номерам.
func _remember_players() -> void:
	saved_invs[uid] = my_inv
	saved_water[uid] = my_water
	for p in peer_uid:
		if farm.inv.has(p):
			saved_invs[peer_uid[p]] = farm.inv[p]
			saved_water[peer_uid[p]] = farm.water_of(p)


## Загрузить сохранённую игру. Возвращает false, если сохранения нет (тогда игра начинается заново).
func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not data is Dictionary:
		return false
	farm = Farm.new()
	farm.from_dict(data)
	farm.money = int(farm.money)
	for k in farm.shipped:
		farm.shipped[k] = int(farm.shipped[k])
	for id in farm.drops:
		farm.drops[id]["n"] = int(farm.drops[id]["n"])
	saved_invs = {}
	for u in data.get("invs", {}):
		saved_invs[u] = _fix_inv(data["invs"][u])
	saved_water = data.get("water", {})
	my_inv = saved_invs.get(uid, Farm.new_inventory())
	my_water = int(saved_water.get(uid, Farm.CAN_CAP))
	farm.inv = {1: my_inv}
	farm.water = {1: my_water}
	Location._cache.clear()
	for loc in farm.mods:
		Location.get_loc(loc).apply_mods(farm.mods[loc])
	main.minutes = float(data.get("minutes", 360.0))
	main.day = farm.day
	var loc: String = data.get("loc", "farm")
	main.enter_location(loc if Location.exists(loc) else "farm")
	var pos: Array = data.get("pos", [])
	if pos.size() == 2 and main.map.walkable(floori(pos[0]), floori(pos[1])):
		main.me.position = Vector3(pos[0], 0, pos[1])
		main.cam_target = main.me.position
	return true


## Числа из файла приходят дробными: количество предметов делаем целым.
static func _fix_inv(a: Array) -> Array:
	var out := []
	out.resize(Farm.INV_SIZE)
	for i in mini(a.size(), Farm.INV_SIZE):
		if a[i] != null:
			out[i] = {"id": String(a[i]["id"]), "n": int(a[i]["n"])}
	return out


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	saved_invs.clear()
	saved_water.clear()


## Подключившийся игрок назвал свой постоянный номер: выдаём ему его инвентарь (или стартовый набор).
@rpc("any_peer", "call_remote", "reliable")
func net_hello(p_uid: String) -> void:
	if not is_host():
		return
	var peer := multiplayer.get_remote_sender_id()
	peer_uid[peer] = p_uid
	farm.inv[peer] = saved_invs[p_uid] if saved_invs.has(p_uid) else Farm.new_inventory()
	farm.water[peer] = int(saved_water.get(p_uid, Farm.CAN_CAP))
	_send_my_inv(peer)
	_to(peer, "net_water", [farm.water_of(peer)])


func is_host() -> bool:
	return multiplayer.is_server()


func me_id() -> int:
	return multiplayer.get_unique_id()


# ---------- что в руках ----------

## Предмет в выбранной ячейке (или null).
func held() -> Variant:
	return my_inv[sel] if sel < my_inv.size() else null


## Чем сейчас работаем: "hoe", "can", "axe", "pick", "seed" или "" (пустые руки, урожай).
func tool() -> String:
	var h: Variant = held()
	if h == null:
		return ""
	var id: String = h["id"]
	if id.begins_with("tool:"):
		return id.get_slice(":", 1)
	return "seed" if id.begins_with("seed:") else ""


func select(slot: int) -> void:
	sel = slot


func set_row(r: int) -> void:
	row = posmod(r, Farm.ROWS)
	sel = row * Farm.ROW + sel % Farm.ROW


func tool_name() -> String:
	var h: Variant = held()
	if h == null:
		return "ничего"
	var info := Farm.item_info(h["id"])
	if h["id"] == "tool:can":
		return "Лейка (%d из %d)" % [my_water, Farm.CAN_CAP]
	return info["name"] + (" (%d)" % h["n"] if h["n"] > 1 or info["stack"] > 1 else "")


# ---------- действия ----------

## Нужно ли подойти к клетке и что-то с ней сделать (а не просто прийти на неё).
func is_target(cell: Vector2i) -> bool:
	var map: Location = main.map
	var o: Variant = map.object_at(cell.x, cell.y)
	if o != null and Location.def(o["id"]).get("block", true):
		return true
	if map.ground_at(cell.x, cell.y) == "~":
		return true
	# грядки есть только на огороде: в другой локации та же клетка — просто земля
	if main.loc_id == "farm" and farm.plot_at(cell.x, cell.y) != null:
		return true
	var t := tool()
	return (t == "hoe" or t == "seed") and Farm.farmable(map, cell.x, cell.y)


## Игрок стоит рядом с клеткой и применяет к ней то, что в руках (или осматривает предмет).
func act(cell: Vector2i) -> void:
	var map: Location = main.map
	var hud: Node = main.hud
	var o: Variant = map.object_at(cell.x, cell.y)
	var t := tool()
	if o != null:
		var id := String(o["id"])
		var d := Location.def(id)
		if d.get("model", "") == "house":
			var door: Array = d.get("door", [0, 0])
			if cell == Vector2i(o["x"] + int(door[0]), o["y"] + int(door[1])):
				hud.ask_sleep()
			else:
				hud.toast("Дедушкин дом. Крыша течёт, доски скрипят. Нужен ремонт.")
			return
		match id:
			"bin":
				hud.open_ship()
			"barometer":
				hud.show_forecast()
			"mailbox":
				hud.show_message("Почтовый ящик", "Писем пока нет. Сюда будут приходить извещения: о смене сезона, о погоде и другие новости.")
			"sign":
				hud.show_message("Табличка", String(o.get("text", "")))
			"well":
				request("refill")
			"bigoak":
				hud.toast("Огромный старый дуб перегородил дорогу. Что за ним, узнаем позже.")
			"signpost", "scarecrow", "haystack", "barrier_h", "barrier_v":
				hud.toast(String(o.get("text", "")))
			"fountain":
				hud.toast("Фонтан замёрз до весны." if Location.season_id(main.day) == "winter" else "Фонтан на рыночной площади. Вода журчит.")
			"stall", "stallside", "tent", "stallback":
				var who := String(o.get("trader", ""))
				if who == "":
					hud.toast("Свободное место. Здесь появится новый торговец.")
				elif not main.market_open():
					hud.toast("Сегодня у рынка выходной: последний день сезона." if Location.season_day(main.day) == Location.SEASON_DAYS else "Рынок открыт с 8:00 до 18:00.")
				else:
					hud.open_trader(who)
			"tree0", "tree1", "stump", "twigs", "rock":
				request("strike", [main.loc_id, cell.x, cell.y, sel])
			_:
				pass
		return
	var g := map.ground_at(cell.x, cell.y)
	if g == "~":
		request("refill")
		return
	if (g == "Q" or g == "N") and t != "can":
		hud.toast("Это соседское поле: здесь ничего не собрать.")
		return
	if t == "axe" or t == "pick" or t == "scythe":
		request("strike", [main.loc_id, cell.x, cell.y, sel])
		return
	request("use", [main.loc_id, cell.x, cell.y, sel])


## Попросить хозяина что-то сделать. Если хозяин — мы сами, делаем сразу.
func request(action: String, args: Array = []) -> void:
	if is_host():
		_host(me_id(), action, args)
	else:
		net_request.rpc_id(1, action, args)


@rpc("any_peer", "call_remote", "reliable")
func net_request(action: String, args: Array) -> void:
	if is_host():
		_host(multiplayer.get_remote_sender_id(), action, args)


## Только у хозяина: проверить и применить действие игрока peer, разослать, что изменилось.
func _host(peer: int, action: String, args: Array) -> void:
	match action:
		"use":
			var loc: String = args[0]
			var x: int = args[1]
			var y: int = args[2]
			var r := farm.use(Location.get_loc(loc), peer, x, y, args[3])
			if r.has("msg"):
				_to(peer, "net_toast", [r["msg"]])
				if not r.has("fx"):
					_to(peer, "net_sfx", ["nope"])
			if r.has("fx"):
				_all("net_fx", [loc, x, y, r["fx"]])
			if r.get("plot", false):
				_all("net_plot", [x, y, farm.plot_at(x, y)])
			if r.get("inv", false):
				_send_my_inv(peer)
			if r.get("water", false):
				_to(peer, "net_water", [farm.water_of(peer)])
			if r.has("harvest"):
				_spill(loc, x, y, "prod:" + r["harvest"][0], r["harvest"][1])
		"strike":
			_strike(peer, args[0], args[1], args[2], args[3])
		"trod":
			# протоптали снег: args = [локация, x, y]
			if not farm.snow_trod.has(args[0]):
				farm.snow_trod[args[0]] = {}
			var k := "%d,%d" % [args[1], args[2]]
			if not farm.snow_trod[args[0]].has(k):
				farm.snow_trod[args[0]][k] = true
				_all("net_trod", [args[0], args[1], args[2]])
		"give":
			# админ-панель: положить предметы себе в инвентарь
			var left := farm.add_item(peer, args[0], args[1])
			_send_my_inv(peer)
			_to(peer, "net_toast", ["Добавлено: %d" % (args[1] - left) + ("" if left == 0 else " (не поместилось %d)" % left)])
		"refill":
			if farm.water_of(peer) >= Farm.CAN_CAP:
				_to(peer, "net_toast", ["Лейка уже полная."])
			else:
				farm.water[peer] = Farm.CAN_CAP
				_to(peer, "net_water", [Farm.CAN_CAP])
				_to(peer, "net_sfx", ["water"])
				_to(peer, "net_toast", ["Лейка наполнена: %d л." % Farm.CAN_CAP])
		"sell":
			var got := farm.sell(peer, args[0], args[1], args[2])
			if got > 0:
				_send_my_inv(peer)
				_send_inv()
				_to(peer, "net_toast", ["+%d монет" % got])
				_to(peer, "net_sfx", ["coin"])
		"buy":
			var err := farm.buy(peer, args[0], args[1], args[2])
			if err != "":
				_to(peer, "net_toast", [err])
			else:
				_send_my_inv(peer)
				_send_inv()
				_to(peer, "net_sfx", ["coin"])
		"ship":
			farm.ship(peer, args[0], args[1])
			_to(peer, "net_sfx", ["plant"])
			_send_my_inv(peer)
			_send_inv()
		"pickup":
			var id: int = args[0]
			if farm.drops.has(id):
				var d: Dictionary = farm.drops[id]
				var left := farm.add_item(peer, d["item"], d["n"])
				var got: int = d["n"] - left
				if got <= 0:
					_to(peer, "net_full_bag", [id])
					return
				_send_my_inv(peer)
				_to(peer, "net_sfx", ["pickup"])
				_to(peer, "net_toast", ["+%d %s" % [got, String(Farm.item_info(d["item"])["name"]).to_lower()]])
				if left > 0:
					d["n"] = left
					_to(peer, "net_full_bag", [id])
				else:
					farm.drops.erase(id)
					_all("net_drop_gone", [id])
		"drop":
			# выбросить из ячейки на землю перед собой: args = [ячейка, сколько (0 — всё), x, z, локация]
			var got: Variant = farm.take(peer, args[0], args[1])
			if got != null:
				_send_my_inv(peer)
				var did := farm.add_drop(got["id"], got["n"], args[2], args[3], args[4])
				_all("net_drops", [[[did, got["id"], got["n"], args[2], args[3], args[2], args[3], peer, args[4]]]])
		"erase":
			if farm.take(peer, args[0], 0) != null:
				_send_my_inv(peer)
		"move":
			farm.move(peer, args[0], args[1])
			_send_my_inv(peer)
		"sleep":
			sleeping[peer] = true
			_check_sleep()
		"wake":
			sleeping.erase(peer)
			_all("net_sleepers", [sleeping.keys()])


## Урожай, дрова и камни разлетаются вокруг клетки в пределах одной клетки.
func _spill(loc: String, x: int, y: int, item: String, n: int) -> void:
	var list := []
	var from := Vector3(x + 0.5, 0, y + 0.5)
	for i in n:
		var a := randf() * TAU
		var r := 0.2 + randf() * 0.8
		var to := from + Vector3(cos(a) * r, 0, sin(a) * r * 0.8)
		var id := farm.add_drop(item, 1, to.x, to.z, loc)
		list.append([id, item, 1, from.x, from.z, to.x, to.z, 0, loc])
	_all("net_drops", [list])


# ---------- топор, кирка, коса ----------
# Удары копятся: дерево падает с 3-го (остаётся пень), пень — со 2-го, камень — со 2-го, ветки — с 1-го.
const NEED := {"tree0": 3, "tree1": 3, "stump": 2, "rock": 2, "twigs": 1}
const GAIN := {"tree0": ["res:wood", 4], "tree1": ["res:wood", 4], "stump": ["res:wood", 2], "twigs": ["res:wood", 1], "rock": ["res:stone", 2]}
var hits := {}


func _strike(peer: int, loc: String, x: int, y: int, slot: int) -> void:
	var map: Location = Location.get_loc(loc)
	map.season = Location.season_id(farm.day)
	var held_item: Variant = farm.inv_of(peer)[slot] if slot >= 0 and slot < farm.inv_of(peer).size() else null
	var t := String(held_item["id"]).get_slice(":", 1) if held_item != null and String(held_item["id"]).begins_with("tool:") else ""
	var o: Variant = map.object_at(x, y)
	var id := String(o["id"]) if o != null else ""
	var say := func(msg: String) -> void:
		_to(peer, "net_toast", [msg])
		if not msg.begins_with("Дерево упало"):
			_to(peer, "net_sfx", ["nope"])
	if id in ["tree0", "tree1", "stump", "twigs"]:
		if t != "axe":
			say.call("Дерево рубят топором." if id.begins_with("tree") else ("Пень выкорчёвывают топором." if id == "stump" else "Ветки рубят топором."))
			return
		if id.begins_with("tree") and map.is_edge(x, y):
			say.call("Это край леса: деревья вдоль границы не рубят.")
			return
	elif id == "rock":
		if t != "pick":
			say.call("Камень разбивают киркой.")
			return
	else:
		if t == "scythe":
			if map.has_flowers(x, y) and not (loc == "farm" and farm.plot_at(x, y) != null):
				_all("net_mod", [loc, x, y, {"mown": true}])
				_all("net_fx", [loc, x, y, "mow"])
			elif loc == "farm" and farm.plot_at(x, y) != null and farm.plot_at(x, y)["crop"] != "":
				say.call("Какие культуры убирать косой, решим позже.")
			else:
				say.call("Здесь нечего косить.")
		elif t == "axe":
			say.call("Здесь нечего рубить.")
		elif t == "pick":
			say.call("Здесь нечего разбивать.")
		return
	var key := "%s:%d,%d" % [loc, x, y]
	var n: int = hits.get(key, 0) + 1
	_all("net_fx", [loc, x, y, "mine" if id == "rock" else "chop"])
	if n < NEED[id]:
		hits[key] = n
		return
	hits.erase(key)
	_all("net_mod", [loc, x, y, {"replace": "stump"} if id.begins_with("tree") else {"remove": true}])
	_spill(loc, x, y, GAIN[id][0], GAIN[id][1])
	if id.begins_with("tree"):
		say.call("Дерево упало. Остался пень.")


## Общее: деньги и что лежит в ящике для продажи.
func _send_inv() -> void:
	_all("net_inv", [farm.money, farm.shipped])


## Свой инвентарь — только его хозяину.
func _send_my_inv(peer: int) -> void:
	_to(peer, "net_my_inv", [farm.inv_of(peer)])


## Новый день наступает, когда спать легли все. Пока нет — тем, кто лёг, показываем, кого ждём.
func _check_sleep() -> void:
	for p in _peers():
		if not sleeping.get(p, false):
			_all("net_sleepers", [sleeping.keys()])
			return
	end_day("")


func _peers() -> Array:
	var out := [1]
	if main.net_mode() != "off":
		out.append_array(multiplayer.get_peers())
	return out


## Только у хозяина: закончить день для всех (все легли спать, наступила полночь или кнопка «+ день»).
## Только у хозяина: если пошёл дождь — полить огород и разослать грядки. Вызывается каждый кадр.
func check_rain(minutes: float) -> void:
	if not is_host() or not farm.apply_rain(minutes):
		return
	for key in farm.plots:
		var xy: PackedStringArray = String(key).split(",")
		_all("net_plot", [int(xy[0]), int(xy[1]), farm.plots[key]])


## Только у хозяина: погода на сегодня вручную (админ-панель).
func set_weather(id: String) -> void:
	if not is_host():
		return
	farm.set_weather(id, main.minutes)
	_all("net_weather", [farm.weather])
	check_rain(main.minutes)


## Только у хозяина: погода на завтра вручную (админ-панель); барометр сразу её показывает, завтра она и будет.
func set_weather_next(id: String) -> void:
	if not is_host():
		return
	farm.weather["next"] = Weather.fixed(id, Weather.DAY_START, farm.rng)
	_all("net_weather", [farm.weather])


## Только у хозяина: заморозки в эту ночь (админ-панель).
func set_frost_tonight() -> void:
	if not is_host():
		return
	farm.weather["frost"] = farm.day
	_all("net_weather", [farm.weather])


## Только у хозяина, каждый кадр: настала минута удара молнии — ударить. Если гроза к этой минуте
## кончилась (сменилась погода), удар отменяется. Давно прошедшие удары (перевели часы) пропускаются.
func check_lightning(minutes: float) -> void:
	if not is_host():
		return
	var today: Dictionary = farm.weather["today"]
	var all: Dictionary = today.get("strikes", {})
	for loc in all:
		var times: Array = all[loc]
		while not times.is_empty() and float(times[0]) <= minutes:
			var t := float(times.pop_front())
			if minutes - t <= 30.0 and Weather.lightning_now(today, t):
				strike_lightning(String(loc))


## Удар молнии в локации loc: случайная клетка, куда может пройти персонаж, не в клетку игрока и не в соседние (3×3),
## без деревьев (и яблони на грядке). Посев на клетке сгорает; огонь и след видят все, кто в этой локации.
func strike_lightning(loc: String) -> Vector2i:
	var map: Location = Location.get_loc(loc)
	map.season = Location.season_id(farm.day)
	var near := _player_cells(loc)
	for attempt in 400:
		var c := Vector2i(farm.rng.randi_range(0, map.W - 1), farm.rng.randi_range(0, map.H - 1))
		if not map.walkable(c.x, c.y):
			continue
		var p: Variant = farm.plot_at(c.x, c.y) if loc == "farm" else null
		if p != null and p["crop"] != "" and Farm.crop(p["crop"]).get("tree", false):
			continue
		var close := false
		for q in near:
			if maxi(absi(q.x - c.x), absi(q.y - c.y)) <= Weather.SAFE:
				close = true
		if close:
			continue
		# посев сгорает: огонь, потом обгоревшее растение — без горелого следа (решение владельца 01.11.2026)
		var burnt := loc == "farm" and farm.burn(c.x, c.y)
		if burnt:
			_all("net_plot", [c.x, c.y, farm.plot_at(c.x, c.y)])
		var trace := 0.0 if burnt else farm.rng.randf_range(Weather.TRACE[0], Weather.TRACE[1])
		_all("net_strike", [loc, c.x, c.y, farm.rng.randf_range(Weather.FIRE[0], Weather.FIRE[1]), trace])
		return c
	return Vector2i(-1, -1)


## Клетки, где стоят игроки в локации loc (хозяин и гости).
func _player_cells(loc: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if main.loc_id == loc:
		out.append(Vector2i(floori(main.me.position.x), floori(main.me.position.z)))
	for r in main.remotes.values():
		if r.get_meta("loc", "") == loc:
			out.append(Vector2i(floori(r.net_pos.x), floori(r.net_pos.z)))
	return out


func end_day(note: String) -> void:
	if not is_host():
		return
	var m := farm.new_day()
	sleeping.clear()
	_all("net_new_day", [farm.to_dict(), m, note])
	save_game()


func on_peer_connected(id: int) -> void:
	if is_host():
		farm.water[id] = Farm.CAN_CAP
		_to(id, "net_full", [farm.to_dict(), main.minutes])
		_send_my_inv(id)
	elif id == 1:
		# мы подключились к хозяину: назовёмся, чтобы он вернул наш инвентарь
		net_hello.rpc_id(1, uid)


func on_peer_disconnected(id: int) -> void:
	if is_host():
		if peer_uid.has(id):
			saved_invs[peer_uid[id]] = farm.inv.get(id, Farm.new_inventory())
			saved_water[peer_uid[id]] = farm.water_of(id)
			peer_uid.erase(id)
		farm.water.erase(id)
		farm.inv.erase(id)
		sleeping.erase(id)
		if not sleeping.is_empty():
			_check_sleep()


## Начать заново (только хозяин): новый огород, нетронутые карты, стартовые инвентари у всех.
func restart() -> void:
	var peers := _peers()
	delete_save()
	farm = Farm.new()
	for p in peers:
		farm.inv_of(p)
		farm.water[p] = Farm.CAN_CAP
	my_inv = farm.inv[1]
	hits.clear()
	sleeping.clear()
	_all("net_full", [farm.to_dict(), 360.0])
	save_game()
	for p in peers:
		_send_my_inv(p)
		_to(p, "net_water", [Farm.CAN_CAP])


## Хозяин пропал или мы отключились: возвращаемся в свой мир (из своего сохранения или новый).
func on_lost_host() -> void:
	sleeping.clear()
	peer_uid.clear()
	_picking.clear()
	_full.clear()
	main.call_deferred("load_own_world")


## Предметы на земле сами летят к игроку; долетевшие просим у хозяина положить в инвентарь.
func tick(delta: float) -> void:
	for id in _full.duplicate():
		if main.world.drop_distance(id, main.me.position) > 2.0:
			_full.erase(id)
	for id in main.world.pull_drops(main.me.position, delta, _full):
		if not _picking.has(id):
			_picking[id] = true
			request("pickup", [id])


# ---------- рассылка ----------

## Вызвать у себя и у всех остальных.
func _all(method: String, args: Array) -> void:
	callv(method, args)
	if main.net_mode() != "off" and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		callv("rpc", [method] + args)


## Вызвать у одного игрока (или у себя).
func _to(peer: int, method: String, args: Array) -> void:
	if peer == me_id():
		callv(method, args)
	else:
		callv("rpc_id", [peer, method] + args)


@rpc("authority", "call_remote", "reliable")
func net_toast(msg: String) -> void:
	main.hud.toast(msg)


@rpc("authority", "call_remote", "reliable")
func net_sfx(name_: String) -> void:
	main.sfx(name_)


@rpc("authority", "call_remote", "reliable")
func net_plot(x: int, y: int, p: Variant) -> void:
	if p == null:
		farm.plots.erase(Farm.cell_key(x, y))
	else:
		farm.plots[Farm.cell_key(x, y)] = p
	main.world.sync_plot(x, y, p)


@rpc("authority", "call_remote", "reliable")
func net_inv(money: int, shipped: Dictionary) -> void:
	farm.money = money
	farm.shipped = shipped
	main.hud.refresh_farm()


@rpc("authority", "call_remote", "reliable")
func net_my_inv(slots: Array) -> void:
	my_inv = slots
	if is_host():
		farm.inv[me_id()] = slots
	main.hud.refresh_farm()


## Подобрать не вышло: инвентарь полон. Попробуем снова, когда отойдём и подойдём.
@rpc("authority", "call_remote", "reliable")
func net_full_bag(id: int) -> void:
	main.hud.toast("Инвентарь полон.")
	_picking.erase(id)
	if id not in _full:
		_full.append(id)


@rpc("authority", "call_remote", "reliable")
func net_water(n: int) -> void:
	my_water = n


## Карта изменилась: срубили дерево, разбили камень, скосили цветы.
@rpc("authority", "call_remote", "reliable")
func net_mod(loc: String, x: int, y: int, change: Dictionary) -> void:
	Location.get_loc(loc).apply_mod(x, y, change)
	if not farm.mods.has(loc):
		farm.mods[loc] = {}
	farm.mods[loc] = Location.get_loc(loc).mods
	if loc == main.loc_id:
		main.on_map_changed(x, y)


@rpc("authority", "call_remote", "reliable")
func net_trod(loc: String, x: int, y: int) -> void:
	if not farm.snow_trod.has(loc):
		farm.snow_trod[loc] = {}
	farm.snow_trod[loc]["%d,%d" % [x, y]] = true
	if loc == main.loc_id:
		main.world.add_trod(x, y)


## Удар по дереву или камню: качнуть его и поднять пыль (видно всем, кто рядом).
@rpc("authority", "call_remote", "reliable")
func net_fx(loc: String, x: int, y: int, kind: String) -> void:
	if loc == main.loc_id:
		main.world.hit_fx(x, y, kind)
		main.sfx({"mow": "till"}.get(kind, kind))


@rpc("authority", "call_remote", "reliable")
func net_drops(list: Array) -> void:
	# [id, предмет, сколько, откуда x, z, куда x, z, кто выбросил (0 — никто), локация]
	for d in list:
		farm.drops[int(d[0])] = {"item": d[1], "n": d[2], "x": d[5], "z": d[6], "loc": d[8]}
		if d[8] != main.loc_id:
			continue
		main.world.add_drop(int(d[0]), d[1], Vector3(d[3], 0, d[4]), Vector3(d[5], 0, d[6]))
		# своё выброшенное не притягивается, пока не отойдёшь (иначе сразу прилетит обратно)
		if int(d[7]) == me_id():
			_full.append(int(d[0]))


@rpc("authority", "call_remote", "reliable")
func net_drop_gone(id: int) -> void:
	farm.drops.erase(id)
	_picking.erase(id)
	_full.erase(id)
	main.world.remove_drop(id)


@rpc("authority", "call_remote", "reliable")
func net_sleepers(ids: Array) -> void:
	main.hud.update_sleep(ids)


@rpc("authority", "call_remote", "reliable")
func net_full(state: Dictionary, minutes: float) -> void:
	farm.from_dict(state)
	# карты заново с диска, поверх — изменения хозяина (срубленное, скошенное)
	Location._cache.clear()
	for loc in farm.mods:
		Location.get_loc(loc).apply_mods(farm.mods[loc])
	_picking.clear()
	my_water = Farm.CAN_CAP
	main.minutes = minutes
	main.day = farm.day
	main.enter_location("farm")
	main.hud.refresh_farm()


## Админ-панель хозяина: день сменился без ночи (растения не растут).
@rpc("authority", "call_remote", "reliable")
func net_set_day(d: int, snow_: bool, weather_: Dictionary) -> void:
	farm.day = d
	farm.snow = snow_
	farm.weather = weather_
	main.day = d
	main.set_day(d)


## Удар молнии: вспышка, треск, огонь и горелый след — у тех, кто в этой локации.
@rpc("authority", "call_remote", "reliable")
func net_strike(loc: String, x: int, y: int, fire: float, trace: float) -> void:
	if loc == main.loc_id:
		main.on_strike(x, y, fire, trace)


## Погода сменилась вручную (админ-панель хозяина).
@rpc("authority", "call_remote", "reliable")
func net_weather(weather_: Dictionary) -> void:
	farm.weather = weather_
	main.update_weather()


@rpc("authority", "call_remote", "reliable")
func net_new_day(state: Dictionary, morning: Dictionary, note: String) -> void:
	if not is_host():
		farm.from_dict(state)
	_picking.clear()
	main.on_new_day(morning, note)
