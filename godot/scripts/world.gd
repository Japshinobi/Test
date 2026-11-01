extends Node3D
## Огород в 3D в духе Ragnarok Online: земля и дом объёмные, деревья, кусты и персонажи — спрайты,
## которые всегда повёрнуты к камере. Одна клетка карты — один метр (одна единица Godot).
## Ось X — на восток, ось Z — на юг (вниз по карте), Y — вверх.

const Location := preload("res://scripts/location.gd")
const Atlas := preload("res://scripts/atlas.gd")
const Farm := preload("res://scripts/farm.gd")
const Palette := preload("res://scripts/palette.gd")

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
var _cell_sprites := {}   # клетка, где стоит объект -> его спрайт (чтобы убрать срубленное)
var _shake := {}          # спрайт -> сколько ещё качаться
var _shops := []          # прилавки: {sprite, name} — открыты или закрыты по часам рынка
var _small_waters := []   # вода в фонтанах: {mat, frames} — кадры меняются, как в пруду
var _small_water_t := 0.0
var _snow := false
var _day := 1
var _trod_tex := {}       # картинка протоптанной клетки по названию земли под снегом
var _market_open := false
var _strikes := []        # удары молнии: {bolt, fire, trace, t, fire_s, trace_s} — живут несколько секунд


func setup(p_atlas: Atlas, p_map: Location) -> void:
	atlas = p_atlas
	map = p_map


## Пересобрать локацию на день: земля, вода и спрайты зависят от времени года.
func build(day: int, farm: Farm, p_map: Location, market_open: bool) -> void:
	map = p_map
	map.season = Location.season_id(day)
	_market_open = market_open
	if content:
		content.free()
	content = Node3D.new()
	content.name = "Map"
	add_child(content)
	sprites.clear()
	_mats.clear()
	_flowers.clear()
	_plots.clear()
	_drops.clear()
	_shops.clear()
	_small_waters.clear()
	_strikes.clear()
	_cell_sprites.clear()
	_shake.clear()
	var snow: bool = farm.snow and Location.season_id(day) == "winter"
	_snow = snow
	_day = day
	var look := Location.look_name(day, snow)
	_look = look
	var season := Location.season_id(day)
	_outer_ground()
	_ground(look, snow, day)
	_water(season == "winter")

	for o in map.objects:
		var d := Location.def(o["id"])
		var size := Location.object_size(o["id"])
		if d.get("model", "") == "house":
			_house(o["x"], o["y"], size, d)
			continue
		if d.get("model", "") == "stall" or d.get("model", "") == "tent":
			_shop(o, d, size, snow, market_open)
			continue
		if d.get("model", "") == "fountain":
			_fountain(o, size, season == "winter", snow)
			continue
		if d.get("model", "") == "well":
			_well(o, season == "winter", snow)
			continue
		if d.get("model", "") in ["bin", "mailbox", "sign", "signpost", "barrier"]:
			_prop(o, d, size, snow)
			continue
		if not d.has("sprite") or not map.in_season(o):
			continue    # служебные метки (выход, старт игрока) и объекты не своего сезона
		var sprite_name := sprite_for(o, look, snow, market_open)
		# спрайт стоит посередине нижнего ряда своих клеток
		var sp := _obj(sprite_name, Vector3(o["x"] + size.x / 2.0, 0, o["y"] + size.y - 0.5), d.get("shadow", true))
		if sp == null:
			continue
		_cell_sprites[Vector2i(o["x"], o["y"])] = sp
		if d.get("shop", false):
			_shops.append({"sprite": sp, "obj": o})

	# цветы растут на клетках «трава с цветами», где ничего не стоит
	if not snow and season != "winter":
		var flowers := "bloom" if season == "spring" else ("some" if season == "summer" else "wither")
		for y in map.H:
			for x in map.W:
				if map.has_flowers(x, y) and not (map.id == "farm" and farm.plot_at(x, y) != null):
					_flowers[Vector2i(x, y)] = _obj("flower_%s_%d" % [flowers, int(Location.hash3(x, y, 31) * 8)], Vector3(x + 0.5, 0, y + 0.5), false)
	# подсолнухи на соседских полях: через клетку, летом растут, осенью отцветают
	if not snow and (season == "summer" or season == "autumn"):
		var stage := 2 if season == "autumn" else (0 if Location.season_day(day) < 4 else 1)
		for y in map.H:
			for x in map.W:
				if (map.ground_at(x, y) == "N" or map.ground_at(x, y) == "n") and (x + y) % 2 == 0 and map.object_at(x, y) == null:
					_obj("sunflower_%d" % stage, Vector3(x + 0.5, 0, y + 0.5))
	if snow:
		for key in farm.snow_trod.get(map.id, {}):
			var xy: PackedStringArray = String(key).split(",")
			add_trod(int(xy[0]), int(xy[1]))
	if map.id == "farm":
		for key in farm.plots:
			var xy: PackedStringArray = key.split(",")
			sync_plot(int(xy[0]), int(xy[1]), farm.plots[key])
	for id in farm.drops:
		var d: Dictionary = farm.drops[id]
		if d.get("loc", "farm") == map.id:
			add_drop(id, d["item"], Vector3(d["x"], 0, d["z"]), Vector3(d["x"], 0, d["z"]))
	set_tint(_tint)


## Имя спрайта объекта с учётом сезона, снега и (для прилавков) торговца и часов рынка.
func sprite_for(o: Dictionary, look: String, snow: bool, market_open: bool) -> String:
	var d := Location.def(o["id"])
	var name: String = d["sprite"]
	if d.get("seasonal", false):
		return name + "_" + look
	if d.get("shop", false):
		var who: String = o.get("trader", "")
		name += "_%s_%d" % [who if who != "" else "empty", 1 if market_open and who != "" else 0]
	if snow and d.get("snow", false):
		name += "_snow"
	return name


## Клетка изменилась (срубили, разбили, скосили): убрать старый спрайт и поставить новый, если есть что ставить.
func update_cell(x: int, y: int) -> void:
	var cell := Vector2i(x, y)
	for dict in [_cell_sprites, _flowers]:
		if dict.has(cell):
			var old: Sprite3D = dict[cell]
			sprites.erase(old)
			_shake.erase(old)
			old.free()
			dict.erase(cell)
	var o: Variant = map.object_at(x, y)
	if o != null and o["x"] == x and o["y"] == y and Location.def(o["id"]).has("sprite") and not Location.def(o["id"]).has("model"):
		var size := Location.object_size(o["id"])
		var d := Location.def(o["id"])
		var sp := _obj(sprite_for(o, _look, _snow, _market_open), Vector3(x + size.x / 2.0, 0, y + size.y - 0.5), d.get("shadow", true))
		if sp:
			sp.modulate = _tint
			_cell_sprites[cell] = sp


## Протоптанный снег: на клетке видна земля под снегом и следы.
func add_trod(x: int, y: int) -> void:
	if not _snow:
		return
	var bare := _tile_name(x, y, Location.look_name(_day, false), false, _day)
	if bare == "":
		return
	var v := (x + y) % 4
	var key := "%s|%d" % [bare, v]
	if not _trod_tex.has(key):
		var img := atlas.image.get_region(atlas.rect(bare))
		img.blend_rect(atlas.image, atlas.rect("trodden_%d" % v), Vector2i.ZERO)
		_trod_tex[key] = ImageTexture.create_from_image(img)
	var sp := Sprite3D.new()
	sp.texture = _trod_tex[key]
	sp.pixel_size = 1.0 / T
	sp.axis = Vector3.AXIS_Y
	sp.shaded = true
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.position = Vector3(x + 0.5, 0.008, y + 0.5)
	content.add_child(sp)


## Удар инструментом: объект качается, вокруг поднимается пыль.
func hit_fx(x: int, y: int, kind: String) -> void:
	var sp: Sprite3D = _cell_sprites.get(Vector2i(x, y))
	if sp:
		_shake[sp] = 0.22
	var colors := {"chop": Color("#c99a66"), "mine": Color("#b8b8c0"), "mow": Color("#f5d33b"), "till": Color("#7a5236"), "water": Color("#9cc8f4")}
	puff(Vector3(x + 0.5, 0.3, y + 0.5), Palette.snap(colors.get(kind, Color.WHITE), "2d"))


## Облачко пыли или брызг: несколько квадратиков разлетаются и падают.
func puff(at: Vector3, color: Color, n := 8) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = n
	p.lifetime = 0.5
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 70.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.2
	p.gravity = Vector3(0, -6, 0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.09, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color * _tint
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	p.mesh = mesh
	p.position = at
	content.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Рынок открылся или закрылся: торговцы появляются за прилавками или прилавки закрываются ставнями.
func set_market_open(open: bool) -> void:
	if open == _market_open:
		return
	_market_open = open
	for s in _shops:
		if s.has("open_node"):
			_show_shop(s, open)
			continue
		var name := sprite_for(s["obj"], _look, _snow, open)
		if atlas.has(name):
			s["sprite"].region_rect = Rect2(atlas.rect(name))


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
	# грядки рисуются только на огороде: изменение грядки приходит всем, где бы игрок ни был
	if map == null or map.id != "farm":
		return
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
	soil.material_override = null
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
			name = "dead_snow" if _snow else "dead"
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


## Удар молнии в клетку: яркий штрих с неба, огонь fire секунд, потом горелый след ещё trace секунд.
## Огонь и след пока простые (искры и тёмное пятно) — свои рисунки на этапе 3.
func strike_fx(x: int, y: int, fire: float, trace: float) -> void:
	var at := Vector3(x + 0.5, 0, y + 0.5)
	var bolt := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.12, 16.0, 0.12)
	bolt.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 0.95, 1.0)
	bolt.material_override = mat
	bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bolt.position = at + Vector3(0, 8.0, 0)
	content.add_child(bolt)
	var trace_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(0.9, 0.9)
	trace_mi.mesh = pm
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tm.albedo_color = Color(0.1, 0.07, 0.05, 0.8)
	trace_mi.material_override = tm
	trace_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trace_mi.position = at + Vector3(0, 0.025, 0)
	content.add_child(trace_mi)
	var fire_p := CPUParticles3D.new()
	fire_p.amount = 36
	fire_p.lifetime = 0.7
	fire_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	fire_p.emission_box_extents = Vector3(0.3, 0.05, 0.3)
	fire_p.direction = Vector3.UP
	fire_p.spread = 20.0
	fire_p.initial_velocity_min = 0.6
	fire_p.initial_velocity_max = 1.4
	fire_p.gravity = Vector3(0, 0.6, 0)
	fire_p.scale_amount_min = 0.6
	fire_p.scale_amount_max = 1.2
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.85, 0.3))
	grad.set_color(1, Color(0.8, 0.15, 0.05, 0.0))
	fire_p.color_ramp = grad
	var q := QuadMesh.new()
	q.size = Vector2(0.14, 0.14)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.vertex_color_use_as_albedo = true
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = fm
	fire_p.mesh = q
	fire_p.position = at + Vector3(0, 0.1, 0)
	content.add_child(fire_p)
	_strikes.append({"bolt": bolt, "fire": fire_p, "trace": trace_mi, "t": 0.0, "fire_s": fire, "trace_s": trace})


func tick(delta: float) -> void:
	for s in _strikes.duplicate():
		s["t"] += delta
		if not is_instance_valid(s["trace"]):
			_strikes.erase(s)
			continue
		if s["t"] > 0.18 and is_instance_valid(s["bolt"]):
			s["bolt"].queue_free()
		if s["t"] > s["fire_s"] and is_instance_valid(s["fire"]) and s["fire"].emitting:
			s["fire"].emitting = false
		if s["t"] > s["fire_s"] + s["trace_s"]:
			s["trace"].queue_free()
			if is_instance_valid(s["fire"]):
				s["fire"].queue_free()
			_strikes.erase(s)
	for sp in _shake.keys():
		_shake[sp] -= delta
		var base: float = sp.get_meta("x0", sp.position.x)
		if not sp.has_meta("x0"):
			sp.set_meta("x0", base)
		if _shake[sp] <= 0.0:
			sp.position.x = base
			_shake.erase(sp)
		else:
			sp.position.x = base + sin(_shake[sp] * 60.0) * 0.06
	if not _small_waters.is_empty():
		_small_water_t += delta
		var f := int(_small_water_t / 0.3)
		for sw in _small_waters:
			var frames: Array = sw["frames"]
			sw["mat"].albedo_texture = frames[f % frames.size()]
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


## Какая картинка земли в клетке: трава, тропинка, поле, канава… (со снегом или без).
func _tile_name(x: int, y: int, look: String, snow: bool, day: int) -> String:
	var field_look := look if Location.season_id(day) != "summer" else "summer%02d" % Location.season_day(day)
	var ice := Location.season_id(day) == "winter"
	var c := map.ground_at(x, y)
	var v := int(Location.hash3(x, y, 3) * 4)
	var tile := ""
	if c == "~":
		tile = "path_0"
	elif c == "V":
		# канава тянется дальше и поворачивает: смотрим, где соседние клетки канавы
		var m := (1 if map.ground_at(x - 1, y) == "V" else 0) | (2 if map.ground_at(x + 1, y) == "V" else 0) \
			| (4 if map.ground_at(x, y - 1) == "V" else 0) | (8 if map.ground_at(x, y + 1) == "V" else 0)
		tile = "ditch_%d%s" % [m, "_ice" if ice else ""]
	elif snow:
		tile = "snow_%d" % v
	elif c == "=":
		tile = "path_%d" % v
	elif c == "P":
		tile = "site_%d" % v
	elif c == "Q" or c == "q":
		tile = "field_wheat_%s_%d" % [field_look, v]
	elif c == "N" or c == "n":
		tile = "field_sun_%s_%d" % [field_look, v]
	elif c == "O":
		tile = "cobbles_%d" % v
	elif c == "b" or c == "d":
		tile = "bridge_%d" % (0 if c == "b" else 1)
	else:
		tile = "grass_%s_%d" % [look, v]
	return tile


func _ground(look: String, snow: bool, day: int) -> void:
	# поля меняются и летом (пшеница зреет): для них свой вид на каждый летний день
	var field_look := look if Location.season_id(day) != "summer" else "summer%02d" % Location.season_day(day)
	var ice := Location.season_id(day) == "winter"
	var img := Image.create(map.W * T, map.H * T, false, Image.FORMAT_RGBA8)
	for y in map.H:
		for x in map.W:
			var c := map.ground_at(x, y)
			var tile := _tile_name(x, y, look, snow, day)
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
	content.add_child(mi)


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


# ---------- прилавки и шатёр торговца ----------
# Объёмные, как дом: простые формы с пиксельными текстурами (16 пикселей на клетку). Торговец — отдельный спрайт
# за стойкой (trader_<кто> в атласе), виден, только когда рынок открыт. Цвета навесов и товара — как в game/sprites.js.

const AWNING := {"fruit": ["#c7432f", "#f2e6bf"], "veg": ["#3f8a3a", "#f2e6bf"], "berry": ["#7a3aa8", "#f2e6bf"],
	"any": ["#5a3a8a", "#ffd24a"], "empty": ["#8a7a6a", "#b8ab98"]}
const GOODS := {"fruit": ["#cf2f2f", "#8fd65a", "#f2d14a"], "veg": ["#e8832a", "#3f9a3a", "#e0402c", "#c49a62"],
	"berry": ["#d63b45", "#8a5a33", "#9a4ad6"], "any": ["#efe0b4", "#c99a66", "#efe0b4"]}
var _mats := {}


## Прилавок или шатёр на своём месте карты. Модель строится лицом на юг в клетках (ширина W, глубина D),
## потом поворачивается лицом туда, куда указывает "facing" в каталоге.
func _shop(o: Dictionary, d: Dictionary, size: Vector2i, snow: bool, market_open: bool) -> void:
	var facing := String(d.get("facing", "south"))
	var across := facing == "south" or facing == "north"
	var w := size.x if across else size.y
	var dp := size.y if across else size.x
	var root := Node3D.new()
	root.name = String(o["id"]).capitalize()
	content.add_child(root)
	var x0 := float(o["x"])
	var z0 := float(o["y"])
	match facing:
		"north":
			root.position = Vector3(x0 + w, 0, z0 + dp)
			root.rotation.y = PI
		"east":
			root.position = Vector3(x0, 0, z0 + w)
			root.rotation.y = PI / 2.0
		"west":
			root.position = Vector3(x0 + dp, 0, z0)
			root.rotation.y = -PI / 2.0
		_:
			root.position = Vector3(x0, 0, z0)
	var who := String(o.get("trader", ""))
	var entry := {"obj": o, "who": who}
	if d.get("model", "") == "tent":
		_tent(root, entry, float(w), float(dp), who, snow)
	else:
		_stall(root, entry, float(w), float(dp), who if who != "" else "empty", snow)
	if d.get("shop", false):
		_shops.append(entry)
		_show_shop(entry, market_open)


## Открыто: торговец и товар на месте. Закрыто (или торговца нет): ставни.
func _show_shop(entry: Dictionary, open: bool) -> void:
	var on: bool = open and entry["who"] != ""
	entry["open_node"].visible = on
	entry["closed_node"].visible = not on
	if entry.get("trader_sprite") != null:
		entry["trader_sprite"].visible = on


func _stall(root: Node3D, entry: Dictionary, w: float, dp: float, who: String, snow: bool) -> void:
	var colors: Array = AWNING[who]
	# задняя стенка, столбы, стойка
	var st := _surface()
	_box(st, Vector3(0.1, 0, 0.2), Vector3(w - 0.1, 1.9, 0.34))
	_add_mesh(root, st, _mat("stall_back", _stall_back()))
	st = _surface()
	for px in [0.1, w - 0.26]:
		_box(st, Vector3(px, 0, 0.18), Vector3(px + 0.16, 2.95, 0.34))
		_box(st, Vector3(px, 0, dp - 0.42), Vector3(px + 0.16, 2.62, dp - 0.26))
	_add_mesh(root, st, _mat("post", _post()))
	st = _surface()
	_box(st, Vector3(0.1, 0, dp - 0.78), Vector3(w - 0.1, 0.9, dp - 0.26))
	_add_mesh(root, st, _mat("counter", _counter()))
	# навес: скат от задней стенки к стойке и фестоны спереди. Поднят высоко: камера смотрит сверху,
	# и под низким навесом торговца не было бы видно
	var back := Vector3(0, 2.97, 0.08)
	var front := Vector3(0, 2.6, dp - 0.12)
	var length := Vector2(front.z - back.z, back.y - front.y).length()
	var n := Vector3(0, front.z - back.z, back.y - front.y).normalized()
	st = _surface()
	quad(st, Vector3(-0.1, back.y, back.z), Vector3(w + 0.1, back.y, back.z), Vector3(w + 0.1, front.y, front.z), Vector3(-0.1, front.y, front.z),
		Rect2(0, 0, w + 0.2, length), n)
	_add_mesh(root, st, _mat("snowroof", _snow_roof()) if snow else _mat("awning_" + who, _stripes(colors)))
	st = _surface()
	quad(st, Vector3(-0.1, front.y, front.z), Vector3(w + 0.1, front.y, front.z), Vector3(w + 0.1, front.y - 0.3, front.z), Vector3(-0.1, front.y - 0.3, front.z),
		Rect2(0, 0, w + 0.2, 1), Vector3.BACK)
	_add_mesh(root, st, _mat("valance_" + who, _valance(colors), true))
	# закрыто: ставни над стойкой; у пустого места — табличка на стойке
	var closed := Node3D.new()
	root.add_child(closed)
	st = _surface()
	quad(st, Vector3(0.26, 2.3, dp - 0.5), Vector3(w - 0.26, 2.3, dp - 0.5), Vector3(w - 0.26, 0.9, dp - 0.5), Vector3(0.26, 0.9, dp - 0.5),
		Rect2(0, 0, w - 0.52, 1.4), Vector3.BACK)
	_add_mesh(closed, st, _mat("shutters", _shutters()))
	if who == "empty":
		st = _surface()
		var cx := w / 2.0
		quad(st, Vector3(cx - 0.62, 0.68, dp - 0.25), Vector3(cx + 0.62, 0.68, dp - 0.25), Vector3(cx + 0.62, 0.25, dp - 0.25), Vector3(cx - 0.62, 0.25, dp - 0.25),
			Rect2(0, 0, 1, 1), Vector3.BACK)
		_add_mesh(closed, st, _mat("plaque", _plaque()))
	# открыто: ящики с товаром по краям стойки и торговец посередине
	var open := Node3D.new()
	root.add_child(open)
	if who != "empty":
		for i in 3:
			_crate(open, Vector3(0.35 + i * 0.42, 0.9, dp - 0.52), GOODS[who][i % GOODS[who].size()])
			_crate(open, Vector3(w - 0.77 - i * 0.42, 0.9, dp - 0.52), GOODS[who][(i + 1) % GOODS[who].size()])
		entry["trader_sprite"] = _trader(root, who, Vector3(w / 2.0, 0.55, dp - 0.86))
	entry["open_node"] = open
	entry["closed_node"] = closed


func _tent(root: Node3D, entry: Dictionary, w: float, dp: float, who: String, snow: bool) -> void:
	var colors: Array = AWNING["any"]
	var x0 := 0.3
	var x1 := w - 0.3
	var z0 := 0.3
	var z1 := dp - 0.9
	var h := 1.7
	var dx0 := w / 2.0 - 0.7
	var dx1 := w / 2.0 + 0.7
	var dh := 1.45
	# стены в полоску, спереди — вход
	var st := _surface()
	quad(st, Vector3(x1, h, z0), Vector3(x0, h, z0), Vector3(x0, 0, z0), Vector3(x1, 0, z0), Rect2(0, 0, x1 - x0, h), Vector3.FORWARD)
	quad(st, Vector3(x0, h, z0), Vector3(x0, h, z1), Vector3(x0, 0, z1), Vector3(x0, 0, z0), Rect2(0, 0, z1 - z0, h), Vector3.LEFT)
	quad(st, Vector3(x1, h, z1), Vector3(x1, h, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Rect2(0, 0, z1 - z0, h), Vector3.RIGHT)
	quad(st, Vector3(x0, h, z1), Vector3(dx0, h, z1), Vector3(dx0, 0, z1), Vector3(x0, 0, z1), Rect2(0, 0, dx0 - x0, h), Vector3.BACK)
	quad(st, Vector3(dx1, h, z1), Vector3(x1, h, z1), Vector3(x1, 0, z1), Vector3(dx1, 0, z1), Rect2(0, 0, x1 - dx1, h), Vector3.BACK)
	quad(st, Vector3(dx0, h, z1), Vector3(dx1, h, z1), Vector3(dx1, dh, z1), Vector3(dx0, dh, z1), Rect2(0, 0, dx1 - dx0, h - dh), Vector3.BACK)
	_add_mesh(root, st, _mat("tent_wall", _stripes(colors, 4)))
	# внутри темно
	st = _surface()
	quad(st, Vector3(dx0, dh, z1 - 0.7), Vector3(dx1, dh, z1 - 0.7), Vector3(dx1, 0, z1 - 0.7), Vector3(dx0, 0, z1 - 0.7), Rect2(0, 0, 1, 1), Vector3.BACK)
	_add_mesh(root, st, _mat("dark", _img(4, 4, Color("#2a1c3a"))))
	# крыша-пирамида с флажком
	var e := 0.25
	var apex := Vector3(w / 2.0, 3.25, (z0 + z1) / 2.0)
	var c := [Vector3(x0 - e, h, z0 - e), Vector3(x1 + e, h, z0 - e), Vector3(x1 + e, h, z1 + e), Vector3(x0 - e, h, z1 + e)]
	st = _surface()
	for i in 4:
		var a: Vector3 = c[i]
		var b: Vector3 = c[(i + 1) % 4]
		var side := a.distance_to(b)
		var nrm := (b - a).cross(apex - a).normalized()
		if nrm.y < 0:
			nrm = -nrm
		tri(st, a, b, apex, Vector2(0, 2), Vector2(side, 2), Vector2(side / 2.0, 0), nrm)
	_add_mesh(root, st, _mat("snowroof", _snow_roof()) if snow else _mat("tent_roof", _stripes(colors, 4)))
	st = _surface()
	_box(st, apex + Vector3(-0.03, -0.1, -0.03), apex + Vector3(0.03, 0.45, 0.03))
	_add_mesh(root, st, _mat("post", _post()))
	st = _surface()
	quad(st, apex + Vector3(0.03, 0.45, 0), apex + Vector3(0.36, 0.38, 0), apex + Vector3(0.36, 0.22, 0), apex + Vector3(0.03, 0.29, 0), Rect2(0, 0, 1, 1), Vector3.BACK)
	_add_mesh(root, st, _mat("flag", _img(4, 4, Color("#ffd24a"))))
	# стойка перед входом
	st = _surface()
	_box(st, Vector3(0.7, 0, dp - 0.75), Vector3(w - 0.7, 0.75, dp - 0.3))
	_add_mesh(root, st, _mat("counter", _counter()))
	var closed := Node3D.new()
	root.add_child(closed)
	st = _surface()
	quad(st, Vector3(dx0, dh, z1 + 0.01), Vector3(dx1, dh, z1 + 0.01), Vector3(dx1, 0, z1 + 0.01), Vector3(dx0, 0, z1 + 0.01), Rect2(0, 0, dx1 - dx0, dh), Vector3.BACK)
	_add_mesh(closed, st, _mat("tent_flap", _stripes([colors[0], colors[0]], 4)))
	var open := Node3D.new()
	root.add_child(open)
	if who != "":
		for i in 5:
			_crate(open, Vector3(0.85 + i * 0.47, 0.75, dp - 0.65), GOODS["any"][i % GOODS["any"].size()])
		entry["trader_sprite"] = _trader(root, who, Vector3(w / 2.0, 0.3, z1 - 0.15))
	entry["open_node"] = open
	entry["closed_node"] = closed


# ---------- мелкие постройки: ящик для продажи, почтовый ящик, табличка, указатель, шлагбаумы ----------

func _prop(o: Dictionary, d: Dictionary, size: Vector2i, snow: bool) -> void:
	var root := Node3D.new()
	root.name = String(o["id"]).capitalize()
	# начало координат — середина занятых клеток на земле
	root.position = Vector3(o["x"] + size.x / 2.0, 0, o["y"] + size.y / 2.0)
	content.add_child(root)
	var wood := _mat("counter", _counter())
	var post := _mat("post", _post())
	var cap := _mat("snowroof", _snow_roof())
	var st: SurfaceTool
	match String(d["model"]):
		"bin":
			# сундук: доски, тёмные железные полосы, крышка чуть шире
			st = _surface()
			_box(st, Vector3(-0.4, 0, -0.27), Vector3(0.4, 0.42, 0.27))
			_add_mesh(root, st, _mat("planks", _planks()))
			st = _surface()
			_box(st, Vector3(-0.44, 0.42, -0.31), Vector3(0.44, 0.52, 0.31))
			_add_mesh(root, st, cap if snow else wood)
			st = _surface()
			for bx in [-0.3, 0.24]:
				_box(st, Vector3(bx, 0, -0.285), Vector3(bx + 0.06, 0.53, 0.285))
			_add_mesh(root, st, _mat("iron", _img(4, 4, Color("#4b4b52"))))
			st = _surface()
			_box(st, Vector3(-0.05, 0.3, 0.27), Vector3(0.05, 0.42, 0.3))
			_add_mesh(root, st, _mat("brass", _img(4, 4, Color("#f0bf45"))))
		"mailbox":
			st = _surface()
			_box(st, Vector3(-0.05, 0, -0.05), Vector3(0.05, 0.85, 0.05))
			_add_mesh(root, st, post)
			st = _surface()
			_box(st, Vector3(-0.3, 0.85, -0.2), Vector3(0.3, 1.18, 0.2))
			_add_mesh(root, st, _mat("mailbox", _mailbox()))
			if snow:
				st = _surface()
				_box(st, Vector3(-0.31, 1.18, -0.21), Vector3(0.31, 1.22, 0.21))
				_add_mesh(root, st, cap)
			# флажок сбоку: поднят — почта есть (пока писем нет, флажок просто стоит)
			st = _surface()
			_box(st, Vector3(0.3, 0.92, 0.0), Vector3(0.33, 1.32, 0.03))
			_add_mesh(root, st, _mat("brass", _img(4, 4, Color("#f0bf45"))))
			st = _surface()
			_box(st, Vector3(0.3, 1.2, 0.03), Vector3(0.33, 1.32, 0.17))
			_add_mesh(root, st, _mat("red", _img(4, 4, Color("#e0402c"))))
		"sign":
			st = _surface()
			for px in [-0.32, 0.26]:
				_box(st, Vector3(px, 0, -0.03), Vector3(px + 0.06, 0.62, 0.03))
			_add_mesh(root, st, post)
			st = _surface()
			_box(st, Vector3(-0.45, 0.55, -0.04), Vector3(0.45, 1.05, 0.03))
			_add_mesh(root, st, _mat("sign_board", _sign_board()))
			if snow:
				st = _surface()
				_box(st, Vector3(-0.46, 1.05, -0.05), Vector3(0.46, 1.09, 0.04))
				_add_mesh(root, st, cap)
		"signpost":
			st = _surface()
			_box(st, Vector3(-0.06, 0, -0.06), Vector3(0.06, 1.7, 0.06))
			_add_mesh(root, st, post)
			# стрелки на все четыре стороны: север — деревня, запад — рынок, восток — ферма, юг — домой
			var arrows := [[PI / 2.0, 1.5], [PI, 1.25], [0.0, 1.0], [-PI / 2.0, 0.75]]
			for ar in arrows:
				var arm := Node3D.new()
				arm.rotation.y = ar[0]
				root.add_child(arm)
				st = _surface()
				_box(st, Vector3(0.06, ar[1], -0.03), Vector3(0.62, ar[1] + 0.18, 0.03))
				_box(st, Vector3(0.62, ar[1] + 0.03, -0.025), Vector3(0.7, ar[1] + 0.15, 0.025))
				_add_mesh(arm, st, _mat("sign_board", _sign_board()))
			if snow:
				st = _surface()
				_box(st, Vector3(-0.07, 1.7, -0.07), Vector3(0.07, 1.74, 0.07))
				_add_mesh(root, st, cap)
		"barrier":
			# два серых столба и полосатая перекладина между ними — вдоль длинной стороны
			var along_x := size.x >= size.y
			var half := (maxf(size.x, size.y) / 2.0) - 0.2
			st = _surface()
			for k in [-1.0, 1.0]:
				var c := Vector3(k * half, 0, 0) if along_x else Vector3(0, 0, k * half)
				_box(st, c + Vector3(-0.08, 0, -0.08), c + Vector3(0.08, 0.95, 0.08))
			_add_mesh(root, st, _mat("barrier_post", _img(4, 4, Color("#5a5a5a"))))
			st = _surface()
			if along_x:
				_box(st, Vector3(-half, 0.72, -0.05), Vector3(half, 0.86, 0.05))
			else:
				_box(st, Vector3(-0.05, 0.72, -half), Vector3(0.05, 0.86, half))
			_add_mesh(root, st, _mat("barrier_bar", _barrier_bar()))
			if snow:
				st = _surface()
				for k in [-1.0, 1.0]:
					var c2 := Vector3(k * half, 0, 0) if along_x else Vector3(0, 0, k * half)
					_box(st, c2 + Vector3(-0.09, 0.95, -0.09), c2 + Vector3(0.09, 0.99, 0.09))
				_add_mesh(root, st, cap)


## Синий почтовый ящик с прорезью.
static func _mailbox() -> Image:
	var img := _img(16, 16, Color("#3d6fd6"))
	img.fill_rect(Rect2i(0, 0, 16, 1), Color("#6f98f0"))
	img.fill_rect(Rect2i(0, 15, 16, 1), Color("#284a9a"))
	img.fill_rect(Rect2i(4, 6, 8, 1), Color("#1c2f6a"))
	return img


## Доска таблички и стрелок указателя: дерево и тёмные строчки «текста».
static func _sign_board() -> Image:
	var img := _img(16, 8, Color("#a97c50"))
	img.fill_rect(Rect2i(0, 0, 16, 1), Color("#c99a66"))
	img.fill_rect(Rect2i(0, 7, 16, 1), Color("#6e4b2c"))
	img.fill_rect(Rect2i(2, 2, 11, 1), Color("#5e3b1f"))
	img.fill_rect(Rect2i(2, 4, 8, 1), Color("#5e3b1f"))
	return img


## Красно-белые полосы шлагбаума.
static func _barrier_bar() -> Image:
	var img := _img(16, 16, Color("#d6455a"))
	img.fill_rect(Rect2i(0, 0, 8, 16), Color("#f2e6bf"))
	return img


# ---------- фонтан и колодец ----------

## Фонтан на рыночной площади: круглая каменная чаша с водой, столб с верхней чашей и струи.
## Зимой вода замёрзшая и струй нет.
func _fountain(o: Dictionary, size: Vector2i, winter: bool, snow: bool) -> void:
	var root := Node3D.new()
	root.name = "Fountain"
	root.position = Vector3(o["x"] + size.x / 2.0, 0, o["y"] + size.y / 2.0)
	content.add_child(root)
	var r := minf(size.x, size.y) / 2.0 - 0.05
	var stone := _mat("stone", _stone())
	var rim := _mat("snowroof", _snow_roof()) if snow else _mat("stone_light", _stone_light())
	# нижняя чаша: стенка и верхний край
	var st := _surface()
	_ring_wall(st, r, 0.0, 0.42, 20)
	_ring_wall(st, r - 0.24, 0.12, 0.42, 20)
	_add_mesh(root, st, stone)
	st = _surface()
	_ring_top(st, r, r - 0.24, 0.42, 20)
	_add_mesh(root, st, rim)
	_water_disc(root, r - 0.24, 0.33, winter)
	# столб и верхняя чаша
	st = _surface()
	_ring_wall(st, 0.17, 0.0, 1.25, 8)
	_ring_wall(st, 0.5, 1.12, 1.3, 14)
	_add_mesh(root, st, stone)
	st = _surface()
	_ring_top(st, 0.5, 0.38, 1.3, 14)
	_disc(st, 0.5, 1.12, 14, true)
	_add_mesh(root, st, rim)
	_water_disc(root, 0.38, 1.26, winter)
	if winter:
		return
	# струи: из верхней чаши во все стороны вниз и фонтанчик вверх посередине
	root.add_child(_jets(Vector3(0, 1.32, 0), 0.45, Vector3(0, 1.0, 0), 2.0, 1.8, 0.8, 56))
	root.add_child(_jets(Vector3(0, 1.34, 0), 0.03, Vector3(0, 1, 0), 0.0, 3.2, 0.5, 16))


## Колодец: каменное кольцо с водой, два столба, двускатная крыша, ворот с верёвкой и ведром.
func _well(o: Dictionary, winter: bool, snow: bool) -> void:
	var root := Node3D.new()
	root.name = "Well"
	root.position = Vector3(o["x"] + 0.5, 0, o["y"] + 0.5)
	content.add_child(root)
	var st := _surface()
	_ring_wall(st, 0.43, 0.0, 0.55, 12)
	_ring_wall(st, 0.3, 0.2, 0.55, 12)
	_add_mesh(root, st, _mat("stone", _stone()))
	st = _surface()
	_ring_top(st, 0.43, 0.3, 0.55, 12)
	_add_mesh(root, st, _mat("snowroof", _snow_roof()) if snow else _mat("stone_light", _stone_light()))
	_water_disc(root, 0.3, 0.32, winter, true)
	st = _surface()
	for px in [-0.45, 0.37]:
		_box(st, Vector3(px, 0, -0.04), Vector3(px + 0.08, 1.42, 0.04))
	_box(st, Vector3(-0.37, 1.0, -0.03), Vector3(0.37, 1.06, 0.03))
	_add_mesh(root, st, _mat("post", _post()))
	st = _surface()
	_box(st, Vector3(-0.01, 0.62, -0.01), Vector3(0.01, 1.0, 0.01))
	_add_mesh(root, st, _mat("rope", _img(4, 4, Color("#d9c9a0"))))
	st = _surface()
	_box(st, Vector3(-0.07, 0.5, -0.07), Vector3(0.07, 0.64, 0.07))
	_add_mesh(root, st, _mat("bucket", _img(4, 4, Color("#8b8b8b"))))
	# крыша: конёк вдоль X, скаты на север и юг
	var y0 := 1.28
	var y1 := 1.68
	var w := 0.62
	var dz := 0.5
	var slope := Vector2(dz, y1 - y0).length()
	st = _surface()
	quad(st, Vector3(-w, y1, 0), Vector3(w, y1, 0), Vector3(w, y0, dz), Vector3(-w, y0, dz), Rect2(0, 0, 2 * w, slope), Vector3(0, dz, y1 - y0).normalized())
	quad(st, Vector3(w, y1, 0), Vector3(-w, y1, 0), Vector3(-w, y0, -dz), Vector3(w, y0, -dz), Rect2(0, 0, 2 * w, slope), Vector3(0, dz, -(y1 - y0)).normalized())
	_add_mesh(root, st, _mat("snowroof", _snow_roof()) if snow else _mat("well_roof", _well_roof()))
	st = _surface()
	tri(st, Vector3(-w + 0.05, y0, dz - 0.05), Vector3(-w + 0.05, y0, -dz + 0.05), Vector3(-w + 0.05, y1, 0), Vector2(0, 0.4), Vector2(1, 0.4), Vector2(0.5, 0), Vector3.LEFT)
	tri(st, Vector3(w - 0.05, y0, -dz + 0.05), Vector3(w - 0.05, y0, dz - 0.05), Vector3(w - 0.05, y1, 0), Vector2(0, 0.4), Vector2(1, 0.4), Vector2(0.5, 0), Vector3.RIGHT)
	_add_mesh(root, st, _mat("planks", _planks()))


## Стенка кольца (как труба без крышки): радиус r, от высоты y0 до y1, n граней.
func _ring_wall(st: SurfaceTool, r: float, y0: float, y1: float, n: int) -> void:
	var edge := TAU * r / n
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0) * r, 0, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, 0, sin(a1) * r)
		var nrm := (p0 + p1).normalized()
		quad(st, p1 + Vector3(0, y1, 0), p0 + Vector3(0, y1, 0), p0 + Vector3(0, y0, 0), p1 + Vector3(0, y0, 0),
			Rect2(i * edge, 0, edge, y1 - y0), nrm)


## Верх кольца между радиусами r0 (внешний) и r1 (внутренний) на высоте y.
func _ring_top(st: SurfaceTool, r0: float, r1: float, y: float, n: int) -> void:
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var o0 := Vector3(cos(a0) * r0, y, sin(a0) * r0)
		var o1 := Vector3(cos(a1) * r0, y, sin(a1) * r0)
		var i0 := Vector3(cos(a0) * r1, y, sin(a0) * r1)
		var i1 := Vector3(cos(a1) * r1, y, sin(a1) * r1)
		quad(st, o0, o1, i1, i0, Rect2(o0.x, o0.z, 0.25, r0 - r1), Vector3.UP)


## Круг (дно или поверхность) радиуса r на высоте y; текстура ложится по X и Z, 16 пикселей на клетку.
func _disc(st: SurfaceTool, r: float, y: float, n: int, down := false) -> void:
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var c := Vector3(0, y, 0)
		var p0 := Vector3(cos(a0) * r, y, sin(a0) * r)
		var p1 := Vector3(cos(a1) * r, y, sin(a1) * r)
		# лицевая сторона — та, с которой вершины идут по часовой стрелке
		if down:
			tri(st, c, p1, p0, Vector2(c.x, c.z), Vector2(p1.x, p1.z), Vector2(p0.x, p0.z), Vector3.DOWN)
		else:
			tri(st, c, p0, p1, Vector2(c.x, c.z), Vector2(p0.x, p0.z), Vector2(p1.x, p1.z), Vector3.UP)


## Вода в чаше: те же кадры воды (или лёд), что у пруда. dark — тёмная вода глубоко в колодце.
func _water_disc(parent: Node3D, r: float, y: float, winter: bool, dark := false) -> void:
	var frames := []
	for f in (1 if winter else 4):
		var img := Image.create(T * 2, T * 2, false, Image.FORMAT_RGBA8)
		for k in 4:
			var tile := "ice_%d" % k if winter else "water_%d_%d" % [k, f]
			img.blit_rect(atlas.image, atlas.rect(tile), Vector2i((k % 2) * T, (k / 2) * T))
		if dark:
			img.adjust_bcs(0.55, 1.0, 1.0)
			img = Palette.quantize(img, "3d")
		frames.append(ImageTexture.create_from_image(img))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = frames[0]
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.uv1_scale = Vector3(0.5, 0.5, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.25
	mat.metallic_specular = 0.7
	var st := _surface()
	_disc(st, r, y, 16)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if frames.size() > 1:
		_small_waters.append({"mat": mat, "frames": frames})


## Струи воды: светлые квадратики вылетают из кольца радиуса r вверх и в стороны и падают.
func _jets(at: Vector3, r: float, dir: Vector3, spread_out: float, speed: float, life: float, amount: int) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.position = at
	p.amount = amount
	p.lifetime = life
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING if r > 0.05 else CPUParticles3D.EMISSION_SHAPE_POINT
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = r
	p.emission_ring_inner_radius = r * 0.9
	p.emission_ring_height = 0.0
	p.direction = dir
	p.spread = 6.0
	p.initial_velocity_min = speed * 0.85
	p.initial_velocity_max = speed
	p.radial_accel_min = spread_out
	p.radial_accel_max = spread_out * 1.4
	p.gravity = Vector3(0, -7.5, 0)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.06, 0.09)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Palette.col("2d", "water", 0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mesh.material = mat
	p.mesh = mesh
	return p


static func _stone_light() -> Image:
	var img := _img(16, 16, Color("#a6a6a6"))
	for i in 8:
		img.set_pixel((i * 7 + 2) % 16, (i * 5 + 3) % 16, Color("#8a8a8a"))
	img.fill_rect(Rect2i(0, 15, 16, 1), Color("#808080"))
	return img


static func _well_roof() -> Image:
	var img := _img(16, 16, Color("#7a4a26"))
	for row in 4:
		img.fill_rect(Rect2i(0, row * 4, 16, 1), Color("#9a6a3a"))
		img.fill_rect(Rect2i(0, row * 4 + 3, 16, 1), Color("#5a3418"))
	return img


## Ящик с товаром на стойке: деревянный ящик, сверху горка товара.
func _crate(parent: Node3D, at: Vector3, color: String) -> void:
	var st := _surface()
	_box(st, at, at + Vector3(0.34, 0.16, 0.26))
	_add_mesh(parent, st, _mat("crate", _img(4, 4, Color("#7a5230"))))
	st = _surface()
	_box(st, at + Vector3(0.05, 0.16, 0.04), at + Vector3(0.29, 0.24, 0.22))
	_add_mesh(parent, st, _mat("goods_" + color, _img(4, 4, Color(color))))


func _trader(root: Node3D, who: String, at: Vector3) -> Sprite3D:
	var name := "trader_" + who
	if not atlas.has(name):
		push_warning("Нет спрайта " + name)
		return null
	var sp := atlas.make_sprite(name)
	sp.position = at
	sp.scale = Vector3(1, STRETCH, 1)
	sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sp.modulate = _tint
	root.add_child(sp)
	sprites.append(sp)
	return sp


## Один материал на текстуру за постройку локации (их много одинаковых: ящики, столбы).
func _mat(key: String, img: Image, cutout := false) -> StandardMaterial3D:
	if not _mats.has(key):
		_mats[key] = _material(img, cutout)
	return _mats[key]


## Полосы навеса или шатра: две краски по очереди, каждая шириной half пикселей.
static func _stripes(colors: Array, half := 8) -> Image:
	var img := _img(half * 2, 16, Color(colors[0]))
	img.fill_rect(Rect2i(half, 0, half, 16), Color(colors[1]))
	return img


## Фестоны навеса: полосы с зубчатым нижним краем (прозрачное отсекается).
static func _valance(colors: Array) -> Image:
	var img := _img(16, 5, Color(0, 0, 0, 0))
	for k in 2:
		var c := Color(colors[k])
		var x := k * 8
		img.fill_rect(Rect2i(x, 0, 8, 3), c)
		img.fill_rect(Rect2i(x + 1, 3, 6, 1), c)
		img.fill_rect(Rect2i(x + 2, 4, 4, 1), c)
	img.fill_rect(Rect2i(0, 0, 16, 1), Color("#3a2a1f"))
	return img


static func _snow_roof() -> Image:
	var img := _img(16, 16, Color("#f4f8ff"))
	for i in 10:
		img.set_pixel((i * 7 + 3) % 16, (i * 5 + 1) % 16, Color("#d8e4f0"))
	return img


static func _stall_back() -> Image:
	var img := _img(16, 16, Color("#8b6a45"))
	for x in [0, 8]:
		img.fill_rect(Rect2i(x, 0, 1, 16), Color("#6f5235"))
	return img


static func _post() -> Image:
	var img := _img(4, 16, Color("#6e4b2c"))
	img.fill_rect(Rect2i(0, 0, 1, 16), Color("#8a5a33"))
	return img


## Стойка из досок: светлая верхняя доска, тёмные швы.
static func _counter() -> Image:
	var img := _img(16, 16, Color("#a97c50"))
	for row in 4:
		var y := row * 4
		img.fill_rect(Rect2i(0, y, 16, 1), Color("#c99a66"))
		img.fill_rect(Rect2i(0, y + 3, 16, 1), Color("#6e4b2c"))
		img.fill_rect(Rect2i((row * 5 + 6) % 16, y, 1, 4), Color("#6e4b2c"))
	return img


static func _shutters() -> Image:
	var img := _img(16, 16, Color("#6f5235"))
	for y in range(1, 16, 3):
		img.fill_rect(Rect2i(0, y, 16, 1), Color("#5a4228"))
	return img


## Табличка «место свободно» на пустом прилавке.
static func _plaque() -> Image:
	var img := _img(20, 7, Color("#f2e6bf"))
	img.fill_rect(Rect2i(2, 2, 16, 1), Color("#8a6a3a"))
	img.fill_rect(Rect2i(2, 4, 12, 1), Color("#8a6a3a"))
	return img


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
	# текстуры построек рисуются кодом — притягиваем их к палитре «3d», как рисунки атласа
	if img.get_width() * img.get_height() <= 4096:
		img = Palette.quantize(img, "3d")
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
