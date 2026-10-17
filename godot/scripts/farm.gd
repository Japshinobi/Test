extends RefCounted
## Общий огород: грядки, семена, урожай, деньги. Правила те же, что в браузерной версии (game/index.html)
## и в Unity (OgorodCore.cs). Этим состоянием владеет хозяин игры, остальные получают его копию по сети.

const Location := preload("res://scripts/location.gd")

## Рост в игровых днях; сезон — 12 дней. Вне своих сезонов растение вянет.
## regrow — через сколько дней плодоносит снова после сбора (0 — растение убирается целиком).
const CROPS := [
	{"key": "radish", "name": "Редис", "product": "Редис", "seed_name": "Семена редиса", "seed": 8, "sell": 22, "grow": 3, "seasons": ["spring", "autumn"]},
	{"key": "peas", "name": "Горох", "product": "Горох", "seed_name": "Семена гороха", "seed": 20, "sell": 14, "grow": 6, "regrow": 3, "seasons": ["spring"]},
	{"key": "potato", "name": "Картофель", "product": "Картофель", "seed_name": "Семенной картофель", "seed": 15, "sell": 55, "grow": 8, "seasons": ["spring"]},
	{"key": "carrot", "name": "Морковь", "product": "Морковь", "seed_name": "Семена моркови", "seed": 20, "sell": 80, "grow": 10, "seasons": ["spring", "autumn"]},
	{"key": "strawberry", "name": "Клубника", "product": "Клубника", "seed_name": "Рассада клубники", "seed": 40, "sell": 30, "grow": 8, "regrow": 4, "seasons": ["spring", "summer"]},
	{"key": "cucumber", "name": "Огурец", "product": "Огурцы", "seed_name": "Семена огурцов", "seed": 15, "sell": 12, "grow": 5, "regrow": 2, "seasons": ["summer"]},
	{"key": "tomato", "name": "Помидор", "product": "Помидоры", "seed_name": "Рассада томатов", "seed": 25, "sell": 24, "grow": 7, "regrow": 3, "seasons": ["summer"]},
	{"key": "corn", "name": "Кукуруза", "product": "Кукуруза", "seed_name": "Семена кукурузы", "seed": 20, "sell": 75, "grow": 8, "seasons": ["summer"]},
	{"key": "pumpkin", "name": "Тыква", "product": "Тыква", "seed_name": "Семена тыквы", "seed": 50, "sell": 240, "grow": 11, "seasons": ["summer", "autumn"]},
	{"key": "apple", "name": "Яблоня", "product": "Яблоки", "seed_name": "Саженец яблони", "seed": 200, "sell": 40, "grow": 12, "regrow": 3, "yield": 3, "tree": true,
		"seasons": ["spring", "summer", "autumn", "winter"], "plant": ["spring", "summer", "autumn"], "fruit": ["autumn"]},
]
const SEASON_RU := {"spring": "весна", "summer": "лето", "autumn": "осень", "winter": "зима"}
const CAN_CAP := 10

var day := 1
var money := 100
var seeds := {}       # культура -> сколько семян
var produce := {}     # культура -> сколько урожая в инвентаре
var shipped := {}     # культура -> сколько лежит в ящике для продажи (оплата утром)
## Грядки: "x,y" -> {tilled, watered, crop, age, ripe, grown, dead}
var plots := {}
## Лейка у каждого своя: id игрока -> литров воды
var water := {}
## Предметы на земле: id -> {key, x, z}
var drops := {}
var next_drop := 1
var snow := false


func _init() -> void:
	for c in CROPS:
		seeds[c["key"]] = 0
		produce[c["key"]] = 0
		shipped[c["key"]] = 0
	seeds["radish"] = 6
	seeds["potato"] = 3


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
func use(map: Location, peer: int, x: int, y: int, tool: String, crop_key: String) -> Dictionary:
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
		p["crop"] = ""
		p["dead"] = false
		return {"msg": "Увядшее растение убрано. Грядка свободна.", "plot": true}
	if p != null and p["crop"] != "" and p["ripe"]:
		var key: String = p["crop"]
		var n := harvest(p)
		return {"plot": true, "harvest": [key, n]}
	if season == "winter" and tool != "can":
		return {"msg": "Зимой земля промёрзла. Огород отдыхает до весны."}
	match tool:
		"hoe":
			if p == null:
				plots[cell_key(x, y)] = {"tilled": true, "watered": false, "crop": "", "age": 0.0, "ripe": false, "grown": false, "dead": false}
				return {"plot": true}
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
			return {"plot": true, "water": true}
		"seed":
			var d := crop(crop_key)
			if p == null:
				return {"msg": "Сначала вскопайте землю мотыгой."}
			if p["crop"] != "":
				return {"msg": "Тут уже растёт: %s." % crop(p["crop"])["name"].to_lower()}
			if seeds.get(crop_key, 0) <= 0:
				return {"msg": "Закончилось: %s. Купите на рынке." % d["seed_name"].to_lower()}
			if not can_plant(crop_key, season):
				return {"msg": "%s: сажают в сезон «%s». Сейчас %s." % [d["name"], seasons_ru(d.get("plant", d["seasons"])), SEASON_RU[season]]}
			seeds[crop_key] -= 1
			p["crop"] = crop_key
			p["age"] = 0.0
			p["ripe"] = false
			p["grown"] = false
			p["dead"] = false
			return {"plot": true, "inv": true}
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
	var snowed := Location.snowing(day)
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
	else:
		snow = false
	m["snowed"] = snowed
	return m


static func _add(d: Dictionary, k: String) -> void:
	d[k] = d.get(k, 0) + 1


## Положить урожай в ящик для продажи: key — культура, "" — всё сразу; n — сколько (0 — всё).
func ship(key: String, n: int) -> void:
	for c in CROPS:
		var k: String = c["key"]
		if key != "" and k != key:
			continue
		var take: int = produce[k] if n <= 0 else mini(n, produce[k])
		produce[k] -= take
		shipped[k] += take


func add_drop(key: String, x: float, z: float) -> int:
	var id := next_drop
	next_drop += 1
	drops[id] = {"key": key, "x": x, "z": z}
	return id


## Всё состояние одним словарём: для отправки по сети (и для сохранения игры потом).
func to_dict() -> Dictionary:
	return {"day": day, "money": money, "seeds": seeds, "produce": produce, "shipped": shipped,
		"plots": plots, "drops": drops, "next_drop": next_drop, "snow": snow}


func from_dict(d: Dictionary) -> void:
	day = int(d["day"])
	money = int(d["money"])
	seeds = d["seeds"]
	produce = d["produce"]
	shipped = d["shipped"]
	plots = d["plots"]
	drops = {}
	for id in d["drops"]:
		drops[int(id)] = d["drops"][id]
	next_drop = int(d["next_drop"])
	snow = d["snow"]
