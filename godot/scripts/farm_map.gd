extends RefCounted
## Карта огорода. Та же, что в браузерной версии (game/index.html) и в Unity (OgorodCore.cs):
## деревья, камни и цветы раскладывает один и тот же «случайный» хеш, поэтому всё стоит на своих местах.
##
## Клетки: '.' трава, ',' цветы, '=' тропинка, 'P' место под постройку, '~' вода, 'T' дерево, 'B' куст,
## 'R' камень, 'K' ветки, 'H' дом, 'D' дверь, 'W' колодец, 'S' ящик для продажи, 'X' почтовый ящик,
## 'I' табличка, 'Y' большой дуб.

const W := 72
const H := 44
## Места под постройки: x0, y0, x1, y1 (теплица и три места под курятник или хлев).
const SITES := [[3, 12, 9, 17], [40, 28, 45, 32], [48, 28, 53, 32], [56, 28, 61, 32]]
## Двор вокруг дома: x0, y0, x1, y1.
const YARD := [10, 3, 17, 9]
## Выходы с огорода: x0, x1, y0, y1.
const EXITS := [[24, 25, 0, 0], [30, 31, 43, 43]]
const SIGNS := [Vector2i(7, 18), Vector2i(44, 26), Vector2i(52, 26), Vector2i(60, 26)]

const SEASON_DAYS := 12
const SEASON_IDS := ["spring", "summer", "autumn", "winter"]
const SEASON_NAMES := ["Весна", "Лето", "Осень", "Зима"]

var tiles := PackedStringArray()


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


func _init() -> void:
	tiles.resize(W * H)
	tiles.fill(".")
	for x in W:
		_set(x, 0, "T")
		_set(x, H - 1, "T")
	for y in H:
		_set(0, y, "T")
		_set(W - 1, y, "T")
	_build_farm()
	for e in EXITS:
		_rect(e[0], e[2], e[1], e[3], "=")
	for s in SIGNS:
		_set(s.x, s.y, "I")
	for y in range(1, H - 1):
		for x in range(1, W - 1):
			if at(x, y) == "." and hash3(x, y, 7 + W) < 0.09:
				_set(x, y, ",")


static func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < W and y < H


func at(x: int, y: int) -> String:
	return tiles[y * W + x] if inside(x, y) else "T"


func walkable(x: int, y: int) -> bool:
	return inside(x, y) and ".,=P".contains(at(x, y))


func _set(x: int, y: int, c: String) -> void:
	if inside(x, y):
		tiles[y * W + x] = c


func _rect(x0: int, y0: int, x1: int, y1: int, c: String) -> void:
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_set(x, y, c)


func _build_farm() -> void:
	_rect(12, 5, 15, 7, "H")
	_set(14, 7, "D")
	_set(19, 6, "W")
	_set(16, 7, "S")
	_set(12, 8, "X")
	_rect(14, 8, 14, 24, "=")
	_rect(14, 24, 67, 24, "=")
	_rect(66, 25, 67, 25, "=")
	_rect(68, 23, 70, 25, "Y")
	_rect(14, 8, 24, 8, "=")
	_rect(24, 0, 24, 8, "=")
	_rect(25, 0, 25, 1, "=")
	_rect(30, 24, 30, 43, "=")
	_rect(31, 42, 31, 43, "=")
	_rect(6, 18, 6, 23, "=")
	_rect(6, 24, 13, 24, "=")
	for x in [43, 51, 59]:
		_rect(x, 25, x, 27, "=")
	for t in SITES:
		_rect(t[0], t[1], t[2], t[3], "P")
	_rect(3, 31, 10, 37, "~")
	_rect(5, 30, 9, 30, "~")
	_rect(11, 33, 11, 36, "~")
	_rect(4, 38, 8, 38, "~")
	for y in range(1, 43):
		for x in range(1, 71):
			if _keep(x, y):
				continue
			var corner := (x > 58 and y < 14) or (x < 20 and y > 38) or (x > 60 and y > 34) or (x < 8 and y < 10)
			var r := hash3(x, y, 501)
			if r < (0.3 if corner else 0.035):
				_set(x, y, "T")
			elif r < (0.36 if corner else 0.05):
				_set(x, y, "B")
			elif r < (0.4 if corner else 0.075):
				_set(x, y, "R")
			elif r < (0.44 if corner else 0.095):
				_set(x, y, "K")
	for y in range(10, 23):
		for x in range(18, 57):
			if at(x, y) != ".":
				continue
			var r := hash3(x, y, 503)
			if r < 0.02:
				_set(x, y, "R")
			elif r < 0.035:
				_set(x, y, "K")


func _keep(x: int, y: int) -> bool:
	if at(x, y) != ".":
		return true
	if x >= YARD[0] - 1 and x <= YARD[2] + 1 and y >= YARD[1] - 1 and y <= YARD[3] + 1:
		return true
	for t in SITES:
		if x >= t[0] - 1 and x <= t[2] + 1 and y >= t[1] - 1 and y <= t[3] + 1:
			return true
	if x >= 18 and x <= 56 and y >= 10 and y <= 22:
		return true
	if y == 8 or y == 24 or x == 14 or x == 24 or x == 30:
		return true
	return _path(x - 1, y) or _path(x + 1, y) or _path(x, y - 1) or _path(x, y + 1)


func _path(x: int, y: int) -> bool:
	return inside(x, y) and at(x, y) == "="


## Карта текстом, построчно — для проверки, что она совпадает с браузерной.
func dump() -> String:
	var rows := PackedStringArray()
	for y in H:
		rows.append("".join(tiles.slice(y * W, (y + 1) * W)))
	return "\n".join(rows)
