extends Node
## Общий огород по сети. Хозяин игры хранит состояние огорода и сам применяет все действия:
## остальные просят его («вскопай клетку 20,15»), он проверяет, меняет огород и рассылает результат всем.
## Когда играешь один, ты и есть хозяин — всё работает так же, только без сети.

const Farm := preload("res://scripts/farm.gd")
const Location := preload("res://scripts/location.gd")

var main: Node
var farm := Farm.new()
## Что сейчас в руках у этого игрока: "hoe", "can" или "seed" (тогда crop — какие семена).
var tool := "hoe"
var tool_crop := ""
var my_water := Farm.CAN_CAP
var sleeping := {}           # у хозяина: id игрока -> лёг спать
var _picking := {}           # id предметов, которые мы уже попросили подобрать


func setup(p_main: Node) -> void:
	main = p_main
	name = "FarmNet"


func is_host() -> bool:
	return multiplayer.is_server()


func me_id() -> int:
	return multiplayer.get_unique_id()


# ---------- пояс: инструменты и семена ----------

## Мотыга, лейка и все семена, которые есть (до 12 ячеек).
func belt() -> Array:
	var out := [{"tool": "hoe", "crop": ""}, {"tool": "can", "crop": ""}]
	for c in Farm.CROPS:
		var k: String = c["key"]
		if out.size() < 12 and (farm.seeds.get(k, 0) > 0 or (tool == "seed" and tool_crop == k)):
			out.append({"tool": "seed", "crop": k})
	return out


func select(slot: Dictionary) -> void:
	tool = slot["tool"]
	tool_crop = slot["crop"]


func tool_name() -> String:
	match tool:
		"hoe":
			return "Мотыга"
		"can":
			return "Лейка (%d из %d)" % [my_water, Farm.CAN_CAP]
	var c := Farm.crop(tool_crop)
	return "%s (%d)" % [c.get("seed_name", ""), farm.seeds.get(tool_crop, 0)]


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
	return tool != "can" and Farm.farmable(map, cell.x, cell.y)


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
	request("use", [cell.x, cell.y, tool, tool_crop])


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
			var r := farm.use(main.map, peer, x, y, args[2], args[3])
			if r.has("msg"):
				_to(peer, "net_toast", [r["msg"]])
			if r.get("plot", false):
				_all("net_plot", [x, y, farm.plot_at(x, y)])
			if r.get("inv", false):
				_send_inv()
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
			farm.ship(args[0], args[1])
			_send_inv()
		"pickup":
			var id: int = args[0]
			if farm.drops.has(id):
				var key: String = farm.drops[id]["key"]
				farm.drops.erase(id)
				farm.produce[key] = farm.produce.get(key, 0) + 1
				_all("net_drop_gone", [id])
				_send_inv()
				_to(peer, "net_toast", ["+1 " + String(Farm.crop(key)["product"]).to_lower()])
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
		var id := farm.add_drop(key, to.x, to.z)
		list.append([id, key, from.x, from.z, to.x, to.z])
	_all("net_drops", [list])


func _send_inv() -> void:
	_all("net_inv", [farm.money, farm.seeds, farm.produce, farm.shipped])


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


func on_peer_disconnected(id: int) -> void:
	if is_host():
		farm.water.erase(id)
		sleeping.erase(id)
		if not sleeping.is_empty():
			_check_sleep()


## Предметы на земле сами летят к игроку; долетевшие просим у хозяина положить в инвентарь.
func tick(delta: float) -> void:
	for id in main.world.pull_drops(main.me.position, delta):
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
func net_inv(money: int, seeds: Dictionary, produce: Dictionary, shipped: Dictionary) -> void:
	farm.money = money
	farm.seeds = seeds
	farm.produce = produce
	farm.shipped = shipped
	main.hud.refresh_farm()


@rpc("authority", "call_remote", "reliable")
func net_water(n: int) -> void:
	my_water = n


@rpc("authority", "call_remote", "reliable")
func net_drops(list: Array) -> void:
	for d in list:
		farm.drops[int(d[0])] = {"key": d[1], "x": d[4], "z": d[5]}
		main.world.add_drop(int(d[0]), d[1], Vector3(d[2], 0, d[3]), Vector3(d[4], 0, d[5]))


@rpc("authority", "call_remote", "reliable")
func net_drop_gone(id: int) -> void:
	farm.drops.erase(id)
	_picking.erase(id)
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
