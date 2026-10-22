extends RefCounted
## Локация: карта из файла maps/<id>.json, который правится редактором карт (editor/map-editor.html).
## В файле два слоя: земля (по символу на клетку) и список объектов. Что значат символы земли и какие
## бывают объекты, описано в каталоге data/objects.json — его читают и игра, и редактор.

const SEASON_DAYS := 12
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]
const SEASON_NAMES := ["Весна", "Лето", "Осень", "Зима"]

static var _catalog: Dictionary
static var _cache := {}

var id := ""
var title := ""
var W := 0
var H := 0
var ground := PackedStringArray()
## Объекты: словари {id, x, y} и, если нужно, {text} у таблички или {to} у выхода.
var objects: Array = []
var _cover: Array = []          # какой объект занимает клетку (или null)
var _walk_ground := {}
## Ходить можно только внутри этого прямоугольника (кроме дорог к выходам): [x0, y0, x1, y1] или пусто.
var bounds: Array = []
## Время года сейчас: объекты не своего сезона (стога осенью) в другое время не видны и не мешают.
var season := "spring"
## Что изменили игроки (срубили дерево, разбили камень, скосили цветы): "x,y" -> изменение.
var mods := {}


## Локация по имени: загружается один раз и дальше берётся готовой.
static func get_loc(map_id: String) -> RefCounted:
	if not _cache.has(map_id):
		_cache[map_id] = load("res://scripts/location.gd").new(map_id)
	return _cache[map_id]


## Есть ли такая карта.
static func exists(map_id: String) -> bool:
	return FileAccess.file_exists("res://maps/%s.json" % map_id)


func _init(map_id: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/%s.json" % map_id))
	id = map_id
	title = data.get("name", map_id)
	W = int(data["width"])
	H = int(data["height"])
	bounds = data.get("bounds", [])
	for row in data["ground"]:
		var r := String(row).rpad(W, ".")
		for x in W:
			ground.append(r[x])
	for g in catalog()["ground"]:
		_walk_ground[g["key"]] = g.get("walk", true)
	_cover.resize(W * H)
	for o in data["objects"]:
		o["x"] = int(o["x"])
		o["y"] = int(o["y"])
		objects.append(o)
		_place(o)


func _place(o: Dictionary) -> void:
	var size := object_size(o["id"])
	for dy in size.y:
		for dx in size.x:
			if inside(o["x"] + dx, o["y"] + dy):
				_cover[(o["y"] + dy) * W + o["x"] + dx] = o


func _unplace(o: Dictionary) -> void:
	var size := object_size(o["id"])
	for dy in size.y:
		for dx in size.x:
			var i: int = (o["y"] + dy) * W + o["x"] + dx
			if inside(o["x"] + dx, o["y"] + dy) and _cover[i] == o:
				_cover[i] = null


## Каталог земли и объектов (data/objects.json): объекты по id.
static func catalog() -> Dictionary:
	if _catalog.is_empty():
		_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://data/objects.json"))
		var by_id := {}
		for o in _catalog["objects"]:
			by_id[o["id"]] = o
		_catalog["by_id"] = by_id
	return _catalog


static func def(object_id: String) -> Dictionary:
	return catalog()["by_id"].get(object_id, {})


static func object_size(object_id: String) -> Vector2i:
	var s: Array = def(object_id).get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


## Символ земли в клетке; за краем карты — «непроходимо».
func ground_at(x: int, y: int) -> String:
	return ground[y * W + x] if inside(x, y) else "#"


## Объект, который стоит на клетке (или занимает её частью, как дом), либо null.
## Объекты не своего сезона (стог летом) считаются отсутствующими.
func object_at(x: int, y: int) -> Variant:
	if not inside(x, y):
		return null
	var o: Variant = _cover[y * W + x]
	if o != null and not in_season(o):
		return null
	return o


func in_season(o: Dictionary) -> bool:
	var list: Array = def(o["id"]).get("seasons", [])
	return list.is_empty() or season in list


func in_bounds(x: int, y: int) -> bool:
	return bounds.is_empty() or (x >= bounds[0] and x <= bounds[2] and y >= bounds[1] and y <= bounds[3])


## Край карты или край проходимой части: деревья здесь — граница, их не рубят.
func is_edge(x: int, y: int) -> bool:
	if x == 0 or y == 0 or x == W - 1 or y == H - 1:
		return true
	if bounds.is_empty():
		return false
	return not in_bounds(x, y) or x == bounds[0] or x == bounds[2] or y == bounds[1] or y == bounds[3]


func walkable(x: int, y: int) -> bool:
	if not inside(x, y) or not _walk_ground.get(ground_at(x, y), true):
		return false
	if not in_bounds(x, y) and ground_at(x, y) != "=":
		return false
	var o: Variant = object_at(x, y)
	return o == null or not def(o["id"]).get("block", true)


## Выход в другую локацию на этой клетке (или null).
func exit_at(x: int, y: int) -> Variant:
	var o: Variant = _cover[y * W + x] if inside(x, y) else null
	return o if o != null and o["id"] == "exit" else null


## Куда ставить игрока, пришедшего из локации from_id: на клетку рядом с выходом туда, внутрь карты.
func arrival(from_id: String) -> Vector2i:
	for o in objects:
		if o["id"] == "exit" and o.get("to", "") == from_id:
			var c := Vector2i(o["x"], o["y"])
			if c.y == 0:
				return c + Vector2i(0, 1)
			if c.y == H - 1:
				return c + Vector2i(0, -1)
			if c.x == 0:
				return c + Vector2i(1, 0)
			return c + Vector2i(-1, 0)
	var sp: Variant = find("spawn")
	return Vector2i(sp["x"], sp["y"]) if sp != null else Vector2i(W / 2, H / 2)


# ---------- изменения карты ----------

## Применить изменение клетки: {"remove": true} — убрать объект, {"replace": "stump"} — заменить объект,
## {"ground": "."} — сменить землю. Изменения запоминаются (для сохранения и для тех, кто придёт позже).
func apply_mod(x: int, y: int, change: Dictionary) -> void:
	var key := "%d,%d" % [x, y]
	var prev: Dictionary = mods.get(key, {})
	# храним итог: убранный пень отменяет прежнюю «замену дерева на пень»
	if change.has("remove"):
		prev.erase("replace")
	if change.has("replace"):
		prev.erase("remove")
	prev.merge(change, true)
	mods[key] = prev
	if change.has("ground"):
		ground[y * W + x] = change["ground"]
	if change.has("remove") or change.has("replace"):
		var o: Variant = _cover[y * W + x]
		if o != null:
			_unplace(o)
			objects.erase(o)
		if change.has("replace"):
			var n := {"id": change["replace"], "x": x, "y": y}
			objects.append(n)
			_place(n)


func apply_mods(all: Dictionary) -> void:
	for key in all:
		var xy: PackedStringArray = String(key).split(",")
		apply_mod(int(xy[0]), int(xy[1]), all[key])


func find(object_id: String) -> Variant:
	for o in objects:
		if o["id"] == object_id:
			return o
	return null


# ---------- хеш и времена года (как в браузерной версии) ----------

## Тот же хеш, что hash() в sprites.js: 32-битная арифметика с переполнением.
static func hash3(a: int, b: int, c: int = 0) -> float:
	const M := 0xFFFFFFFF
	var h: int = ((a * 374761393) ^ (b * 668265263) ^ (c * 1274126177)) & M
	h = ((h ^ (h >> 13)) * 1274126177) & M
	h ^= h >> 16
	return h / 4294967296.0


static func season_index(day: int) -> int:
	return ((day - 1) / SEASON_DAYS) % 4


static func season_id(day: int) -> String:
	return SEASON_IDS[season_index(day)]


static func season_name(day: int) -> String:
	return SEASON_NAMES[season_index(day)]


static func season_day(day: int) -> int:
	return (day - 1) % SEASON_DAYS + 1


## Название «вида» дня в атласе: деревья, кусты, трава и цветы меняются с ним.
static func look_name(day: int, snow: bool) -> String:
	match season_id(day):
		"spring":
			return "spring%02d" % season_day(day)
		"autumn":
			return "autumn%02d" % season_day(day)
		"summer":
			return "summer"
	return "wintersnow" if snow else "winter"
