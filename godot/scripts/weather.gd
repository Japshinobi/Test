extends RefCounted
## Погода: виды, шансы по сезонам, план на день и как она выглядит в каждую минуту.
## Правила — из design/weather.xlsx (листы «Погода» и «Параметры»), только строки «решено» и «в игре».
## Погоду выбирает хозяин игры; план хранится в состоянии огорода (farm.weather) и приходит гостю вместе с ним.
##
## План на день: {"am": утренняя погода, "pm": погода после смены, "at": минута начала смены (-1 — без смены),
## "strikes": {локация: [игровые минуты ударов молнии]}} — удары выбираются заранее, пока известен план грозы.
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
## Виды, которых ещё нет в игре, отдают свою долю другим (так было 22.10.2026: тучи — в «ясно», гроза — в «дождь»).
## Когда вид появляется, строку отсюда убирают. С 01.11.2026 тучи и гроза в игре — отдавать некому.
const FOLD := {}

## Как выглядит и что делает каждый вид.
## light — множитель солнца (и силы теней); tint — чем подкрасить свет; fog — плотность дымки;
## fall — что падает с неба и сколько (0..1: дождь — 0.65, ливень в грозу — 1); waters — поливает ли огород;
## lightning — бьёт ли молния (и бывают ли вспышки с громом вдали).
const TYPES := {
	"clear": {"name": "Ясно", "light": 1.0, "tint": Color(1, 1, 1), "fog": 0.004, "fall": "", "waters": false},
	"clouds": {"name": "Тучи", "light": 0.5, "tint": Color(0.84, 0.86, 0.91), "fog": 0.007, "fall": "", "waters": false},
	"rain": {"name": "Дождь", "light": 0.35, "tint": Color(0.74, 0.78, 0.86), "fog": 0.012, "fall": "rain", "rain": 0.65, "waters": true},
	"storm": {"name": "Гроза", "light": 0.15, "tint": Color(0.56, 0.6, 0.72), "fog": 0.016, "fall": "rain", "rain": 1.0, "waters": true, "lightning": true},
	"fog": {"name": "Туман", "light": 0.55, "tint": Color(0.88, 0.89, 0.92), "fog": 0.022, "fall": "", "waters": false},
	"snow": {"name": "Снег", "light": 0.6, "tint": Color(0.9, 0.92, 0.97), "fog": 0.01, "fall": "snow", "waters": false},
}
## Перед дождём и грозой сначала собираются тучи (решение владельца 01.11.2026): переход BLEND минут в тучи,
## потом дождь набирает силу за RAMP минут. Если дождь или гроза с утра — сразу.
const GATHER := ["rain", "storm"]
const RAMP := 20.0

## Молния (лист «Параметры», решения владельца 01.11.2026): за полную грозу (с утра до полуночи) — 2 или 3 удара
## в каждой локации; гроза часть дня — пропорционально меньше, но хотя бы 1. На рынке не бьёт: там торговцы (НПЦ).
## Новая локация, где в грозу нет НПЦ, — добавить сюда.
const LIGHTNING_LOCS := ["farm", "cross", "river", "forest"]
const STRIKES_MIN := 2
const STRIKES_MAX := 3
const DAY_START := 6.0 * 60.0
const DAY_END := 24.0 * 60.0
const SAFE := 1              # молния не бьёт в клетку игрока и соседние (квадрат 3×3; через одну — можно)
const FIRE := [5.0, 7.0]     # огонь горит, секунд
const TRACE := [10.0, 15.0]  # горелый след виден после огня, секунд

## Заморозки — ночное явление (лист «Параметры», решения владельца 01.11.2026): окно из 3 ночей — весной после
## 1, 2 или 3-го дня, осенью после 9, 10 или 11-го; в каждом окне с шансом 50% и не больше одного раза.
## В 21:00 холодает и проступает иней; утром иней тает к полудню. Ночью гибнет с одним шансом от 1 до 5% каждое
## растение, которое боится заморозков ("frost" у культуры), а все растущие посевы (кроме деревьев) — +1 день к росту.
const FROST_NIGHTS := {"spring": [1, 2, 3], "autumn": [9, 10, 11]}
const FROST_CHANCE := 0.5
const FROST_KILL := [0.01, 0.05]
const FROST_FROM := 21.0 * 60.0
const FROST_IN := 30.0               # иней проступает за полчаса
const FROST_MELT := [8.0 * 60.0, 12.0 * 60.0]  # утром тает с 8:00 до полудня

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
	p["strikes"] = strikes(p, DAY_START, rng)
	return p


## Погода на весь день без смены (админ-панель); удары молнии — на оставшуюся часть дня с минуты from.
static func fixed(id: String, from := DAY_START, rng: RandomNumberGenerator = null) -> Dictionary:
	var p := {"am": id, "pm": id, "at": -1}
	if rng:
		p["strikes"] = strikes(p, from, rng)
	return p


## Части дня [начало, конец) в игровых минутах, когда идёт молниеносная погода (гроза).
static func storm_spans(p: Dictionary, from := DAY_START) -> Array:
	var out := []
	var segs := _stages(p)
	for i in segs.size():
		if not TYPES.get(segs[i][1], {}).get("lightning", false):
			continue
		var a: float = maxf(float(segs[i][0]), from)
		var b: float = float(segs[i + 1][0]) if i + 1 < segs.size() else DAY_END
		if b > a:
			out.append([a, b])
	return out


## Минуты ударов молнии в каждой локации: 2–3 за полную грозу, меньше — пропорционально её длине (но хотя бы 1).
static func strikes(p: Dictionary, from: float, rng: RandomNumberGenerator) -> Dictionary:
	var spans := storm_spans(p, from)
	var total := 0.0
	for sp in spans:
		total += sp[1] - sp[0]
	var out := {}
	if total <= 0.0:
		return out
	for loc in LIGHTNING_LOCS:
		var n := maxi(1, roundi(rng.randi_range(STRIKES_MIN, STRIKES_MAX) * total / (DAY_END - DAY_START)))
		var times := []
		for i in n:
			# случайная минута внутри грозы
			var r := rng.randf() * total
			for sp in spans:
				if r < sp[1] - sp[0]:
					times.append(snappedf(sp[0] + r, 0.1))
					break
				r -= sp[1] - sp[0]
		times.sort()
		out[loc] = times
	return out


## Идёт ли гроза в эту минуту (после перехода через тучи).
static func lightning_now(p: Dictionary, minutes: float) -> bool:
	return TYPES.get(now(p, minutes)[0], {}).get("lightning", false)


## Этапы дня: [минута начала, погода, сколько минут переход к ней]. Перед дождём и грозой — тучи.
static func _stages(p: Dictionary) -> Array:
	var am := String(p.get("am", "clear"))
	var pm := String(p.get("pm", am))
	var at := float(p.get("at", -1))
	var out := [[0.0, am, 0.0]]
	if at < 0.0 or pm == am:
		return out
	if pm in GATHER and am not in GATHER and am != "clouds":
		out.append([at, "clouds", BLEND])
		out.append([at + BLEND, pm, RAMP])
	else:
		out.append([at, pm, BLEND])
	return out


## Какая погода сейчас и насколько прошёл переход к ней (0..1; 1 — переход закончен).
static func now(p: Dictionary, minutes: float) -> Array:
	var segs := _stages(p)
	var i := _stage_at(segs, minutes)
	var blend: float = segs[i][2]
	return [String(segs[i][1]), 1.0 if blend <= 0.0 else clampf((minutes - float(segs[i][0])) / blend, 0.0, 1.0)]


static func _stage_at(segs: Array, minutes: float) -> int:
	var i := 0
	for j in segs.size():
		if minutes >= float(segs[j][0]):
			i = j
	return i


## Шла ли эта погода в какой-то момент дня до minutes (для полива дождём). Утренняя погода идёт с утра.
static func had(p: Dictionary, id: String, minutes: float) -> bool:
	for seg in _stages(p):
		if seg[1] == id and minutes >= float(seg[0]):
			return true
	return false


static func waters_now(p: Dictionary, minutes: float) -> bool:
	for id in TYPES:
		if TYPES[id]["waters"] and had(p, id, minutes):
			return true
	return false


## Как выглядит погода в эту минуту: свет, подкраска, дымка, дождь и снег (0..1), с плавным переходом.
static func look(p: Dictionary, minutes: float) -> Dictionary:
	var segs := _stages(p)
	var i := _stage_at(segs, minutes)
	var b: Dictionary = TYPES.get(String(segs[i][1]), TYPES["clear"])
	var a: Dictionary = TYPES.get(String(segs[i - 1][1]), TYPES["clear"]) if i > 0 else b
	var k: float = 1.0 if float(segs[i][2]) <= 0.0 else clampf((minutes - float(segs[i][0])) / float(segs[i][2]), 0.0, 1.0)
	return {
		"light": lerpf(a["light"], b["light"], k),
		"tint": (a["tint"] as Color).lerp(b["tint"], k),
		"fog": lerpf(a["fog"], b["fog"], k),
		"rain": lerpf(float(a.get("rain", 0.0)), float(b.get("rain", 0.0)), k),
		"storm": lerpf(1.0 if a.get("lightning", false) else 0.0, 1.0 if b.get("lightning", false) else 0.0, k),
		"snow": lerpf(1.0 if a["fall"] == "snow" else 0.0, 1.0 if b["fall"] == "snow" else 0.0, k),
	}


## Начало окна заморозков (день d — первая ночь окна): выбрать, будут ли заморозки и в какую ночь.
## -1 — в этом окне заморозков нет; -2 — d не начало окна, решать нечего.
static func frost_roll(d: int, rng: RandomNumberGenerator) -> int:
	var nights: Array = FROST_NIGHTS.get(Location.season_id(d), [])
	if nights.is_empty() or Location.season_day(d) != nights[0]:
		return -2
	if rng.randf() >= FROST_CHANCE:
		return -1
	return d + rng.randi_range(0, nights.size() - 1)


## Сколько инея сейчас (0..1): вечером в ночь заморозков — с 21:00, утром после них — до полудня.
static func frost_amount(w: Dictionary, day: int, minutes: float) -> float:
	var night := int(w.get("frost", -1))
	if night == day and minutes >= FROST_FROM:
		return clampf((minutes - FROST_FROM) / FROST_IN, 0.0, 1.0)
	if night == day - 1 and night > 0:
		return 1.0 - clampf((minutes - FROST_MELT[0]) / (FROST_MELT[1] - FROST_MELT[0]), 0.0, 1.0)
	return 0.0


## Барометр (лист «Параметры», решения владельца 01.11.2026): показывает погоду на завтра — план next, он же
## утром станет погодой дня, поэтому прогноз всегда точный. Стрелка: 4 деления; при смене днём — худшая погода.
const GAUGE := {"clear": 0, "clouds": 1, "fog": 1, "snow": 1, "rain": 2, "storm": 3}
const GAUGE_NAMES := ["Ясно", "Переменно", "Дождь", "Буря"]
const FORECAST := {"clear": "ясно", "clouds": "пасмурно", "rain": "дождь", "storm": "гроза", "fog": "туман", "snow": "снег"}
const LATER := {"clear": "днём прояснится", "clouds": "днём затянет тучами", "rain": "днём возможен дождь",
	"storm": "днём возможна гроза", "fog": "днём возможен туман", "snow": "днём возможен снег"}


## Деление стрелки барометра (0 — Ясно … 3 — Буря) для плана дня.
static func gauge(p: Dictionary) -> int:
	var am := String(p.get("am", "clear"))
	var g: int = GAUGE.get(am, 0)
	if int(p.get("at", -1)) >= 0:
		g = maxi(g, GAUGE.get(String(p.get("pm", am)), 0))
	return g


## Текст прогноза: «Завтра: ясно» или «Завтра: ясно, днём возможен дождь».
static func forecast(p: Dictionary) -> String:
	var am := String(p.get("am", "clear"))
	var pm := String(p.get("pm", am))
	var t := "Завтра: %s" % FORECAST.get(am, am)
	if int(p.get("at", -1)) >= 0 and pm != am:
		t += ", " + String(LATER.get(pm, pm))
	return t


static func name_of(id: String) -> String:
	return TYPES.get(id, TYPES["clear"])["name"]
