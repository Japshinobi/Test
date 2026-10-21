extends Node3D
## Персонаж: спрайт, который всегда смотрит в камеру, тень-овал под ногами и имя снизу, как в Ragnarok Online.
## Какой стороной его показать, зависит и от того, куда он идёт, и от того, откуда смотрит камера.

const Atlas := preload("res://scripts/atlas.gd")
const Palette := preload("res://scripts/palette.gd")
## Для рисунков PixelLab: при камере под 50° пиксели на экране выходят квадратными, как на рисунке.
const STRETCH := 1.5
## Рисунки героев из PixelLab: холст 64×64, 32 пикселя на клетку (герой ростом около двух клеток).
const PX := 32
const SIZE := 64
## Восемь сторон по кругу, начиная с «лицом к камере» и дальше по часовой (вправо по экрану).
const DIRS := ["south", "south-east", "east", "north-east", "north", "north-west", "west", "south-west"]
## Персонажи: папка с основой (8 рисунков <сторона>.png) и слои одежды поверх неё по порядку.
## Слой — папка <основа>/<слой>/ с теми же 8 рисунками, прозрачными везде, кроме вещи.
const CHARS := {
	"vanya": {"dir": "res://assets/chars/vanya", "layers": ["jacket"]},
	"nina": {"dir": "res://assets/chars/nina", "layers": []},
}

var atlas: Atlas
var sprite: Sprite3D
var label: Label3D
## Куда смотрит персонаж: угол в мире (0 — на юг, к камере по умолчанию).
var face := 0.0
var moving := false
## Чужой персонаж (второй игрок): его положение приходит по сети, а мы плавно ведём его туда.
var remote := false
var net_pos := Vector3.ZERO
var _anim := 0.0

static var _blob_mat: StandardMaterial3D
## Готовые полосы из 8 сторон по персонажам: {"vanya": {"tex": ..., "ay": ...}}.
static var _strips := {}


func setup(p_atlas: Atlas, friend: bool, title: String) -> void:
	atlas = p_atlas
	sprite = Sprite3D.new()
	sprite.region_enabled = true
	sprite.pixel_size = 1.0 / PX
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.scale = Vector3(1, STRETCH, 1)
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sprite)

	var blob := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(0.8, 0.4)
	blob.mesh = mesh
	blob.material_override = _blob_material()
	blob.position.y = 0.02
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(blob)

	label = Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.pixel_size = 0.0011
	label.font_size = 26
	label.outline_size = 8
	label.outline_modulate = Color(0, 0, 0, 0.85)
	label.offset = Vector2(0, -22)
	label.render_priority = 10
	label.outline_render_priority = 9
	add_child(label)
	set_look(friend, title)


func set_look(friend: bool, title: String) -> void:
	var strip := _strip("nina" if friend else "vanya")
	sprite.texture = strip["tex"]
	sprite.material_override = Atlas.upright(strip["tex"])
	# ноги — на земле: середина нижнего ряда ступней в точке персонажа
	sprite.offset = Vector2(0, float(strip["ay"]) - SIZE * 0.5)
	label.text = title
	label.modulate = Color("#c8f5b0") if friend else Color("#ffe9a8")


func set_tint(c: Color) -> void:
	sprite.modulate = c


func tick(delta: float, cam_yaw: float) -> void:
	if remote:
		if position.distance_to(net_pos) > 3.0:
			position = net_pos
		else:
			position = position.lerp(net_pos, 1.0 - exp(-12.0 * delta))
	# анимации ходьбы пока нет — персонаж стоит в одной позе
	sprite.region_rect = Rect2(_side(cam_yaw) * SIZE, 0, SIZE, SIZE)


## Какой стороной персонаж повёрнут к камере — номер в DIRS (0 — лицом, 2 — правым боком, 4 — спиной).
func _side(cam_yaw: float) -> int:
	var d := Vector3(sin(face), 0, cos(face))
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var a := atan2(d.dot(right), -d.dot(fwd))
	return posmod(roundi(a / (PI / 4.0)), 8)


## Полоса из 8 сторон персонажа: основа, на неё по порядку слои одежды; тёмный внешний контур
## перекрашен в ряд outline палитры «2d». Собирается один раз на персонажа.
static func _strip(who: String) -> Dictionary:
	if _strips.has(who):
		return _strips[who]
	var info: Dictionary = CHARS[who]
	var img := Image.create(SIZE * DIRS.size(), SIZE, false, Image.FORMAT_RGBA8)
	var bottom := 0
	for i in DIRS.size():
		var one := Atlas.load_image("%s/%s.png" % [info["dir"], DIRS[i]])
		for layer in info["layers"]:
			var path := "%s/%s/%s.png" % [info["dir"], layer, DIRS[i]]
			if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
				push_warning("Нет слоя " + path)
				continue
			var top := Atlas.load_image(path)
			one.blend_rect(top, Rect2i(0, 0, SIZE, SIZE), Vector2i.ZERO)
		_outline(one)
		bottom = maxi(bottom, one.get_used_rect().end.y)
		img.blit_rect(one, Rect2i(0, 0, SIZE, SIZE), Vector2i(i * SIZE, 0))
	_strips[who] = {"tex": ImageTexture.create_from_image(img), "ay": bottom}
	return _strips[who]


## Тёмные пиксели на краю силуэта (рядом с прозрачным) — в цвет контура палитры.
static func _outline(img: Image) -> void:
	var line := Palette.col("2d", "outline", 2)
	var edge: Array[Vector2i] = []
	for y in SIZE:
		for x in SIZE:
			var c := img.get_pixel(x, y)
			if c.a == 0.0 or maxf(c.r, maxf(c.g, c.b)) > 0.25:
				continue
			for n: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q := Vector2i(x, y) + n
				if q.x < 0 or q.y < 0 or q.x >= SIZE or q.y >= SIZE or img.get_pixelv(q).a == 0.0:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		img.set_pixelv(p, line)


static func _blob_material() -> StandardMaterial3D:
	if _blob_mat:
		return _blob_mat
	var img := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	for y in 8:
		for x in 16:
			var dx := (x + 0.5 - 8.0) / 8.0
			var dy := (y + 0.5 - 4.0) / 4.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0.32))
	_blob_mat = StandardMaterial3D.new()
	_blob_mat.albedo_texture = ImageTexture.create_from_image(img)
	_blob_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return _blob_mat
