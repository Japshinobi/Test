extends RefCounted
## Атлас спрайтов (собирается скриптом tools/export-atlas.mjs из рисунков game/sprites.js).
## У каждого спрайта есть «точка опоры» (ax, ay) — место, которым он стоит на земле.

const Palette := preload("res://scripts/palette.gd")
const T := 16   # пикселей чернового рисунка в одной клетке
## Рубашка Тёмы — ряд палитры cloth_red (оттенки 1 и 2), рубашку друга перекрашиваем в cloth_green,
## чтобы игроков не путать. В game/sprites.js рубашка нарисована теми же цветами палитры.

var image: Image
var texture: ImageTexture
var friend_texture: ImageTexture
var sprites := {}


func _init() -> void:
	image = load_image("res://assets/atlas.png")
	texture = ImageTexture.create_from_image(image)
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas.json"))
	for s in index["sprites"]:
		sprites[s["n"]] = s
	friend_texture = ImageTexture.create_from_image(_recolor_friend())


## Картинка из проекта. В редакторе её загружает импорт Godot; если импорта нет — читаем файл напрямую.
static func load_image(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
	if img == null:
		img = Image.load_from_file(path)
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func has(name: String) -> bool:
	return sprites.has(name)


func rect(name: String) -> Rect2i:
	var s: Dictionary = sprites[name]
	return Rect2i(int(s["x"]), int(s["y"]), int(s["w"]), int(s["h"]))


## Спрайт в 3D-мире: всегда повёрнут к камере и стоит на земле своей точкой опоры.
func make_sprite(name: String) -> Sprite3D:
	var s: Dictionary = sprites[name]
	var sp := Sprite3D.new()
	sp.texture = texture
	sp.region_enabled = true
	sp.region_rect = Rect2(rect(name))
	sp.centered = true
	sp.offset = Vector2(float(s["w"]) * 0.5 - float(s["ax"]), float(s["ay"]) - float(s["h"]) * 0.5)
	sp.pixel_size = 1.0 / T
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	return sp


func _recolor_friend() -> Image:
	var img := image.duplicate() as Image
	var from := [Palette.col("2d", "cloth_red", 1).to_rgba32(), Palette.col("2d", "cloth_red", 2).to_rgba32()]
	var to := [Palette.col("2d", "cloth_green", 1), Palette.col("2d", "cloth_green", 2)]
	for name in sprites:
		if not String(name).begins_with("player_"):
			continue
		var r := rect(name)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var i := from.find(img.get_pixel(x, y).to_rgba32())
				if i >= 0:
					img.set_pixel(x, y, to[i])
	return img
