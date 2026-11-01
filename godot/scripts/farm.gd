extends RefCounted
## Общий огород: грядки, семена, урожай, деньги. Правила те же, что в браузерной версии (game/index.html)
## и в Unity (OgorodCore.cs). Этим состоянием владеет хозяин игры, остальные получают его копию по сети.

const Location := preload("res://scripts/location.gd")
const Weather := preload("res://scripts/weather.gd")

## Рост в игровых днях; сезон — 12 дней. Вне своих сезонов растение вянет.
## regrow — через сколько дней плодоносит снова после сбора (0 — растение убирается целиком).
## "frost": true — культура боится заморозков (лист «Культуры и погода» в design/weather.xlsx).
const CROPS := [
	{"key": "radish", "name": "Редис", "product": "Редис", "seed_name": "Семена редиса", "seed": 8, "sell": 22, "grow": 3, "seasons": ["spring", "autumn"]},
	{"key": "peas", "name": "Горох", "product": "Горох", "seed_name": "Семена гороха", "seed": 20, "sell": 14, "grow": 6, "regrow": 3, "seasons": ["spring"]},
	{"key": "potato", "name": "Картофель", "product": "Картофель", "seed_name": "Семенной картофель", "seed": 15, "sell": 55, "grow": 8, "seasons": ["spring"], "frost": true},
	{"key": "carrot", "name": "Морковь", "product": "Морковь", "seed_name": "Семена моркови", "seed": 20, "sell": 80, "grow": 10, "seasons": ["spring", "autumn"]},
	{"key": "strawberry", "name": "Клубника", "product": "Клубника", "seed_name": "Рассада клубники", "seed": 40, "sell": 30, "grow": 8, "regrow": 4, "seasons": ["spring", "summer"], "frost": true},
	{"key": "cucumber", "name": "Огурец", "product": "Огурцы", "seed_name": "Семена огурцов", "seed": 15, "sell": 12, "grow": 5, "regrow": 2, "seasons": ["summer"], "frost": true},
	{"key": "tomato", "name": "Помидор", "product": "Помидоры", "seed_name": "Рассада томатов", "seed": 25, "sell": 24, "grow": 7, "regrow": 3, "seasons": ["summer"], "frost": true},
	{"key": "corn", "name": "Кукуруза", "product": "Кукуруза", "seed_name": "Семена кукурузы", "seed": 20, "sell": 75, "grow": 8, "seasons": ["summer"], "frost": true},
	{"key": "pumpkin", "name": "Тыква", "product": "Тыква", "seed_name": "Семена тыквы", "seed": 50, "sell": 240, "grow": 11, "seasons": ["summer", "autumn"], "frost": true},
	{"key": "apple", "name": "Яблоня", "product": "Яблоки", "seed_name": "Саженец яблони", "seed": 200, "sell": 40, "grow": 12, "regrow": 3, "yield": 3, "tree": true,
		"seasons": ["spring", "summer", "autumn", "winter"], "plant": ["spring", "summer", "autumn"], "fruit": ["autumn"]},
]
const SEASON_RU := {"spring": "весна", "summer": "лето", "autumn": "осень", "winter": "зима"}
const CAN_CAP := 10
## Инвентарь: 20 ячеек (два ряда панели по 10). Третий ряд откроется, когда появятся предметы-расширения.
const INV_SIZE := 20
const ROW := 10
const ROWS := 3
const STACK := 99
const TOOLS := {
	"hoe": {"name": "Мотыга", "icon": "icon_hoe"},
	"can": {"name": "Лейка", "icon": "icon_can"},
	"axe": {"name": "Топор", "icon": "icon_axe"},
	"pick": {"name": "Кирка", "icon": "icon_pick"},
	"scythe": {"name": "Коса", "icon": "icon_scythe"},
}
const RES := {"wood": {"name": "Древесина", "icon": "icon_wood"}, "stone": {"name": "Камень", "icon": "icon_stone"}}

var day := 1
var money := 100
## Инвентарь у каждого свой: id игрока -> массив ячеек; ячейка — null или {"id": "seed:radish", "n": 6}.
## Предметы: "tool:hoe", "tool:can", "tool:axe", "tool:pick", "seed:<культура>", "prod:<культура>".
var inv := {}
var shipped := {}     # культура -> сколько лежит в ящике для продажи (оплата утром)
## Грядки: "x,y" -> {tilled, watered, crop, age, ripe, grown, dead}
var plots := {}
## Лейка у каждого своя: id игрока -> литров воды
var water := {}
## Предметы на земле: id -> {item, n, x, z}
var drops := {}
var next_drop := 1
## Лежит ли снег на земле (зимой): ложится после снегопада, без снегопада сходит случайно.
var snow := false
## Погода (решает хозяин): day — для какого дня планы; today и next — планы на сегодня и завтра (см. weather.gd);
## wet — дождь сегодня уже был: огород полит на весь день; frost — день, в ночь после которого заморозки (-1 — нет).
var weather := {"day": 1, "today": Weather.fixed("clear"), "next": Weather.fixed("clear"), "wet": false}
var rng := RandomNumberGenerator.new()
## Изменения карт по локациям: что срубили, разбили, скосили. "farm" -> {"x,y": изменение}
var mods := {}
## Протоптанный снег: локация -> {"x,y": true}. Свежий снег засыпает следы, весной снег тает.
var snow_trod := {}


func _init() -> void:
	for c in CROPS:
		shipped[c["key"]] = 0
	rng.randomize()
	new_weather(day)


# ---------- погода ----------

## Погода на день d: «завтра» из прошлого плана становится «сегодня», на завтра выбирается новая.
func new_weather(d: int) -> void:
	var today: Dictionary = weather["next"] if int(weather.get("day", 0)) + 1 == d else Weather.plan(d, rng)
	# заморозки решаются один раз на окно, в его первый день
	var frost := int(weather.get("frost", -1))
	var roll := Weather.frost_roll(d, rng)
	if roll != -2:
		frost = roll
	weather = {"day": d, "today": today, "next": Weather.plan(d + 1, rng), "wet": false, "frost": frost}


## Погода на сегодня — вручную (админ-панель), с минуты minutes; удары молнии — на остаток дня.
func set_weather(id: String, minutes := Weather.DAY_START) -> void:
	weather["today"] = Weather.fixed(id, minutes, rng)
	weather["wet"] = false


## Молния ударила в грядку: посев сгорает — остаётся обгоревшее растение, его убирают, как увядшее.
## Деревья (яблоню) молния не трогает. true — грядка изменилась.
func burn(x: int, y: int) -> bool:
	var p: Variant = plot_at(x, y)
	if p == null or p["crop"] == "" or p["dead"] or crop(p["crop"]).get("tree", false):
		return false
	p["dead"] = true
	p["ripe"] = false
	p["burnt"] = true
	return true


## Ночь заморозков: один шанс от 1 до 5% на ночь — с ним гибнет каждое растущее растение, которое боится
## заморозков (остаётся увядшим); остальные растущие посевы (кроме деревьев) созреют на день позже.
## Возвращает погибшие: культура -> сколько.
func frost_night() -> Dictionary:
	var killed := {}
	var chance := rng.randf_range(Weather.FROST_KILL[0], Weather.FROST_KILL[1])
	for key in plots:
		var p: Dictionary = plots[key]
		if p["crop"] == "" or p["dead"] or p["ripe"] or crop(p["crop"]).get("tree", false):
			continue
		if crop(p["crop"]).get("frost", false) and rng.randf() < chance:
			p["dead"] = true
			_add(killed, p["crop"])
		else:
			p["age"] = maxf(0.0, float(p["age"]) - 1.0)
	return killed


## Если сегодня уже шёл дождь — полить весь огород (один раз за день). true — грядки изменились.
func apply_rain(minutes: float) -> bool:
	if weather.get("wet", false) or not Weather.waters_now(weather["today"], minutes):
		return false
	weather["wet"] = true
	for key in plots:
		plots[key]["watered"] = true
	return true


# ---------- предметы и инвентарь ----------

## Название, картинка и сколько штук помещается в ячейку.
static func item_info(id: String) -> Dictionary:
	var kind := id.get_slice(":", 0)
	var key := id.get_slice(":", 1)
	match kind:
		"tool":
			var t: Dictionary = TOOLS.get(key, {"name": key, "icon": "icon_hoe"})
			return {"name": t["name"], "icon": t["icon"], "stack": 1, "edible": false}
		"seed":
			return {"name": crop(key).get("seed_name", key), "icon": "seed_" + key, "stack": STACK, "edible": false}
		"prod":
			return {"name": crop(key).get("product", key), "icon": "prod_" + key, "stack": STACK, "edible": false}
		"res":
			var r: Dictionary = RES.get(key, {"name": key, "icon": "icon_wood"})
			return {"name": r["name"], "icon": r["icon"], "stack": STACK, "edible": false}
	return {"name": id, "icon": "icon_hoe", "stack": 1, "edible": false}


## Стартовый набор каждого игрока.
static func new_inventory() -> Array:
	var a := []
	a.resize(INV_SIZE)
	var start := [["tool:hoe", 1], ["tool:can", 1], ["tool:axe", 1], ["tool:pick", 1], ["tool:scythe", 1], ["seed:radish", 6], ["seed:potato", 3]]
	for i in start.size():
		a[i] = {"id": start[i][0], "n": start[i][1]}
	return a


func inv_of(peer: int) -> Array:
	if not inv.has(peer):
		inv[peer] = new_inventory()
	return inv[peer]


## Положить предметы в инвентарь: сначала в стопки того же предмета, потом в пустые ячейки.
## Возвращает, сколько не поместилось.
func add_item(peer: int, id: String, n: int) -> int:
	var a := inv_of(peer)
	var cap: int = item_info(id)["stack"]
	for i in a.size():
		if n <= 0:
			break
		if a[i] != null and a[i]["id"] == id and a[i]["n"] < cap:
			var put := mini(n, cap - a[i]["n"])
			a[i]["n"] += put
			n -= put
	for i in a.size():
		if n <= 0:
			break
		if a[i] == null:
			var put := mini(n, cap)
			a[i] = {"id": id, "n": put}
			n -= put
	return n


## Сколько таких предметов у игрока.
func count(peer: int, id: String) -> int:
	var total := 0
	for s in inv_of(peer):
		if s != null and s["id"] == id:
			total += s["n"]
	return total


## Забрать n штук из ячейки (0 — всё). Возвращает, что забрали: {id, n} или null.
func take(peer: int, slot: int, n: int) -> Variant:
	var a := inv_of(peer)
	if slot < 0 or slot >= a.size() or a[slot] == null:
		return null
	var s: Dictionary = a[slot]
	var k: int = s["n"] if n <= 0 else mini(n, s["n"])
	s["n"] -= k
	if s["n"] <= 0:
		a[slot] = null
	return {"id": s["id"], "n": k}


## Поменять местами две ячейки (или сложить одинаковые в одну стопку).
func move(peer: int, from: int, to: int) -> void:
	var a := inv_of(peer)
	if from == to or from < 0 or to < 0 or from >= a.size() or to >= a.size():
		return
	var s: Variant = a[from]
	var d: Variant = a[to]
	if s != null and d != null and s["id"] == d["id"]:
		var cap: int = item_info(s["id"])["stack"]
		var put := mini(s["n"], cap - d["n"])
		d["n"] += put
		s["n"] -= put
		a[from] = s if s["n"] > 0 else null
		return
	a[from] = d
	a[to] = s


static func crop(key: String) -> Dictionary:
	for c in CROPS:
		if c["key"] == key:
			return c
	return {}


static func in_season(key: String, season: String) -> bool:
	return season in crop(key)["seasons"]


static func can_plant(key: String, season: String) -> bool:
	return season in crop(key).get("plant", crop(key)["seasons"])


static func seasons_ru(list: Array) -> String:
	return ", ".join(list.map(func(s): return SEASON_RU[s]))


## Стадия роста для картинки: 0 семя, 1 росток, 2 куст (или выросшее дерево), 3 созрело.
static func stage(p: Dictionary) -> int:
	var d := crop(p["crop"])
	if p["ripe"]:
		return 3
	if d.get("tree", false) and p["grown"]:
		return 2
	var f: float = p["age"] / float(d["grow"])
	return 0 if f < 0.3 else (1 if f < 0.6 else 2)


## Цена на рынке плавает изо дня в день; ящик для продажи платит на 10% меньше.
static func price(day_: int, key: String) -> int:
	var idx := CROPS.find(crop(key))
	var factor := 0.8 + 0.45 * Location.hash3(day_, idx + 1, 99)
	return maxi(1, roundi(crop(key)["sell"] * factor))


static func bin_price(day_: int, key: String) -> int:
	return maxi(1, roundi(price(day_, key) * 0.9))


static func cell_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


func plot_at(x: int, y: int) -> Variant:
	return plots.get(cell_key(x, y))


func water_of(peer: int) -> int:
	return water.get(peer, CAN_CAP)


## Где можно копать: трава без предметов, кроме двора вокруг дома (дом и две клетки вокруг).
static func farmable(map: Location, x: int, y: int) -> bool:
	var g := map.ground_at(x, y)
	if (g != "." and g != ",") or map.object_at(x, y) != null:
		return false
	for o in map.objects:
		if Location.def(o["id"]).get("model", "") == "house":
			var s := Location.object_size(o["id"])
			if x >= o["x"] - 2 and x < o["x"] + s.x + 2 and y >= o["y"] - 2 and y < o["y"] + s.y + 2:
				return false
	return true


## Действие инструментом по клетке. Возвращает {msg} для игрока и что изменилось:
## {plot: true} — грядка, {inv: true} — семена и деньги, {water: true} — лейка, {harvest: [key, n]} — что выпало.
func use(map: Location, peer: int, x: int, y: int, slot: int) -> Dictionary:
	if map.id != "farm":
		var g0 := map.ground_at(x, y)
		if g0 == "." or g0 == "," or g0 == "=":
			return {"msg": "Копать можно только у себя на огороде."}
		return {}
	var held: Variant = inv_of(peer)[slot] if slot >= 0 and slot < inv_of(peer).size() else null
	var held_id: String = held["id"] if held != null else ""
	var tool := held_id.get_slice(":", 1) if held_id.begins_with("tool:") else ("seed" if held_id.begins_with("seed:") else "")
	var crop_key := held_id.get_slice(":", 1)
	var p: Variant = plot_at(x, y)
	var season := Location.season_id(day)
	if p == null and not farmable(map, x, y):
		if tool != "can":
			var g := map.ground_at(x, y)
			if g == "=":
				return {"msg": "На дороге копать нельзя."}
			if g == "P":
				return {"msg": "Это место под постройку."}
			if g == "." or g == ",":
				return {"msg": "Во дворе у дома копать нельзя: отойдите на пару шагов."}
		return {}
	if p != null and p["crop"] != "" and p["dead"]:
		var burnt: bool = p.get("burnt", false)
		p["crop"] = ""
		p["dead"] = false
		p.erase("burnt")
		return {"msg": ("Обгоревшее" if burnt else "Увядшее") + " растение убрано. Грядка свободна.", "plot": true, "fx": "till"}
	if p != null and p["crop"] != "" and p["ripe"]:
		var key: String = p["crop"]
		var n := harvest(p)
		return {"plot": true, "harvest": [key, n], "fx": "harvest"}
	if tool == "axe" or tool == "pick" or tool == "scythe":
		return {}
	if tool == "":
		return {}
	if season == "winter" and tool != "can":
		return {"msg": "Зимой земля промёрзла. Огород отдыхает до весны."}
	match tool:
		"hoe":
			if p == null:
				# после дождя новая грядка тоже полита: огород полит на весь день
				plots[cell_key(x, y)] = {"tilled": true, "watered": weather.get("wet", false), "crop": "", "age": 0.0, "ripe": false, "grown": false, "dead": false}
				return {"plot": true, "fx": "till"}
			if p["crop"] != "":
				return {"msg": "Тут растёт: %s." % crop(p["crop"])["name"].to_lower()}
			return {"msg": "Земля уже вскопана. Выберите семена."}
		"can":
			if p == null:
				return {"msg": "Сначала вскопайте землю мотыгой."}
			if season == "winter":
				return {"msg": "Зимой поливать не нужно: земля спит под снегом."}
			if p["watered"]:
				return {"msg": "Здесь уже полито."}
			if water_of(peer) <= 0:
				return {"msg": "Лейка пуста. Наберите воды в колодце или пруду."}
			water[peer] = water_of(peer) - 1
			p["watered"] = true
			return {"plot": true, "water": true, "fx": "water"}
		"seed":
			var d := crop(crop_key)
			if p == null:
				return {"msg": "Сначала вскопайте землю мотыгой."}
			if p["crop"] != "":
				return {"msg": "Тут уже растёт: %s." % crop(p["crop"])["name"].to_lower()}
			if held == null or held["n"] <= 0:
				return {"msg": "Закончилось: %s. Купите на рынке." % d["seed_name"].to_lower()}
			if not can_plant(crop_key, season):
				return {"msg": "%s: сажают в сезон «%s». Сейчас %s." % [d["name"], seasons_ru(d.get("plant", d["seasons"])), SEASON_RU[season]]}
			take(peer, slot, 1)
			p["crop"] = crop_key
			p["age"] = 0.0
			p["ripe"] = false
			p["grown"] = false
			p["dead"] = false
			return {"plot": true, "inv": true, "fx": "plant"}
	return {}


## Сбор созревшего: сколько штук выпадет. Многолетнее растение остаётся и растёт заново.
static func harvest(p: Dictionary) -> int:
	var d := crop(p["crop"])
	var n: int = d.get("yield", 1)
	var regrow: int = d.get("regrow", 0)
	if regrow > 0:
		p["ripe"] = false
		p["age"] = float(d["grow"] - regrow)
		if d.get("tree", false):
			p["grown"] = true
	else:
		p["crop"] = ""
		p["age"] = 0.0
		p["ripe"] = false
	return n


## Ночь: растения растут (без полива вдвое медленнее), не в свой сезон вянут, ящик платит.
## Возвращает отчёт для утреннего окна.
func new_day() -> Dictionary:
	var m := {"ripened": {}, "withered": {}, "dry": 0, "income": 0, "season_changed": false, "snowed": false}
	if int(weather.get("frost", -1)) == day:
		m["frost"] = frost_night()
	var snowed := Weather.had(weather["today"], "snow", 24.0 * 60.0)
	var before := Location.season_id(day)
	var next := Location.season_id(day + 1)
	m["season_changed"] = next != before
	for key in plots:
		var p: Dictionary = plots[key]
		if p["crop"] != "" and not p["dead"]:
			var d := crop(p["crop"])
			if d.get("tree", false):
				# яблоня живёт круглый год: растёт вне зимы, плодоносит только осенью
				if m["season_changed"] and p["ripe"] and next not in d["fruit"]:
					p["ripe"] = false
					p["age"] = float(d["grow"] - d["regrow"])
				if before != "winter" and not p["ripe"]:
					if not p["grown"] or before in d["fruit"]:
						if not p["watered"]:
							m["dry"] += 1
						p["age"] += 1.0 if p["watered"] else 0.5
					if p["age"] >= d["grow"]:
						p["age"] = float(d["grow"])
						p["grown"] = true
						if next in d["fruit"]:
							p["ripe"] = true
							_add(m["ripened"], p["crop"])
						else:
							p["age"] = float(d["grow"] - d["regrow"])
			elif not p["ripe"]:
				if not p["watered"]:
					m["dry"] += 1
				p["age"] += 1.0 if p["watered"] else 0.5
				if p["age"] >= d["grow"]:
					p["age"] = float(d["grow"])
					p["ripe"] = true
					_add(m["ripened"], p["crop"])
			if m["season_changed"] and not d.get("tree", false) and not in_season(p["crop"], next):
				p["dead"] = true
				p["ripe"] = false
				_add(m["withered"], p["crop"])
				m["ripened"].erase(p["crop"])
		p["watered"] = false
	for c in CROPS:
		m["income"] += shipped[c["key"]] * bin_price(day, c["key"])
		shipped[c["key"]] = 0
	money += m["income"]
	day += 1
	if Location.season_id(day) == "winter":
		if snowed:
			snow = true
			snow_trod = {}
		elif snow and rng.randf() < Weather.SNOW_MELT:
			snow = false
			snow_trod = {}
	else:
		snow = false
		snow_trod = {}
	m["snowed"] = snowed
	new_weather(day)
	# дождь с самого утра — огород полит сразу
	apply_rain(6.0 * 60.0)
	return m


static func _add(d: Dictionary, k: String) -> void:
	d[k] = d.get(k, 0) + 1


# ---------- рынок ----------
# Каждый торговец покупает только свой товар по рыночной цене и продаёт семена своего товара в сезон.
# Универсальный торговец продаёт три вида семян не по сезону на 50% дороже; выбор меняется в 1-й и 6-й день сезона.
const TRADERS := {
	"fruit": {"name": "Фруктовщик", "what": "фрукты", "cat": ["apple"]},
	"veg": {"name": "Овощница", "what": "овощи", "cat": ["radish", "peas", "potato", "carrot", "cucumber", "tomato", "corn", "pumpkin"]},
	"berry": {"name": "Торговка ягодами и грибами", "what": "ягоды и грибы", "cat": ["strawberry"]},
	"any": {"name": "Универсальный торговец", "what": "", "cat": []},
}


static func universal_offer(day_: int) -> Dictionary:
	var sid := Location.season_id(day_)
	var d := Location.season_day(day_)
	var period := ((day_ - 1) / Location.SEASON_DAYS) * 2 + (0 if d <= 5 else 1)
	var pool := []
	for i in CROPS.size():
		if not can_plant(CROPS[i]["key"], sid):
			pool.append([Location.hash3(period, i, 71), CROPS[i]["key"]])
	pool.sort_custom(func(a, b): return a[0] < b[0])
	return {"list": pool.slice(0, 3).map(func(p): return p[1]), "until": 5 if d <= 5 else Location.SEASON_DAYS - 1}


## Что продаёт торговец сегодня и почём.
static func trader_seeds(who: String, day_: int) -> Array:
	if who == "any":
		return universal_offer(day_)["list"].map(func(k): return [k, roundi(crop(k)["seed"] * 1.5)])
	var out := []
	for k in TRADERS[who]["cat"]:
		if can_plant(k, Location.season_id(day_)):
			out.append([k, int(crop(k)["seed"])])
	return out


## Насколько сегодня цена отличается от обычной: "up", "down" или "".
static func trend(day_: int, key: String) -> String:
	var f := 0.8 + 0.45 * Location.hash3(day_, CROPS.find(crop(key)) + 1, 99)
	return "up" if f > 1.08 else ("down" if f < 0.92 else "")


## Продать торговцу урожай игрока: key — культура ("" — всё, что он берёт), n — сколько (0 — всё). Возвращает выручку.
func sell(peer: int, who: String, key: String, n: int) -> int:
	var got := 0
	var a := inv_of(peer)
	for i in a.size():
		var s: Variant = a[i]
		if s == null or not String(s["id"]).begins_with("prod:"):
			continue
		var k := String(s["id"]).get_slice(":", 1)
		if k not in TRADERS[who]["cat"] or (key != "" and k != key):
			continue
		var t: int = s["n"] if n <= 0 else mini(n, s["n"])
		take(peer, i, t)
		got += t * price(day, k)
		if n > 0:
			n -= t
			if n <= 0:
				break
	money += got
	return got


## Купить семена: деньги общие, семена — в инвентарь покупателя. Возвращает сообщение об ошибке или "".
func buy(peer: int, who: String, key: String, n: int) -> String:
	var cost := 0
	for offer in trader_seeds(who, day):
		if offer[0] == key:
			cost = offer[1] * n
	if cost <= 0:
		return "Сегодня этого нет в продаже."
	if money < cost:
		return "Не хватает монет."
	var left := add_item(peer, "seed:" + key, n)
	if left > 0:
		take_id(peer, "seed:" + key, n - left)
		return "Инвентарь полон."
	money -= cost
	return ""


## Забрать n штук предмета id из любых ячеек.
func take_id(peer: int, id: String, n: int) -> void:
	var a := inv_of(peer)
	for i in range(a.size() - 1, -1, -1):
		if n <= 0:
			return
		if a[i] != null and a[i]["id"] == id:
			var t: int = mini(n, a[i]["n"])
			take(peer, i, t)
			n -= t


## Положить урожай игрока в ящик для продажи: key — культура ("" — весь урожай), n — сколько (0 — всё).
func ship(peer: int, key: String, n: int) -> void:
	var a := inv_of(peer)
	for i in a.size():
		var s: Variant = a[i]
		if s == null or not String(s["id"]).begins_with("prod:"):
			continue
		var k := String(s["id"]).get_slice(":", 1)
		if key != "" and k != key:
			continue
		var t: int = s["n"] if n <= 0 else mini(n, s["n"])
		take(peer, i, t)
		shipped[k] += t
		if n > 0:
			n -= t
			if n <= 0:
				return


func add_drop(item: String, n: int, x: float, z: float, loc: String = "farm") -> int:
	var id := next_drop
	next_drop += 1
	drops[id] = {"item": item, "n": n, "x": x, "z": z, "loc": loc}
	return id


## Всё состояние одним словарём: для отправки по сети (и для сохранения игры потом).
func to_dict() -> Dictionary:
	return {"day": day, "money": money, "shipped": shipped, "mods": mods, "snow_trod": snow_trod,
		"plots": plots, "drops": drops, "next_drop": next_drop, "snow": snow, "weather": weather}


func from_dict(d: Dictionary) -> void:
	day = int(d["day"])
	money = int(d["money"])
	shipped = d["shipped"]
	plots = d["plots"]
	drops = {}
	for id in d["drops"]:
		drops[int(id)] = d["drops"][id]
	next_drop = int(d["next_drop"])
	mods = d.get("mods", {})
	snow_trod = d.get("snow_trod", {})
	snow = d["snow"]
	if d.has("weather"):
		weather = d["weather"]
		weather["day"] = int(weather.get("day", day))
		weather["frost"] = int(weather.get("frost", -1))
		for k in ["today", "next"]:
			if weather[k].has("at"):
				weather[k]["at"] = int(weather[k]["at"])
	else:
		new_weather(day)
