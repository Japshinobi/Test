extends RefCounted
## Палитры игры из data/palette.json: «3d» — земля и всё объёмное, «2d» — персонажи, растения, предметы, эффекты.
## Рисунки атласа уже притянуты к палитрам при сборке (tools/export-atlas.mjs). Здесь то же делается
## для картинок, которые рисует сама игра: текстуры построек, цвета пыли и брызг.

static var _data: Dictionary
static var _ramps := {}      # палитра -> ряды цветов (от светлого к тёмному)
static var _memo := {}       # палитра -> цвет -> [ряд, ступень]


static func _load() -> void:
	if not _data.is_empty():
		return
	_data = JSON.parse_string(FileAccess.get_file_as_string("res://data/palette.json"))
	for k in ["3d", "2d"]:
		var list := []
		for ramp in _data[k].values():
			list.append(ramp.map(func(hex): return Color(hex)))
		_ramps[k] = list
		_memo[k] = {}


## Ряд и ступень ближайшего цвета палитры.
static func _nearest(c: Color, set_name: String) -> Array:
	_load()
	var key := c.to_rgba32() | 0xFF
	var m: Dictionary = _memo[set_name]
	if not m.has(key):
		var best := [0, 0]
		var bd := INF
		var ramps: Array = _ramps[set_name]
		for ri in ramps.size():
			for si in ramps[ri].size():
				var p: Color = ramps[ri][si]
				# «redmean»: расстояние, близкое к тому, как глаз различает цвета
				var rm := (c.r + p.r) * 0.5
				var d := (2.0 + rm) * (c.r - p.r) ** 2 + 4.0 * (c.g - p.g) ** 2 + (3.0 - rm) * (c.b - p.b) ** 2
				if d < bd:
					bd = d
					best = [ri, si]
		m[key] = best
	return m[key]


## Цвет из ряда палитры: ramp — материал ("wood", "cloth_red"…), i — 0 светлый … 3 тёмный.
static func col(set_name: String, ramp: String, i: int) -> Color:
	_load()
	var r: Array = _data[set_name][ramp]
	return Color(r[clampi(i, 0, r.size() - 1)])


## Ближайший цвет палитры (прозрачность сохраняется).
static func snap(c: Color, set_name: String) -> Color:
	var n := _nearest(c, set_name)
	var p: Color = _ramps[set_name][n[0]][n[1]]
	return Color(p.r, p.g, p.b, c.a)


## Притянуть все пиксели картинки к палитре. Разные цвета картинки, попавшие в одну ступень, раздвигаются
## по ряду (светлее — выше, темнее — ниже), чтобы узор не слился. Для небольших текстур (до 64×64).
static func quantize(img: Image, set_name: String) -> Image:
	var out := img.duplicate() as Image
	var count := {}
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				var key := c.to_rgba32() | 0xFF
				count[key] = count.get(key, 0) + 1
	var groups := {}
	for key in count:
		var n := _nearest(Color.hex(key), set_name)
		var gk: int = n[0] * 100 + n[1]
		if not groups.has(gk):
			groups[gk] = []
		groups[gk].append(key)
	var to := {}
	for gk in groups:
		var keys: Array = groups[gk]
		var ramp: Array = _ramps[set_name][gk / 100]
		var si: int = gk % 100
		keys.sort_custom(func(a, b): return count[a] > count[b])
		var main_l := Color.hex(keys[0]).get_luminance()
		to[keys[0]] = ramp[si]
		var lighter := keys.slice(1).filter(func(k): return Color.hex(k).get_luminance() >= main_l)
		var darker := keys.slice(1).filter(func(k): return Color.hex(k).get_luminance() < main_l)
		lighter.sort_custom(func(a, b): return Color.hex(a).get_luminance() < Color.hex(b).get_luminance())
		darker.sort_custom(func(a, b): return Color.hex(a).get_luminance() > Color.hex(b).get_luminance())
		for j in lighter.size():
			to[lighter[j]] = ramp[maxi(0, si - 1 - j)]
		for j in darker.size():
			to[darker[j]] = ramp[mini(ramp.size() - 1, si + 1 + j)]
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.0:
				var p: Color = to[c.to_rgba32() | 0xFF]
				out.set_pixel(x, y, Color(p.r, p.g, p.b, c.a))
	return out
