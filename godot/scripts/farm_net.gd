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
	var o: Variant = map.object_at(cell.x, cell.y)
	if o != null:
		var d := Location.def(o["id"])
		if d.get("model", "") == "house":
			var door: Array = d.get("door", [0, 0])
			if cell == Vector2i(o["x"] + int(door[0]), o["y"] + int(door[1])):
				main.hud.ask_sleep()
			else:
				main.hud.toast("Дедушкин дом. Крыша течёт, доски скрипят. Нужен ремонт.")
			return
		match String(o["id"]):
			"bin":
				main.hud.open_ship()
			"mailbox":
				main.hud.show_message("Почтовый ящик", "Писем пока нет. Сюда будут приходить новости и объявления.")
			"sign":
				main.hud.show_message("Табличка", String(o.get("text", "")))
			"well":
				request("refill")
			"bigoak":
				main.hud.toast("Огромный старый дуб перегородил дорогу. Что за ним, узнаем позже.")
			_:
				if d.get("block", true):
					main.hud.toast("Топор и кирка появятся на следующих шагах.")
		return
	if map.ground_at(cell.x, cell.y) == "~":
		request("refill")
		return
	request("use", [cell.x, cell.y, sel])


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
			var x: int = args[0]
			var y: int = args[1]
			var r := farm.use(main.map, peer, x, y, args[2])
			if r.has("msg"):
				_to(peer, "net_toast", [r["msg"]])
			if r.get("plot", false):
				_all("net_plot", [x, y, farm.plot_at(x, y)])
			if r.get("inv", false):
				_send_my_inv(peer)
			if r.get("water", false):
				_to(peer, "net_water", [farm.water_of(peer)])
			if r.has("harvest"):
				_spill(x, y, r["harvest"][0], r["harvest"][1])
		"refill":
			if farm.water_of(peer) >= Farm.CAN_CAP:
				_to(peer, "net_toast", ["Лейка уже полная."])
			else:
				farm.water[peer] = Farm.CAN_CAP
				_to(peer, "net_water", [Farm.CAN_CAP])
				_to(peer, "net_toast", ["Лейка наполнена: %d л." % Farm.CAN_CAP])
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
			# выбросить из ячейки на землю перед собой: args = [ячейка, сколько (0 — всё), x, z]
			var got: Variant = farm.take(peer, args[0], args[1])
			if got != null:
				_send_my_inv(peer)
				var did := farm.add_drop(got["id"], got["n"], args[2], args[3])
				_all("net_drops", [[[did, got["id"], got["n"], args[2], args[3], args[2], args[3], peer]]])
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


## Урожай разлетается вокруг грядки в пределах клетки.
func _spill(x: int, y: int, key: String, n: int) -> void:
	var list := []
	var from := Vector3(x + 0.5, 0, y + 0.5)
	for i in n:
		var a := randf() * TAU
		var r := 0.2 + randf() * 0.8
		var to := from + Vector3(cos(a) * r, 0, sin(a) * r * 0.8)
		var id := farm.add_drop("prod:" + key, 1, to.x, to.z)
		list.append([id, "prod:" + key, 1, from.x, from.z, to.x, to.z, 0])
	_all("net_drops", [list])


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


@rpc("authority", "call_remote", "reliable")
func net_drops(list: Array) -> void:
	# [id, предмет, сколько, откуда x, z, куда x, z, кто выбросил (0 — никто)]
	for d in list:
		farm.drops[int(d[0])] = {"item": d[1], "n": d[2], "x": d[5], "z": d[6]}
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
