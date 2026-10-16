extends Node3D
## Персонаж: спрайт, который всегда смотрит в камеру, тень-овал под ногами и имя снизу, как в Ragnarok Online.
## Какой стороной его показать, зависит и от того, куда он идёт, и от того, откуда смотрит камера.

const Atlas := preload("res://scripts/atlas.gd")
const STRETCH := 1.25

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


func setup(p_atlas: Atlas, friend: bool, title: String) -> void:
	atlas = p_atlas
	sprite = atlas.make_sprite("player_down_0")
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
	sprite.texture = atlas.friend_texture if friend else atlas.texture
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
	_anim = _anim + delta if moving else 0.0
	var frame := int(_anim / 0.16) % 2 if moving else 0
	sprite.region_rect = Rect2(atlas.rect("player_%s_%d" % [_side(cam_yaw), frame]))


## Какой стороной персонаж повёрнут к камере: лицом, спиной, левым или правым боком.
## Рисунков пока четыре; в RO их восемь (с диагоналями) — их можно будет добавить из PixelLab.
func _side(cam_yaw: float) -> String:
	var d := Vector3(sin(face), 0, cos(face))
	var fwd := Vector3(-sin(cam_yaw), 0, -cos(cam_yaw))
	var right := Vector3(cos(cam_yaw), 0, -sin(cam_yaw))
	var ff := d.dot(fwd)
	var fr := d.dot(right)
	if absf(fr) > absf(ff):
		return "right" if fr > 0 else "left"
	return "up" if ff > 0 else "down"


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
