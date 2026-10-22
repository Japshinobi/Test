extends Node
## Звуки: простые «пики», как в браузерной версии. Каждый звук — одна-две ноты (частота, длительность,
## форма волны, громкость, скольжение частоты, задержка). Звуки синтезируются один раз при запуске.

const RATE := 22050
const SOUNDS := {
	"till": [[150, 0.09, "square", 0.05, -60, 0.0]],
	"water": [[700, 0.14, "sine", 0.06, -400, 0.0]],
	"plant": [[440, 0.07, "triangle", 0.07, 0, 0.0]],
	"harvest": [[660, 0.07, "square", 0.04, 0, 0.0], [880, 0.1, "square", 0.04, 0, 0.07]],
	"coin": [[988, 0.05, "square", 0.04, 0, 0.0], [1319, 0.12, "square", 0.04, 0, 0.05]],
	"nope": [[110, 0.12, "saw", 0.03, 0, 0.0]],
	"pickup": [[880, 0.04, "triangle", 0.05, 0, 0.0], [1175, 0.05, "triangle", 0.04, 0, 0.035]],
	"chop": [[240, 0.06, "square", 0.06, -90, 0.0], [180, 0.05, "triangle", 0.05, 0, 0.04]],
	"mine": [[520, 0.04, "square", 0.05, -200, 0.0], [300, 0.06, "saw", 0.03, -100, 0.03]],
}

var on := true
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _rain: AudioStreamPlayer


func _ready() -> void:
	for name_ in SOUNDS:
		_streams[name_] = _synth(SOUNDS[name_])
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(name_: String) -> void:
	if not on or not _streams.has(name_):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[name_]
	p.play()


## Шум дождя: level 0..1 (0 — тишина). Включается и затихает вместе с погодой.
func set_rain(level: float) -> void:
	var audible := on and level > 0.02
	if not audible:
		if _rain and _rain.playing:
			_rain.stop()
		return
	if _rain == null:
		_rain = AudioStreamPlayer.new()
		_rain.stream = _noise_loop()
		add_child(_rain)
	_rain.volume_db = linear_to_db(0.35 * level)
	if not _rain.playing:
		_rain.play()


## Две секунды мягкого шума (сглаженный белый шум), повторяются по кругу.
static func _noise_loop() -> AudioStreamWAV:
	var count := RATE * 2
	var data := PackedByteArray()
	data.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var v := 0.0
	for i in count:
		v = v * 0.55 + rng.randf_range(-1.0, 1.0) * 0.45
		data.encode_s16(i * 2, int(clampf(v * 0.6, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = count
	return s


## Собрать звук из нот в один короткий WAV.
static func _synth(notes: Array) -> AudioStreamWAV:
	var total := 0.0
	for n in notes:
		total = maxf(total, n[5] + n[1] + 0.02)
	var count := int(total * RATE)
	var buf := PackedFloat32Array()
	buf.resize(count)
	for n in notes:
		var f0: float = n[0]
		var dur: float = n[1]
		var kind: String = n[2]
		var vol: float = n[3] * 4.0
		var slide: float = n[4]
		var start := int(n[5] * RATE)
		var phase := 0.0
		for i in int(dur * RATE):
			var t := float(i) / RATE
			var f := maxf(40.0, f0 + slide * t / dur)
			phase = fmod(phase + f / RATE, 1.0)
			var w: float
			match kind:
				"square":
					w = 1.0 if phase < 0.5 else -1.0
				"triangle":
					w = 4.0 * absf(phase - 0.5) - 1.0
				"saw":
					w = 2.0 * phase - 1.0
				_:
					w = sin(phase * TAU)
			# громкость затухает, как exponentialRamp в браузере
			var env := pow(0.0001 / maxf(vol, 0.0001), t / dur) * vol
			if start + i < count:
				buf[start + i] += w * env
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		data.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.stereo = false
	s.data = data
	return s
