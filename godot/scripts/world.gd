extends Node3D
## Огород в 3D в духе Ragnarok Online: земля и дом объёмные, деревья, кусты и персонажи — спрайты,
## которые всегда повёрнуты к камере. Одна клетка карты — один метр (одна единица Godot).
## Ось X — на восток, ось Z — на юг (вниз по карте), Y — вверх.

const Location := preload("res://scripts/location.gd")
const Atlas := preload("res://scripts/atlas.gd")
const Farm := preload("res://scripts/farm.gd")

const T := 16
## Камера смотрит сверху под углом, и стоячие спрайты кажутся приплюснутыми. Немного вытягиваем их вверх.
const STRETCH := 1.25
const BASIN := -0.45     # глубина пруда
const WATER_Y := -0.16   # уровень воды

var atlas: Atlas
var map: Location
var sprites: Array[Sprite3D] = []
var content: Node3D
var water_mat: StandardMaterial3D
var water_frames: Array[ImageTexture] = []
var _water_t := 0.0
var _water_frame := 0
var _tint := Color.WHITE
var _look := "summer"
var _flowers := {}        # клетка -> спрайт цветов (убирается, когда клетку вскопали)
var _plots := {}          # клетка -> узел грядки
var _drops := {}          # id -> {node, from, to, t, key}


func setup(p_atlas: Atlas, p_map: Location) -> void:
	atlas = p_atlas
	map = p_map
	_outer_ground()


## Пересобрать карту на день: земля, вода и спрайты зависят от времени года.
func build(day: int, farm: Farm) -> void:
	if content:
		content.free()
	content = Node3D.new()
	content.name = "Map"
	add_child(content)
	sprites.clear()
	_flowers.clear()
	_plots.clear()
	_drops.clear()
	var snow := Location.snow_cover(day)
	var look := Location.look_name(day, snow)
	_look = look
	var season := Location.season_id(day)
	_ground(look, snow)
	_water(season == "winter")

	for o in map.objects:
		var d := Location.def(o["id"])
		var size := Location.object_size(o["id"])
		if d.get("model", "") == "house":
			_house(o["x"], o["y"], size, d)
			continue
		if not d.has("sprite"):
			continue    # служебные метки: выход, старт игрока
		var sprite_name: String = d["sprite"]
		if d.get("seasonal", false):
			sprite_name += "_" + look
		elif snow and d.get("snow", false):
			sprite_name += "_snow"
		# спрайт стоит посередине нижнего ряда своих клеток
		_obj(sprite_name, Vector3(o["x"] + size.x / 2.0, 0, o["y"] + size.y - 0.5), d.get("shadow", true))

	# цветы растут на клетках «трава с цветами», где ничего не стоит
	if not snow and season != "winter":
		var flowers := "bloom" if season == "spring" else ("some" if season == "summer" else "wither")
		for y in map.H:
			for x in map.W:
				if map.ground_at(x, y) == "," and map.object_at(x, y) == null and farm.plot_at(x, y) == null:
					_flowers[Vector2i(x, y)] = _obj("flower_%s_%d" % [flowers, int(Location.hash3(x, y, 31) * 8)], Vector3(x + 0.5, 0, y + 0.5), false)
	for key in farm.plots:
		var xy: PackedStringArray = key.split(",")
		sync_plot(int(xy[0]), int(xy[1]), farm.plots[key])
	for id in farm.drops:
		var d: Dictionary = farm.drops[id]
		add_drop(id, d["item"], Vector3(d["x"], 0, d["z"]), Vector3(d["x"], 0, d["z"]))
	set_tint(_tint)


## Цвет дневного света. Спрайты не освещаются солнцем, поэтому подкрашиваем их сами.
func set_tint(c: Color) -> void:
	_tint = c
	for sp in sprites:
		sp.modulate = c
	for n in _plots.values():
		for ch in n.get_children():
			if ch is Sprite3D and ch.billboard != BaseMaterial3D.BILLBOARD_DISABLED:
				ch.modulate = c
	for d in _drops.values():
		d["node"].modulate = c


# ---------- грядки ----------

## Показать грядку так, как она сейчас: вскопанная (или политая) земля и растение на ней.
func sync_plot(x: int, y: int, p: Variant) -> void:
	var cell := Vector2i(x, y)
	if _plots.has(cell):
		_plots[cell].free()
		_plots.erase(cell)
	if _flowers.has(cell):
		var f: Sprite3D = _flowers[cell]
		sprites.erase(f)
		f.free()
		_flowers.erase(cell)
	if p == null:
		return
	var node := Node3D.new()
	node.position = Vector3(x + 0.5, 0, y + 0.5)
	content.add_child(node)
	_plots[cell] = node
	# земля лежит на земле: плоский спрайт, освещается солнцем как сама земля
	var soil := atlas.make_sprite("soilwet" if p["watered"] else "soil")
	soil.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	soil.axis = Vector3.AXIS_Y
	soil.centered = true
	soil.offset = Vector2.ZERO
	soil.shaded = true
	soil.position.y = 0.015
	soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(soil)
	if p["crop"] != "":
		var name: String
		if p["dead"]:
			name = "dead"
		elif Farm.crop(p["crop"]).get("tree", false):
			name = "crop_%s_%d_%s" % [p["crop"], Farm.stage(p), _look]
		else:
			name = "crop_%s_%d" % [p["crop"], Farm.stage(p)]
		if atlas.has(name):
			var sp := atlas.make_sprite(name)
			sp.scale = Vector3(1, STRETCH, 1)
			# у растений якорь внизу картинки, а сам кустик нарисован в её нижних 16 пикселях
			sp.position.z = 0.0
			sp.modulate = _tint
			node.add_child(sp)


# ---------- предметы на земле ----------

func add_drop(id: int, item: String, from: Vector3, to: Vector3) -> void:
	var sp := atlas.make_sprite(Farm.item_info(item)["icon"])
	sp.offset = Vector2(0, 8)
	sp.pixel_size = 0.7 / T
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.modulate = _tint
	sp.position = from
	content.add_child(sp)
	_drops[id] = {"node": sp, "from": from, "to": to, "t": 0.0 if from != to else 1.0, "item": item}


func remove_drop(id: int) -> void:
	if _drops.has(id):
		_drops[id]["node"].free()
		_drops.erase(id)


## Предметы тянутся к игроку, если он ближе полутора клеток. Возвращает id тех, что долетели до него.
func pull_drops(player: Vector3, delta: float, skip: Array) -> Array:
	var reached := []
	for id in _drops:
		var d: Dictionary = _drops[id]
		if d["t"] < 1.0 or id in skip:
			continue
		var pos: Vector3 = d["to"]
		var to := Vector3(player.x, 0, player.z) - pos
		var dist := to.length()
		if dist < 0.3:
			reached.append(id)
		elif dist < 1.5:
			d["to"] = pos + to.normalized() * minf(dist, (4.0 + (1.5 - dist) * 6.0) * delta)
	return reached


func drop_distance(id: int, player: Vector3) -> float:
	if not _drops.has(id):
		return INF
	var p: Vector3 = _drops[id]["to"]
	return Vector2(p.x - player.x, p.z - player.z).length()


func tick(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for id in _drops:
		var d: Dictionary = _drops[id]
		var n: Sprite3D = d["node"]
		if d["t"] < 1.0:
			# вылетают из грядки дугой
			d["t"] = minf(1.0, d["t"] + delta / 0.35)
			var u: float = d["t"]
			n.position = d["from"].lerp(d["to"], u) + Vector3(0, sin(u * PI) * 0.45, 0)
		else:
			n.position = d["to"] + Vector3(0, 0.04 + 0.04 * sin(now * 3.3 + float(id)), 0)
	if water_frames.size() > 1:
		_water_t += delta
		if _water_t > 0.3:
			_water_t = 0.0
			_water_frame = (_water_frame + 1) % water_frames.size()
			water_mat.albedo_texture = water_frames[_water_frame]


func _obj(sprite_name: String, pos: Vector3, shadow := true) -> Sprite3D:
	if not atlas.has(sprite_name):
		push_warning("Нет спрайта " + sprite_name)
		return null
	var sp := atlas.make_sprite(sprite_name)
	sp.position = pos
	sp.scale = Vector3(1, STRETCH, 1)
	if not shadow:
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	content.add_child(sp)
	sprites.append(sp)
	return sp


# ---------- земля ----------

func _is_water(x: int, y: int) -> bool:
	return map.ground_at(x, y) == "~"


## Высота угла клетки: внутри пруда земля опускается, у берега получается склон.
func _height(x: int, y: int) -> float:
	if _is_water(x - 1, y - 1) and _is_water(x, y - 1) and _is_water(x - 1, y) and _is_water(x, y):
		return BASIN
	return 0.0


func _ground(look: String, snow: bool) -> void:
	var img := Image.create(map.W * T, map.H * T, false, Image.FORMAT_RGBA8)
	for y in map.H:
		for x in map.W:
			var c := map.ground_at(x, y)
			var v := int(Location.hash3(x, y, 3) * 4)
			var tile: String
			if c == "~":
				tile = "path_0"
			elif snow:
				tile = "snow_%d" % v
			elif c == "=":
				tile = "path_%d" % v
			elif c == "P":
				tile = "site_%d" % v
			else:
				tile = "grass_%s_%d" % [look, v]
			if c == "#":
				img.fill_rect(Rect2i(x * T, y * T, T, T), Color("#1b1d22"))    # непроходимо: тёмная земля
				continue
			img.blit_rect(atlas.image, atlas.rect(tile), Vector2i(x * T, y * T))
	img.generate_mipmaps()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in map.H:
		for x in map.W:
			var a := _corner(x, y)
			var b := _corner(x + 1, y)
			var c := _corner(x + 1, y + 1)
			var d := _corner(x, y + 1)
			for v in [a, b, c, a, c, d]:
				st.set_normal(v[2])
				st.set_uv(v[1])
				st.add_vertex(v[0])
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = st.commit()
	mi.material_override = mat
	content.add_child(mi)


func _corner(x: int, y: int) -> Array:
	var h := _height(x, y)
	var n := Vector3(_height(x - 1, y) - _height(x + 1, y), 2.0, _height(x, y - 1) - _height(x, y + 1)).normalized()
	return [Vector3(x, h, y), Vector2(float(x) / map.W, float(y) / map.H), n]


## Земля за краем карты, чтобы вокруг не было пустоты.
func _outer_ground() -> void:
	# Рамка вокруг карты, а не сплошной лист под ней: иначе она закрыла бы низины вроде пруда.
	const PAD := 200.0
	var w := float(map.W)
	var h := float(map.H)
	var st := _surface()
	for r in [Rect2(-PAD, -PAD, w + 2 * PAD, PAD), Rect2(-PAD, h, w + 2 * PAD, PAD), Rect2(-PAD, 0, PAD, h), Rect2(w, 0, PAD, h)]:
		var y := -0.03
		quad(st, Vector3(r.position.x, y, r.position.y), Vector3(r.end.x, y, r.position.y), Vector3(r.end.x, y, r.end.y), Vector3(r.position.x, y, r.end.y),
			Rect2(0, 0, 1, 1), Vector3.UP)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#3f6b34")
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "OuterGround"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------- вода ----------

func _water(winter: bool) -> void:
	water_frames.clear()
	var x0 := map.W
	var y0 := map.H
	var x1 := -1
	var y1 := -1
	for y in map.H:
		for x in map.W:
			if _is_water(x, y):
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return
	for f in (1 if winter else 4):
		var img := Image.create((x1 - x0 + 1) * T, (y1 - y0 + 1) * T, false, Image.FORMAT_RGBA8)
		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				if _is_water(x, y):
					var tile := "ice_%d" % ((x + y) % 4) if winter else "water_%d_%d" % [(x + y) % 4, f]
					img.blit_rect(atlas.image, atlas.rect(tile), Vector2i((x - x0) * T, (y - y0) * T))
		water_frames.append(ImageTexture.create_from_image(img))
	water_mat = StandardMaterial3D.new()
	water_mat.albedo_texture = water_frames[0]
	water_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR if winter else BaseMaterial3D.TRANSPARENCY_ALPHA
	if not winter:
		water_mat.albedo_color = Color(1, 1, 1, 0.82)
		water_mat.roughness = 0.25
		water_mat.metallic_specular = 0.7
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	quad(st, Vector3(x0, WATER_Y, y0), Vector3(x1 + 1, WATER_Y, y0), Vector3(x1 + 1, WATER_Y, y1 + 1), Vector3(x0, WATER_Y, y1 + 1),
		Rect2(0, 0, 1, 1), Vector3.UP)
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = st.commit()
	mi.material_override = water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	content.add_child(mi)


## Четырёхугольник a-b-c-d (по кругу) с текстурой из прямоугольника uv: a — левый верх картинки.
static func quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, uv: Rect2, n: Vector3) -> void:
	var ua := uv.position
	var ub := Vector2(uv.end.x, uv.position.y)
	var uc := uv.end
	var ud := Vector2(uv.position.x, uv.end.y)
	for v in [[a, ua], [b, ub], [c, uc], [a, ua], [c, uc], [d, ud]]:
		st.set_normal(n)
		st.set_uv(v[1])
		st.add_vertex(v[0])


static func tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, n: Vector3) -> void:
	for v in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(n)
		st.set_uv(v[1])
		st.add_vertex(v[0])


# ---------- дом ----------
# Дом строится по своему месту на карте: занимает size клеток, дверь смотрит на юг (вниз по карте).

const WALL := 2.0
const RIDGE := 3.3
const EAVE := 0.3


func _house(x: int, y: int, size: Vector2i, d: Dictionary) -> void:
	var house := Node3D.new()
	house.name = "House"
	house.position = Vector3(x, 0, y)
	content.add_child(house)
	# дальше всё в клетках относительно левого верхнего угла дома
	var HX0 := 0.0
	var HX1 := float(size.x)
	var HZ0 := 0.0
	var HZ1 := float(size.y)
	var door: Array = d.get("door", [size.x / 2, size.y - 1])
	var dx := float(door[0])
	var zm := (HZ0 + HZ1) / 2.0

	# стены и фронтоны
	var st := _surface()
	quad(st, Vector3(HX0, WALL, HZ1), Vector3(HX1, WALL, HZ1), Vector3(HX1, 0, HZ1), Vector3(HX0, 0, HZ1), Rect2(0, 0, HX1, 2), Vector3.BACK)
	quad(st, Vector3(HX1, WALL, HZ0), Vector3(HX0, WALL, HZ0), Vector3(HX0, 0, HZ0), Vector3(HX1, 0, HZ0), Rect2(0, 0, HX1, 2), Vector3.FORWARD)
	quad(st, Vector3(HX0, WALL, HZ0), Vector3(HX0, WALL, HZ1), Vector3(HX0, 0, HZ1), Vector3(HX0, 0, HZ0), Rect2(0, 0, HZ1, 2), Vector3.LEFT)
	quad(st, Vector3(HX1, WALL, HZ1), Vector3(HX1, WALL, HZ0), Vector3(HX1, 0, HZ0), Vector3(HX1, 0, HZ1), Rect2(0, 0, HZ1, 2), Vector3.RIGHT)
	var gv := RIDGE - WALL
	tri(st, Vector3(HX0, WALL, HZ0), Vector3(HX0, WALL, HZ1), Vector3(HX0, RIDGE, zm), Vector2(0, gv), Vector2(HZ1, gv), Vector2(zm, 0), Vector3.LEFT)
	tri(st, Vector3(HX1, WALL, HZ1), Vector3(HX1, WALL, HZ0), Vector3(HX1, RIDGE, zm), Vector2(0, gv), Vector2(HZ1, gv), Vector2(zm, 0), Vector3.RIGHT)
	_add_mesh(house, st, _material(_planks()))

	# крыша: два ската с напуском над стенами
	var slope := (RIDGE - WALL) / (zm - HZ0)
	var ey := WALL - EAVE * slope
	var length := Vector2(zm - HZ0 + EAVE, RIDGE - ey).length()
	st = _surface()
	quad(st, Vector3(HX0 - EAVE, RIDGE, zm), Vector3(HX1 + EAVE, RIDGE, zm), Vector3(HX1 + EAVE, ey, HZ1 + EAVE), Vector3(HX0 - EAVE, ey, HZ1 + EAVE),
		Rect2(0, 0, HX1 - HX0 + 2 * EAVE, length), Vector3(0, zm - HZ0, RIDGE - WALL).normalized())
	quad(st, Vector3(HX1 + EAVE, RIDGE, zm), Vector3(HX0 - EAVE, RIDGE, zm), Vector3(HX0 - EAVE, ey, HZ0 - EAVE), Vector3(HX1 + EAVE, ey, HZ0 - EAVE),
		Rect2(0, 0, HX1 - HX0 + 2 * EAVE, length), Vector3(0, zm - HZ0, -(RIDGE - WALL)).normalized())
	_add_mesh(house, st, _material(_shingles()))

	# дверь и окна — чуть впереди стены
	st = _surface()
	quad(st, Vector3(dx + 0.1, 1.5, HZ1 + 0.02), Vector3(dx + 0.92, 1.5, HZ1 + 0.02), Vector3(dx + 0.92, 0, HZ1 + 0.02), Vector3(dx + 0.1, 0, HZ1 + 0.02), Rect2(0, 0, 1, 1), Vector3.BACK)
	_add_mesh(house, st, _material(_door(), true))
	st = _surface()
	quad(st, Vector3(0.55, 1.4, HZ1 + 0.02), Vector3(1.3, 1.4, HZ1 + 0.02), Vector3(1.3, 0.78, HZ1 + 0.02), Vector3(0.55, 0.78, HZ1 + 0.02), Rect2(0, 0, 1, 1), Vector3.BACK)
	quad(st, Vector3(HX1 + 0.02, 1.4, zm + 0.4), Vector3(HX1 + 0.02, 1.4, zm - 0.35), Vector3(HX1 + 0.02, 0.78, zm - 0.35), Vector3(HX1 + 0.02, 0.78, zm + 0.4), Rect2(0, 0, 1, 1), Vector3.RIGHT)
	quad(st, Vector3(HX0 - 0.02, 1.4, zm - 0.4), Vector3(HX0 - 0.02, 1.4, zm + 0.35), Vector3(HX0 - 0.02, 0.78, zm + 0.35), Vector3(HX0 - 0.02, 0.78, zm - 0.4), Rect2(0, 0, 1, 1), Vector3.LEFT)
	_add_mesh(house, st, _material(_window(), true))

	# печная труба
	st = _surface()
	_box(st, Vector3(HX1 - 1.3, 2.4, zm - 0.9), Vector3(HX1 - 0.75, 3.85, zm - 0.4))
	_add_mesh(house, st, _material(_stone()))


func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var sx := hi.x - lo.x
	var sy := hi.y - lo.y
	var sz := hi.z - lo.z
	quad(st, Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z), Rect2(0, 0, sx, sy), Vector3.BACK)
	quad(st, Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Rect2(0, 0, sx, sy), Vector3.FORWARD)
	quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Rect2(0, 0, sz, sy), Vector3.LEFT)
	quad(st, Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Rect2(0, 0, sz, sy), Vector3.RIGHT)
	quad(st, Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Rect2(0, 0, sx, sz), Vector3.UP)


func _surface() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _add_mesh(parent: Node3D, st: SurfaceTool, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	parent.add_child(mi)


func _material(img: Image, cutout := false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if cutout:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	return mat


# ---------- пиксельные текстуры дома: 16 пикселей на метр, как у спрайтов ----------

static func _img(w: int, h: int, fill: Color) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(fill)
	return img


## Старые доски: светлый верхний край, тёмный шов снизу, стыки вразбивку.
static func _planks() -> Image:
	var img := _img(16, 16, Color("#8a5a33"))
	for row in 4:
		var y := row * 4
		img.fill_rect(Rect2i(0, y, 16, 1), Color("#a5703f"))
		img.fill_rect(Rect2i(0, y + 3, 16, 1), Color("#5e3b20"))
		img.fill_rect(Rect2i((row * 7 + 3) % 16, y, 1, 4), Color("#5e3b20"))
		img.set_pixel((row * 11 + 9) % 16, y + 2, Color("#734a29"))
	return img


static func _shingles() -> Image:
	var img := _img(16, 16, Color("#9c3f2f"))
	for row in 4:
		var y := row * 4
		img.fill_rect(Rect2i(0, y + 3, 16, 1), Color("#6b2820"))
		img.fill_rect(Rect2i(0, y, 16, 1), Color("#b55a40"))
		for k in 2:
			var x := ((row % 2) * 4 + k * 8) % 16
			img.fill_rect(Rect2i(x, y, 1, 3), Color("#6b2820"))
	return img


static func _door() -> Image:
	var img := _img(13, 24, Color("#4a2f1d"))
	img.fill_rect(Rect2i(1, 1, 11, 23), Color("#7a4a28"))
	for x in [4, 8]:
		img.fill_rect(Rect2i(x, 1, 1, 23), Color("#5c361d"))
	img.fill_rect(Rect2i(1, 6, 11, 1), Color("#5c361d"))
	img.fill_rect(Rect2i(1, 17, 11, 1), Color("#5c361d"))
	img.fill_rect(Rect2i(10, 12, 1, 2), Color("#f0bf45"))
	return img


static func _window() -> Image:
	var img := _img(12, 10, Color("#4a2f1d"))
	img.fill_rect(Rect2i(1, 1, 10, 8), Color("#8fc7e8"))
	img.fill_rect(Rect2i(1, 1, 4, 2), Color("#c9e8f7"))
	img.fill_rect(Rect2i(6, 1, 1, 8), Color("#4a2f1d"))
	img.fill_rect(Rect2i(1, 5, 10, 1), Color("#4a2f1d"))
	return img


static func _stone() -> Image:
	var img := _img(16, 16, Color("#7f7f86"))
	for row in 4:
		var y := row * 4
		img.fill_rect(Rect2i(0, y + 3, 16, 1), Color("#55555c"))
		img.fill_rect(Rect2i(0, y, 16, 1), Color("#9a9aa2"))
		img.fill_rect(Rect2i(((row % 2) * 5 + 2) % 16, y, 1, 3), Color("#55555c"))
		img.fill_rect(Rect2i(((row % 2) * 5 + 10) % 16, y, 1, 3), Color("#55555c"))
	return img
