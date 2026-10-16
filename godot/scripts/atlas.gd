extends RefCounted
## Атлас спрайтов из браузерной версии (тот же, что в Unity; собирается скриптом unity/Tools~/export-atlas.mjs).
## У каждого спрайта есть «точка опоры» (ax, ay) — место, которым он стоит на земле.

const T := 16   # пикселей чернового рисунка в одной клетке
## Цвета рубашки Тёмы и рубашки друга: второго игрока перекрашиваем, чтобы их не путать.
const SHIRT := ["#c0563a", "#963f29"]
const FRIEND_SHIRT := ["#4e9a52", "#35703c"]

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
	var from := [Color(SHIRT[0]).to_rgba32(), Color(SHIRT[1]).to_rgba32()]
	var to := [Color(FRIEND_SHIRT[0]), Color(FRIEND_SHIRT[1])]
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
