extends RefCounted
## Локация: карта из файла maps/<id>.json, который правится редактором карт (editor/map-editor.html).
## В файле два слоя: земля (по символу на клетку) и список объектов. Что значат символы земли и какие
## бывают объекты, описано в каталоге data/objects.json — его читают и игра, и редактор.

const SEASON_DAYS := 12
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]
const SEASON_NAMES := ["Весна", "Лето", "Осень", "Зима"]

static var _catalog: Dictionary

var id := ""
var title := ""
var W := 0
var H := 0
var ground := PackedStringArray()
## Объекты: словари {id, x, y} и, если нужно, {text} у таблички или {to} у выхода.
var objects: Array = []
var _cover: Array = []          # какой объект занимает клетку (или null)
var _walk_ground := {}


func _init(map_id: String) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://maps/%s.json" % map_id))
	id = map_id
	title = data.get("name", map_id)
	W = int(data["width"])
	H = int(data["height"])
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
		var size := object_size(o["id"])
		for dy in size.y:
			for dx in size.x:
				if inside(o["x"] + dx, o["y"] + dy):
					_cover[(o["y"] + dy) * W + o["x"] + dx] = o


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
func object_at(x: int, y: int) -> Variant:
	return _cover[y * W + x] if inside(x, y) else null


func walkable(x: int, y: int) -> bool:
	if not inside(x, y) or not _walk_ground.get(ground_at(x, y), true):
		return false
	var o: Variant = object_at(x, y)
	return o == null or not def(o["id"]).get("block", true)


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


## Примерно через день зимой идёт снег; к утру он ложится.
static func snowing(day: int) -> bool:
	return day >= 1 and season_id(day) == "winter" and hash3(day, 5, 77) < 0.5


static func snow_cover(day: int) -> bool:
	return season_id(day) == "winter" and snowing(day - 1)


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
