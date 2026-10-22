extends RefCounted
## Погода: виды, шансы по сезонам, план на день и как она выглядит в каждую минуту.
## Правила — из design/weather.xlsx (листы «Погода» и «Параметры»), только строки «решено» и «в игре».
## Погоду выбирает хозяин игры; план хранится в состоянии огорода (farm.weather) и приходит гостю вместе с ним.
##
## План на день: {"am": утренняя погода, "pm": погода после смены, "at": минута начала смены (-1 — без смены)}.
## В farm.weather лежат два плана: "today" и "next" (на завтра — для будущего барометра).

const Location := preload("res://scripts/location.gd")

## Шансы в день, % — весна, лето, осень, зима (лист «Погода»).
const CHANCE := {
	"clear": [45, 55, 30, 40],
	"clouds": [20, 10, 25, 25],
	"rain": [25, 15, 30, 0],
	"storm": [5, 15, 3, 0],
	"snow": [0, 0, 0, 30],
	"fog": [5, 5, 12, 5],
}
## Виды, которых ещё нет в игре, отдают свою долю другим (решение владельца 22.10.2026):
## тучи — в «ясно», гроза — в «дождь». Когда вид появится, строку отсюда убрать.
const FOLD := {"clouds": "clear", "storm": "rain"}

## Как выглядит и что делает каждый вид.
## light — множитель солнца (и силы теней); tint — чем подкрасить свет; fog — плотность дымки;
## fall — что падает с неба; waters — поливает ли огород.
const TYPES := {
	"clear": {"name": "Ясно", "light": 1.0, "tint": Color(1, 1, 1), "fog": 0.004, "fall": "", "waters": false},
	"rain": {"name": "Дождь", "light": 0.35, "tint": Color(0.74, 0.78, 0.86), "fog": 0.012, "fall": "rain", "waters": true},
	"fog": {"name": "Туман", "light": 0.55, "tint": Color(0.88, 0.89, 0.92), "fog": 0.022, "fall": "", "waters": false},
	"snow": {"name": "Снег", "light": 0.6, "tint": Color(0.9, 0.92, 0.97), "fog": 0.01, "fall": "snow", "waters": false},
}

const CHANGE_CHANCE := 0.2   # шанс, что погода сменится днём (решение владельца 22.10.2026)
const CHANGE_FROM := 7 * 60  # смена — в любое время дня, между 7:00 и 20:00
const CHANGE_TO := 20 * 60
const BLEND := 60.0          # переход — около 1 игрового часа
const SNOW_MELT := 0.5       # шанс, что лежащий снег сойдёт за ночь без снегопада


## Вид погоды по шансам сезона.
static func pick(season_index: int, rng: RandomNumberGenerator) -> String:
	var weights := {}
	for id in CHANCE:
		var to: String = FOLD.get(id, id)
		weights[to] = weights.get(to, 0) + int(CHANCE[id][season_index])
	var total := 0
	for id in weights:
		total += weights[id]
	var r := rng.randi_range(1, maxi(total, 1))
	for id in weights:
		r -= weights[id]
		if r <= 0:
			return id
	return "clear"


## План погоды на день: утренняя погода и, возможно, одна смена днём.
static func plan(day: int, rng: RandomNumberGenerator) -> Dictionary:
	var s := Location.season_index(day)
	var am := pick(s, rng)
	# снег в 1-й день зимы обязателен
	if Location.season_id(day) == "winter" and Location.season_day(day) == 1:
		am = "snow"
	var p := {"am": am, "pm": am, "at": -1}
	if rng.randf() < CHANGE_CHANCE:
		var pm := pick(s, rng)
		if pm != am:
			p["pm"] = pm
			p["at"] = rng.randi_range(CHANGE_FROM, CHANGE_TO)
	return p


## Погода на весь день без смены (админ-панель).
static func fixed(id: String) -> Dictionary:
	return {"am": id, "pm": id, "at": -1}


## Какая погода сейчас и насколько прошёл переход к ней (0..1; 1 — переход закончен).
static func now(p: Dictionary, minutes: float) -> Array:
	var at := float(p.get("at", -1))
	if at < 0.0 or minutes < at:
		return [String(p.get("am", "clear")), 1.0]
	return [String(p.get("pm", "clear")), clampf((minutes - at) / BLEND, 0.0, 1.0)]


## Шла ли эта погода в какой-то момент дня до minutes (для полива дождём). Утренняя погода идёт с утра.
static func had(p: Dictionary, id: String, minutes: float) -> bool:
	if String(p.get("am", "")) == id:
		return true
	return int(p.get("at", -1)) >= 0 and minutes >= float(p["at"]) and String(p.get("pm", "")) == id


static func waters_now(p: Dictionary, minutes: float) -> bool:
	for id in TYPES:
		if TYPES[id]["waters"] and had(p, id, minutes):
			return true
	return false


## Как выглядит погода в эту минуту: свет, подкраска, дымка, дождь и снег (0..1), с плавным переходом.
static func look(p: Dictionary, minutes: float) -> Dictionary:
	var a: Dictionary = TYPES.get(String(p.get("am", "clear")), TYPES["clear"])
	var b := a
	var k := 0.0
	var at := float(p.get("at", -1))
	if at >= 0.0 and minutes >= at:
		b = TYPES.get(String(p.get("pm", "clear")), TYPES["clear"])
		k = clampf((minutes - at) / BLEND, 0.0, 1.0)
	return {
		"light": lerpf(a["light"], b["light"], k),
		"tint": (a["tint"] as Color).lerp(b["tint"], k),
		"fog": lerpf(a["fog"], b["fog"], k),
		"rain": lerpf(1.0 if a["fall"] == "rain" else 0.0, 1.0 if b["fall"] == "rain" else 0.0, k),
		"snow": lerpf(1.0 if a["fall"] == "snow" else 0.0, 1.0 if b["fall"] == "snow" else 0.0, k),
	}


static func name_of(id: String) -> String:
	return TYPES.get(id, TYPES["clear"])["name"]
