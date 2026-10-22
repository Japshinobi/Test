extends RefCounted
## Атлас спрайтов (собирается скриптом tools/export-atlas.mjs из рисунков game/sprites.js).
## У каждого спрайта есть «точка опоры» (ax, ay) — место, которым он стоит на земле.

const T := 16   # пикселей чернового рисунка в одной клетке

var image: Image
var texture: ImageTexture
var sprites := {}

## Спрайты стоят на экране ровно, как в Ragnarok Online: без наклона по краям экрана и с одинаковыми
## пропорциями везде. Обычный спрайт «повёрнут к камере по вертикали» (BILLBOARD_FIXED_Y), и из-за
## перспективы по краям экрана заваливается наружу, а внизу сплющивается. Здесь картинка
## выводится параллельно экрану; высота — как у вертикального спрайта в середине экрана
## (растяжение STRETCH × косинус наклона камеры). Глубина берётся от вертикального спрайта,
## чтобы голова не уходила в стену или дерево за спиной; сама картинка остаётся плоской. Подкраска (modulate) работает как раньше.
const UPRIGHT := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D tex : source_color, filter_nearest;

void vertex() {
	if (!OUTPUT_IS_SRGB) {
		COLOR.rgb = mix(pow((COLOR.rgb + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), COLOR.rgb * (1.0 / 12.92), lessThan(COLOR.rgb, vec3(0.04045)));
	}
	vec3 anchor = (VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0)).xyz;
	vec3 up = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	float x = VERTEX.x * length(MODEL_MATRIX[0].xyz);
	float y = VERTEX.y * length(MODEL_MATRIX[1].xyz);
	vec3 standing = anchor + vec3(x, 0.0, 0.0) + up * y;
	vec3 screen = anchor + vec3(x, y * up.y, 0.0);
	// картинка плоская и параллельна экрану (иначе текстура гнётся по диагонали),
	// а глубина — от вертикального спрайта
	vec4 pos = PROJECTION_MATRIX * vec4(screen, 1.0);
	vec4 depth = PROJECTION_MATRIX * vec4(standing, 1.0);
	pos.z = depth.z / depth.w * pos.w;
	POSITION = pos;
}

void fragment() {
	vec4 c = texture(tex, UV) * COLOR;
	if (c.a < 0.5) {
		discard;
	}
	ALBEDO = c.rgb;
}
"""
static var _upright_shader: Shader
static var _upright_mats := {}


func _init() -> void:
	image = load_image("res://assets/atlas.png")
	texture = ImageTexture.create_from_image(image)
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas.json"))
	for s in index["sprites"]:
		sprites[s["n"]] = s


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
	sp.material_override = upright(texture)
	return sp


## Материал «спрайт стоит на экране ровно» для картинки (один на картинку).
static func upright(tex: Texture2D) -> ShaderMaterial:
	if _upright_mats.has(tex):
		return _upright_mats[tex]
	if _upright_shader == null:
		_upright_shader = Shader.new()
		_upright_shader.code = UPRIGHT
	var m := ShaderMaterial.new()
	m.shader = _upright_shader
	m.set_shader_parameter("tex", tex)
	_upright_mats[tex] = m
	return m

