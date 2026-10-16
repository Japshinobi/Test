extends Node3D
## Огород в 3D в духе Ragnarok Online: земля и дом объёмные, деревья, кусты и персонажи — спрайты,
## которые всегда повёрнуты к камере. Одна клетка карты — один метр (одна единица Godot).
## Ось X — на восток, ось Z — на юг (вниз по карте), Y — вверх.

const FarmMap := preload("res://scripts/farm_map.gd")
const Atlas := preload("res://scripts/atlas.gd")

const T := 16
## Камера смотрит сверху под углом, и стоячие спрайты кажутся приплюснутыми. Немного вытягиваем их вверх.
const STRETCH := 1.25
const BASIN := -0.45     # глубина пруда
const WATER_Y := -0.16   # уровень воды

var atlas: Atlas
var map: FarmMap
var sprites: Array[Sprite3D] = []
var content: Node3D
var water_mat: StandardMaterial3D
var water_frames: Array[ImageTexture] = []
var _water_t := 0.0
var _water_frame := 0
var _tint := Color.WHITE


func setup(p_atlas: Atlas, p_map: FarmMap) -> void:
	atlas = p_atlas
	map = p_map
	_outer_ground()
	_house()


## Пересобрать карту на день: земля, вода и спрайты зависят от времени года.
func build(day: int) -> void:
	if content:
		content.free()
	content = Node3D.new()
	content.name = "Map"
	add_child(content)
	sprites.clear()
	var snow := FarmMap.snow_cover(day)
	var look := FarmMap.look_name(day, snow)
	var season := FarmMap.season_id(day)
	_ground(look, snow)
	_water(season == "winter")

	var sfx := "_snow" if snow else ""
	var flowers := "bloom" if season == "spring" else ("some" if season == "summer" else "wither")
	for y in FarmMap.H:
		for x in FarmMap.W:
			var p := Vector3(x + 0.5, 0, y + 0.5)
			match map.at(x, y):
				"T":
					_obj("tree%d_%s" % [1 if FarmMap.hash3(x, y, 11) < 0.35 else 0, look], p)
				"B":
					_obj("bush_" + look, p)
				"W":
					_obj("well" + sfx, p)
				"S":
					_obj("bin" + sfx, p)
				"X":
					_obj("mailbox" + sfx, p)
				"I":
					_obj("sign" + sfx, p)
				"R":
					_obj("rock" + sfx, p)
				"K":
					_obj("twigs" + sfx, p, false)
				",":
					if not snow and season != "winter":
						_obj("flower_%s_%d" % [flowers, int(FarmMap.hash3(x, y, 31) * 8)], p, false)
	_obj("bigtree_" + look, Vector3(69.5, 0, 25.2))
	for t in FarmMap.SITES:
		for c in [[t[0], t[1]], [t[2], t[1]], [t[0], t[3]], [t[2], t[3]]]:
			_obj("stake" + sfx, Vector3(c[0] + 0.5, 0, c[1] + 0.5), false)
	set_tint(_tint)


## Цвет дневного света. Спрайты не освещаются солнцем, поэтому подкрашиваем их сами.
func set_tint(c: Color) -> void:
	_tint = c
	for sp in sprites:
		sp.modulate = c


func tick(delta: float) -> void:
	if water_frames.size() > 1:
		_water_t += delta
		if _water_t > 0.3:
			_water_t = 0.0
			_water_frame = (_water_frame + 1) % water_frames.size()
			water_mat.albedo_texture = water_frames[_water_frame]


func _obj(sprite_name: String, pos: Vector3, shadow := true) -> void:
	if not atlas.has(sprite_name):
		push_warning("Нет спрайта " + sprite_name)
		return
	var sp := atlas.make_sprite(sprite_name)
	sp.position = pos
	sp.scale = Vector3(1, STRETCH, 1)
	if not shadow:
		sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	content.add_child(sp)
	sprites.append(sp)


# ---------- земля ----------

func _is_water(x: int, y: int) -> bool:
	return FarmMap.inside(x, y) and map.at(x, y) == "~"


## Высота угла клетки: внутри пруда земля опускается, у берега получается склон.
func _height(x: int, y: int) -> float:
	if _is_water(x - 1, y - 1) and _is_water(x, y - 1) and _is_water(x - 1, y) and _is_water(x, y):
		return BASIN
	return 0.0


func _ground(look: String, snow: bool) -> void:
	var img := Image.create(FarmMap.W * T, FarmMap.H * T, false, Image.FORMAT_RGBA8)
	for y in FarmMap.H:
		for x in FarmMap.W:
			var c := map.at(x, y)
			var v := int(FarmMap.hash3(x, y, 3) * 4)
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
			img.blit_rect(atlas.image, atlas.rect(tile), Vector2i(x * T, y * T))
	img.generate_mipmaps()

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in FarmMap.H:
		for x in FarmMap.W:
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
	return [Vector3(x, h, y), Vector2(float(x) / FarmMap.W, float(y) / FarmMap.H), n]


## Земля за краем карты, чтобы вокруг не было пустоты.
func _outer_ground() -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(400, 400)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#3f6b34")
	mat.roughness = 1.0
	mat.metallic_specular = 0.0
	var mi := MeshInstance3D.new()
	mi.name = "OuterGround"
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = Vector3(FarmMap.W / 2.0, -0.03, FarmMap.H / 2.0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ---------- вода ----------

func _water(winter: bool) -> void:
	water_frames.clear()
	var x0 := FarmMap.W
	var y0 := FarmMap.H
	var x1 := -1
	var y1 := -1
	for y in FarmMap.H:
		for x in FarmMap.W:
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
# Дом стоит на клетках x 12..15, y 5..7 (как в браузерной версии), дверь на клетке (14, 7) смотрит на юг.

const HX0 := 12.0
const HX1 := 16.0
const HZ0 := 5.0
const HZ1 := 8.0
const WALL := 2.0
const RIDGE := 3.3
const EAVE := 0.3


func _house() -> void:
	var house := Node3D.new()
	house.name = "House"
	add_child(house)
	var zm := (HZ0 + HZ1) / 2.0

	# стены и фронтоны
	var st := _surface()
	quad(st, Vector3(HX0, WALL, HZ1), Vector3(HX1, WALL, HZ1), Vector3(HX1, 0, HZ1), Vector3(HX0, 0, HZ1), Rect2(0, 0, 4, 2), Vector3.BACK)
	quad(st, Vector3(HX1, WALL, HZ0), Vector3(HX0, WALL, HZ0), Vector3(HX0, 0, HZ0), Vector3(HX1, 0, HZ0), Rect2(0, 0, 4, 2), Vector3.FORWARD)
	quad(st, Vector3(HX0, WALL, HZ0), Vector3(HX0, WALL, HZ1), Vector3(HX0, 0, HZ1), Vector3(HX0, 0, HZ0), Rect2(0, 0, 3, 2), Vector3.LEFT)
	quad(st, Vector3(HX1, WALL, HZ1), Vector3(HX1, WALL, HZ0), Vector3(HX1, 0, HZ0), Vector3(HX1, 0, HZ1), Rect2(0, 0, 3, 2), Vector3.RIGHT)
	var gv := RIDGE - WALL
	tri(st, Vector3(HX0, WALL, HZ0), Vector3(HX0, WALL, HZ1), Vector3(HX0, RIDGE, zm), Vector2(0, gv), Vector2(3, gv), Vector2(1.5, 0), Vector3.LEFT)
	tri(st, Vector3(HX1, WALL, HZ1), Vector3(HX1, WALL, HZ0), Vector3(HX1, RIDGE, zm), Vector2(0, gv), Vector2(3, gv), Vector2(1.5, 0), Vector3.RIGHT)
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
	quad(st, Vector3(14.1, 1.5, HZ1 + 0.02), Vector3(14.92, 1.5, HZ1 + 0.02), Vector3(14.92, 0, HZ1 + 0.02), Vector3(14.1, 0, HZ1 + 0.02), Rect2(0, 0, 1, 1), Vector3.BACK)
	_add_mesh(house, st, _material(_door(), true))
	st = _surface()
	quad(st, Vector3(12.55, 1.4, HZ1 + 0.02), Vector3(13.3, 1.4, HZ1 + 0.02), Vector3(13.3, 0.78, HZ1 + 0.02), Vector3(12.55, 0.78, HZ1 + 0.02), Rect2(0, 0, 1, 1), Vector3.BACK)
	quad(st, Vector3(HX1 + 0.02, 1.4, 6.9), Vector3(HX1 + 0.02, 1.4, 6.15), Vector3(HX1 + 0.02, 0.78, 6.15), Vector3(HX1 + 0.02, 0.78, 6.9), Rect2(0, 0, 1, 1), Vector3.RIGHT)
	quad(st, Vector3(HX0 - 0.02, 1.4, 6.1), Vector3(HX0 - 0.02, 1.4, 6.85), Vector3(HX0 - 0.02, 0.78, 6.85), Vector3(HX0 - 0.02, 0.78, 6.1), Rect2(0, 0, 1, 1), Vector3.LEFT)
	_add_mesh(house, st, _material(_window(), true))

	# печная труба
	st = _surface()
	_box(st, Vector3(14.7, 2.4, 5.6), Vector3(15.25, 3.85, 6.1))
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
