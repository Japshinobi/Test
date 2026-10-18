extends Node
## Общий огород по сети. Хозяин игры хранит состояние огорода и сам применяет все действия:
## остальные просят его («вскопай клетку 20,15»), он проверяет, меняет огород и рассылает результат всем.
## Когда играешь один, ты и есть хозяин — всё работает так же, только без сети.

const Farm := preload("res://scripts/farm.gd")
const Location := preload("res://scripts/location.gd")

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


func setup(p_main: Node) -> void:
	main = p_main
	name = "FarmNet"
	farm.inv[1] = my_inv


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
	if farm.plot_at(cell.x, cell.y) != null:
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
		"refill":
			if farm.water_of(peer) >= Farm.CAN_CAP:
				_to(peer, "net_toast", ["Лейка уже полная."])
			else:
				farm.water[peer] = Farm.CAN_CAP
				_to(peer, "net_water", [Farm.CAN_CAP])
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
	var say := func(msg: String) -> void: _to(peer, "net_toast", [msg])
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
			if map.ground_at(x, y) == "," and o == null:
				_all("net_mod", [loc, x, y, {"ground": "."}])
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
func end_day(note: String) -> void:
	if not is_host():
		return
	var m := farm.new_day()
	sleeping.clear()
	_all("net_new_day", [farm.to_dict(), m, note])


func on_peer_connected(id: int) -> void:
	if is_host():
		farm.water[id] = Farm.CAN_CAP
		_to(id, "net_full", [farm.to_dict(), main.minutes])
		_send_my_inv(id)


func on_peer_disconnected(id: int) -> void:
	if is_host():
		farm.water.erase(id)
		farm.inv.erase(id)
		sleeping.erase(id)
		if not sleeping.is_empty():
			_check_sleep()


## Хозяин пропал: дальше играем одни со своим огородом и своим инвентарём.
func on_lost_host() -> void:
	farm.inv = {1: my_inv}
	farm.water = {1: my_water}
	sleeping.clear()


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


## Удар по дереву или камню: качнуть его и поднять пыль (видно всем, кто рядом).
@rpc("authority", "call_remote", "reliable")
func net_fx(loc: String, x: int, y: int, kind: String) -> void:
	if loc == main.loc_id:
		main.world.hit_fx(x, y, kind)


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
	for loc in farm.mods:
		Location.get_loc(loc).apply_mods(farm.mods[loc])
	_picking.clear()
	my_water = Farm.CAN_CAP
	main.minutes = minutes
	main.set_day(farm.day)
	main.hud.refresh_farm()


@rpc("authority", "call_remote", "reliable")
func net_new_day(state: Dictionary, morning: Dictionary, note: String) -> void:
	if not is_host():
		farm.from_dict(state)
	_picking.clear()
	main.on_new_day(morning, note)
