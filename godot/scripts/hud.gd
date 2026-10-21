extends CanvasLayer
## Интерфейс: игра вдвоём (слева сверху), часы, деньги и лейка (справа сверху), пояс с инструментами
## и семенами (снизу), всплывающие сообщения и окна: сон, утро, ящик для продажи, инвентарь.

const Farm := preload("res://scripts/farm.gd")
const Location := preload("res://scripts/location.gd")

var main: Node
var root: Control
var clock: Label
var money_label: Label
var sleepers_label: Label
var status: Label
var ip_edit: LineEdit
var host_btn: Button
var join_btn: Button
var leave_btn: Button
var net_box: VBoxContainer
var test_box: HBoxContainer
var fast_btn: Button
var belt_box: HBoxContainer
var tool_label: Label
var toast_label: Label
var _toast_t := 0.0
var _belt_sig := ""
var _menu: PopupMenu
const SLOT := 58

## Открытое окно (или null) и его вид: "message", "sleep", "wait", "morning", "ship", "inventory".
var dialog: PanelContainer
var dialog_kind := ""
var fade_rect: ColorRect


func setup(p_main: Node) -> void:
	main = p_main
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = _theme()
	add_child(root)

	# игра вдвоём
	var net := _panel(root)
	net.position = Vector2(12, 12)
	var nv := VBoxContainer.new()
	net.add_child(nv)
	var title := Button.new()
	title.text = "Игра вдвоём  (скрыть)"
	title.flat = true
	title.focus_mode = Control.FOCUS_NONE
	nv.add_child(title)
	net_box = VBoxContainer.new()
	nv.add_child(net_box)
	title.pressed.connect(func() -> void:
		net_box.visible = not net_box.visible
		title.text = "Игра вдвоём  " + ("(скрыть)" if net_box.visible else "(показать)"))
	host_btn = _button(net_box, "Создать игру", func() -> void: main.host_game())
	var row := HBoxContainer.new()
	net_box.add_child(row)
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "адрес друга"
	ip_edit.custom_minimum_size = Vector2(190, 0)
	row.add_child(ip_edit)
	join_btn = _button(row, "Подключиться", func() -> void: main.join_game(ip_edit.text.strip_edges()))
	leave_btn = _button(net_box, "Отключиться", func() -> void: main.leave_game())
	status = Label.new()
	status.custom_minimum_size = Vector2(330, 0)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_font_size_override("font_size", 15)
	net_box.add_child(status)

	# часы, деньги, лейка
	var right := _panel(root)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.position += Vector2(-12, 12)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	clock = Label.new()
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(clock)
	money_label = Label.new()
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	money_label.add_theme_color_override("font_color", Color("#f0cf7a"))
	rv.add_child(money_label)
	var row2 := HBoxContainer.new()
	rv.add_child(row2)
	_button(row2, "Инвентарь", open_inventory)
	_button(row2, "Справка", open_help)
	test_box = HBoxContainer.new()
	row2.add_child(test_box)
	fast_btn = _button(test_box, "Админ", open_admin)
	sleepers_label = Label.new()
	sleepers_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sleepers_label.add_theme_font_size_override("font_size", 14)
	rv.add_child(sleepers_label)

	# пояс внизу
	var bottom := VBoxContainer.new()
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.position.y -= 10
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	tool_label = _outlined_label(16)
	tool_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(tool_label)
	var belt_panel := _panel(bottom)
	belt_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var belt_row := HBoxContainer.new()
	belt_row.add_theme_constant_override("separation", 6)
	belt_panel.add_child(belt_row)
	belt_box = HBoxContainer.new()
	belt_box.add_theme_constant_override("separation", 6)
	belt_row.add_child(belt_box)
	# две стрелки справа: ряд выше / ряд ниже (вместе — высотой с ячейку, шириной в половину)
	var arrows := VBoxContainer.new()
	arrows.add_theme_constant_override("separation", 0)
	belt_row.add_child(arrows)
	for up in [true, false]:
		var a := ArrowButton.new()
		a.up = up
		a.custom_minimum_size = Vector2(SLOT / 2.0, SLOT / 2.0)
		a.focus_mode = Control.FOCUS_NONE
		a.pressed.connect(func() -> void: main.farmnet.set_row(main.farmnet.row + (-1 if up else 1)))
		arrows.add_child(a)
	var hint := _outlined_label(13)
	hint.text = "Тап — подойти и сделать · тянуть или Q/E — камера · два пальца или колесо — приблизить · пробел — действие · 1–0 — панель · I — инвентарь · долгое нажатие на предмет — меню"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(760, 0)
	bottom.add_child(hint)

	# всплывающие сообщения
	toast_label = _outlined_label(20)
	toast_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	toast_label.offset_left = 420
	toast_label.offset_right = -420
	toast_label.offset_top = 215
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(toast_label)

	# затемнение при переходе между локациями
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.02, 0.03, 0.09, 0.0)
	fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fade_rect)
	refresh()


func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		toast_label.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)


func refresh() -> void:
	var m := int(main.minutes)
	clock.text = "День %d · %s · %02d:%02d" % [main.day, main.season_text(), m / 60, m % 60]
	var farm: Farm = main.farmnet.farm
	money_label.text = "Монеты: %d   ·   Лейка: %d/%d" % [farm.money, main.farmnet.my_water, Farm.CAN_CAP]
	var net_state: String = main.net_mode()
	host_btn.visible = net_state == "off"
	join_btn.get_parent().visible = net_state == "off"
	leave_btn.visible = net_state != "off"
	if main.time_frozen:
		clock.text += " (время стоит)"
	status.text = main.net_status
	tool_label.text = "В руках: " + main.farmnet.tool_name()
	_refresh_belt()


## Окно открыто — герой стоит и ждёт.
func is_busy() -> bool:
	return dialog != null


func set_fade(a: float) -> void:
	fade_rect.color.a = clampf(a, 0.0, 1.0)


func toast(text: String) -> void:
	toast_label.text = text
	toast_label.modulate.a = 1.0
	_toast_t = 2.8


# ---------- панель быстрого доступа ----------
# Как в Stardew Valley: панель — это ряды самого инвентаря (по 10 ячеек), стрелки переключают ряд.

func _refresh_belt() -> void:
	var fn: Node = main.farmnet
	var sig: String = str(fn.my_inv) + "|" + str(fn.sel) + "|" + str(fn.row) + "|" + str(fn.my_water)
	if sig == _belt_sig:
		return
	_belt_sig = sig
	for c in belt_box.get_children():
		c.queue_free()
	for i in Farm.ROW:
		belt_box.add_child(_slot_button(fn.row * Farm.ROW + i))
	if dialog_kind == "inventory":
		_fill_inventory_grid()


## Ячейка инвентаря: картинка, количество, выделение; её можно перетаскивать и долго нажимать.
func _slot_button(index: int) -> Button:
	var fn: Node = main.farmnet
	var b := SlotButton.new()
	b.hud = self
	b.index = index
	b.custom_minimum_size = Vector2(SLOT, SLOT)
	b.focus_mode = Control.FOCUS_NONE
	if index >= Farm.INV_SIZE:
		b.disabled = true
		b.tooltip_text = "Закрыто: инвентарь можно будет расширить"
		return b
	var it: Variant = fn.my_inv[index]
	if index == fn.sel:
		b.add_theme_stylebox_override("normal", _box(Color("#4a63a8"), Color("#f0cf7a"), 3))
		b.add_theme_stylebox_override("hover", _box(Color("#5570b8"), Color("#f0cf7a"), 3))
	if it != null:
		var info := Farm.item_info(it["id"])
		b.tooltip_text = info["name"]
		var icon := TextureRect.new()
		icon.texture = _icon(info["icon"])
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 9
		icon.offset_top = 9
		icon.offset_right = -9
		icon.offset_bottom = -9
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(icon)
		if it["n"] > 1:
			var n := _outlined_label(13)
			n.text = str(it["n"])
			n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			n.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			n.set_anchors_preset(Control.PRESET_FULL_RECT)
			n.offset_right = -4
			n.offset_bottom = -1
			b.add_child(n)
	b.pressed.connect(func() -> void: fn.select(index))
	return b


## Клавиши 1–0: ячейка в текущем ряду.
func select_slot(i: int) -> void:
	var fn: Node = main.farmnet
	fn.select(fn.row * Farm.ROW + i)


## Меню предмета по долгому нажатию (или правой кнопкой).
func open_item_menu(index: int) -> void:
	var fn: Node = main.farmnet
	if index >= fn.my_inv.size() or fn.my_inv[index] == null:
		return
	var info := Farm.item_info(fn.my_inv[index]["id"])
	if _menu:
		_menu.queue_free()
	_menu = PopupMenu.new()
	_menu.add_theme_font_size_override("font_size", 20)
	_menu.add_item("Выбросить", 0)
	_menu.add_item("Использовать", 1)
	_menu.set_item_disabled(1, not info["edible"])
	_menu.add_item("Стереть", 2)
	root.add_child(_menu)
	_menu.id_pressed.connect(_on_item_menu.bind(index))
	_menu.position = Vector2i(get_viewport().get_mouse_position())
	_menu.popup()


func _on_item_menu(id: int, index: int) -> void:
	if id == 0:
		drop_slot(index)
	elif id == 2:
		_confirm_erase(index)


## Выбросить предмет из ячейки на землю перед собой.
func drop_slot(index: int) -> void:
	var me: Node3D = main.me
	var f: float = main.me.face
	var p := me.position + Vector3(sin(f), 0, cos(f)) * 0.9
	main.farmnet.request("drop", [index, 0, p.x, p.z, main.loc_id])


func _confirm_erase(index: int) -> void:
	var fn: Node = main.farmnet
	var it: Variant = fn.my_inv[index]
	if it == null:
		return
	var reopen := dialog_kind == "inventory"
	var v := _open("erase", "Стереть предмет?")
	_text(v, "«%s» (%d шт.) исчезнет совсем. Это нельзя отменить." % [Farm.item_info(it["id"])["name"], it["n"]])
	var h := _buttons(v)
	_button(h, "Стереть", func() -> void:
		close_dialog()
		fn.request("erase", [index])
		if reopen:
			open_inventory())
	_button(h, "Отмена", func() -> void:
		close_dialog()
		if reopen:
			open_inventory())


func _icon(name: String) -> Texture2D:
	var t := AtlasTexture.new()
	t.atlas = main.atlas.texture
	t.region = Rect2(main.atlas.rect(name))
	return t


# ---------- окна ----------

## Открыть окно с заголовком; возвращает контейнер, куда класть содержимое.
func _open(kind: String, title: String, width := 520) -> VBoxContainer:
	close_dialog()
	dialog_kind = kind
	var shade := DropZone.new()
	shade.hud = self
	shade.color = Color(0, 0, 0, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog = PanelContainer.new()
	dialog.add_child(shade)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	root.add_child(dialog)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE    # чтобы предмет можно было бросить на затемнение вокруг окна
	dialog.add_child(center)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 22)
	t.add_theme_color_override("font_color", Color("#f0cf7a"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	return v


func close_dialog() -> void:
	if dialog:
		dialog.queue_free()
		dialog = null
	dialog_kind = ""


func _text(v: Control, text: String, size := 17) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	v.add_child(l)
	return l


func _buttons(v: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	return h


func show_message(title: String, text: String) -> void:
	var v := _open("message", title)
	_text(v, text)
	_button(_buttons(v), "Понятно", close_dialog)


func ask_sleep() -> void:
	var v := _open("sleep", "Дедушкин дом")
	_text(v, "Лечь спать? Новый день начнётся, когда спать лягут все игроки.")
	var h := _buttons(v)
	_button(h, "Спать", func() -> void:
		close_dialog()
		main.farmnet.request("sleep"))
	_button(h, "Ещё не время", close_dialog)


## Кто уже лёг спать. Если среди них мы — показываем, кого ждём.
func update_sleep(ids: Array) -> void:
	var me: int = main.farmnet.me_id()
	var names := ids.map(func(id): return _player_name(id))
	sleepers_label.text = ("Спят: " + ", ".join(names)) if not ids.is_empty() else ""
	if me in ids:
		var waiting := []
		var everyone: Array = main.farmnet._peers() if main.farmnet.is_host() else [1] + main.remotes.keys()
		for p in everyone:
			if p not in ids and p != me:
				waiting.append(_player_name(p))
		var v := _open("wait", "Вы легли спать")
		_text(v, "Ждём, пока ляжет спать: %s." % ", ".join(waiting) if not waiting.is_empty() else "Засыпаем…")
		_button(_buttons(v), "Встать", func() -> void:
			close_dialog()
			main.farmnet.request("wake"))
	elif dialog_kind == "wait":
		close_dialog()


func _player_name(id: int) -> String:
	return "Ваня" if id == 1 else "Нина"


const SEASON_TEXT := {
	"spring": "Наступила весна! Снег сошёл, деревья просыпаются, на лугу зацветают цветы.",
	"summer": "Наступило лето! Тепло, всё зелёное, самое время для огурцов и помидоров.",
	"autumn": "Наступила осень! Листья скоро пожелтеют, а яблони дадут урожай.",
	"winter": "Наступила зима! Земля промёрзла, огород отдыхает до весны. Скоро выпадет снег.",
}


func show_morning(m: Dictionary, note: String) -> void:
	sleepers_label.text = ""
	var day: int = main.day
	var sid := Location.season_id(day)
	var v := _open("morning", "%s, день %d из %d" % [main.season_text(), Location.season_day(day), Location.SEASON_DAYS], 620)
	var lines := PackedStringArray()
	if m.get("season_changed", false):
		lines.append(SEASON_TEXT[sid])
		if not m.get("withered", {}).is_empty():
			lines.append("Не пережили смену сезона: %s. Уберите увядшие растения с грядок." % ", ".join(m["withered"].keys().map(func(k): return "%s ×%d" % [Farm.crop(k)["name"], m["withered"][k]])))
		var now := Farm.CROPS.filter(func(c): return Farm.can_plant(c["key"], sid)).map(func(c): return String(c["name"]).to_lower())
		if not now.is_empty():
			lines.append("В этом сезоне сажают: %s." % ", ".join(now))
	if m.get("snowed", false) and sid == "winter":
		lines.append("За ночь всё засыпало снегом.")
	if Location.snowing(day):
		lines.append("Сегодня идёт снег.")
	if m.get("income", 0) > 0:
		lines.append("За отгрузку из ящика получено %d монет." % m["income"])
	if note != "":
		lines.append(note)
	var ripe: Dictionary = m.get("ripened", {})
	lines.append(("За ночь созрело: %s." % ", ".join(ripe.keys().map(func(k): return "%s ×%d" % [Farm.crop(k)["product"], ripe[k]]))) if not ripe.is_empty() else "Пока ничего не созрело. Растения тянутся к солнцу.")
	if m.get("dry", 0) > 0:
		lines.append("Без полива осталось растений: %d. Они росли вдвое медленнее." % m["dry"])
	var best := ""
	var best_price := 0.0
	for c in Farm.CROPS:
		var pr := Farm.price(day, c["key"]) / float(c["sell"])
		if best == "" or pr > best_price:
			best = c["key"]
			best_price = pr
	lines.append("Сегодня дороже всего принимают: %s, по %d монет." % [String(Farm.crop(best)["product"]).to_lower(), Farm.price(day, best)])
	_text(v, "\n\n".join(lines), 16)
	_button(_buttons(v), "Доброе утро!", close_dialog)


# ---------- вступление, справка, админ-панель ----------

const HOW := "1. Мотыгой вскопайте землю на любой траве своего огорода (кроме двора у дома и дорог). Камни разбивают киркой, деревья, пни и ветки рубят топором, цветы скашивают косой.\n2. Возьмите семена и посадите их на вскопанную грядку.\n3. Полейте грядку из лейки. Воду набирают в колодце или пруду.\n4. Ночью растения подрастают. Без полива — вдвое медленнее.\n5. Год делится на четыре сезона по 12 дней. У каждой культуры свой сезон: когда он кончается, растение увядает. Зимой огород отдыхает, переживает её только яблоня.\n6. Урожай продают на рынке (вверх до перекрёстка, потом налево) или через ящик у дома — на 10% дешевле, деньги приходят утром. Семена покупают у торговцев; рынок открыт с 8:00 до 18:00, кроме последнего дня сезона.\n7. Дороги у края карты ведут в другие места: вверху перекрёсток, внизу речка, за ней лес.\n8. Чтобы лечь спать и начать новый день, подойдите к двери дома."


func open_intro() -> void:
	var v := _open("intro", "Дедушкин огород", 700)
	_text(v, "Дедушка Матвей оставил внуку Ване и его жене Нине старый дом и заросший огород на краю деревни. В кармане 100 монет и пара пакетиков семян.\n\nПлан простой: вырастить урожай, продать его и привести дедушкин дом в порядок.", 16)
	_text(v, HOW, 14)
	_button(_buttons(v), "Начать", close_dialog)


func open_help() -> void:
	if is_busy():
		return
	var v := _open("help", "Справка", 700)
	_text(v, "День %d. Огород, деньги и ящик для продажи общие; инвентарь у каждого свой." % main.day, 15)
	_text(v, HOW, 14)
	_text(v, "Управление: тап или клик — подойти и сделать; тянуть или Q/E — повернуть камеру; колесо или два пальца — приблизить; пробел — действие; 1–0 — панель; I — инвентарь; H — админ-панель.", 14)
	var h := _buttons(v)
	_button(h, "Играть", close_dialog)
	_button(h, "Звук: " + ("вкл" if main.sound.on else "выкл"), func() -> void:
		main.sound.on = not main.sound.on
		close_dialog()
		open_help())
	if main.farmnet.is_host():
		_button(h, "Начать заново", _confirm_restart)


func _confirm_restart() -> void:
	var v := _open("restart", "Начать заново?")
	_text(v, "Весь прогресс сотрётся: деньги, грядки, инвентарь и всё, что срублено и построено.")
	var h := _buttons(v)
	_button(h, "Да, начать заново", func() -> void:
		close_dialog()
		main.restart_game())
	_button(h, "Нет", close_dialog)


## Админ-панель для проверки: сезон, день, время, выдача предметов. Сезон и день меняются сразу —
## растения при этом не растут и не вянут. Время и день меняет только хозяин игры.
func open_admin() -> void:
	if is_busy() and dialog_kind != "admin":
		return
	var host: bool = main.farmnet.is_host()
	var day: int = main.day
	var v := _open("admin", "Админ-панель", 700)
	_text(v, "Для проверки. При смене сезона и дня растения не растут и не увядают." + ("" if host else " Время и день меняет хозяин игры."), 14)
	if host:
		_text(v, "Сезон", 15).add_theme_color_override("font_color", Color("#9aa0b4"))
		var hs := _buttons(v)
		for i in 4:
			var b := _button(hs, Location.SEASON_NAMES[i], func() -> void:
				main.admin_set_day((day - 1) / (Location.SEASON_DAYS * 4) * Location.SEASON_DAYS * 4 + i * Location.SEASON_DAYS + Location.season_day(day))
				open_admin())
			if Location.season_index(day) == i:
				b.add_theme_stylebox_override("normal", _box(Color("#4a63a8"), Color("#f0cf7a"), 2))
		var hd := _buttons(v)
		_text(hd, "День сезона:", 15)
		var spin := SpinBox.new()
		spin.min_value = 1
		spin.max_value = Location.SEASON_DAYS
		spin.value = Location.season_day(day)
		hd.add_child(spin)
		_button(hd, "Установить", func() -> void:
			main.admin_set_day(day - Location.season_day(day) + int(spin.value))
			open_admin())
		_text(hd, "(всего дней: %d)" % day, 14)
		var ht := _buttons(v)
		_text(ht, "Время:", 15)
		for t in [[360, "6:00"], [720, "12:00"], [1080, "18:00"], [1320, "22:00"]]:
			_button(ht, t[1], func() -> void: main.admin_set_time(t[0]))
		_button(ht, "Запустить время" if main.time_frozen else "Остановить время", func() -> void:
			main.time_frozen = not main.time_frozen
			open_admin())
		var hf := _buttons(v)
		_button(hf, "Пропустить ночь (растения растут)", func() -> void:
			close_dialog()
			main.skip_day())
		_button(hf, "Время ×%d" % (1 if main.fast else 25), func() -> void:
			main.toggle_fast()
			open_admin())
	_text(v, "Добавить в инвентарь", 15).add_theme_color_override("font_color", Color("#9aa0b4"))
	var hg := _buttons(v)
	var pick := OptionButton.new()
	var ids := []
	for t in Farm.TOOLS:
		ids.append("tool:" + t)
	for c in Farm.CROPS:
		ids.append("seed:" + c["key"])
	for c in Farm.CROPS:
		ids.append("prod:" + c["key"])
	for r in Farm.RES:
		ids.append("res:" + r)
	for id in ids:
		pick.add_item(Farm.item_info(id)["name"])
	hg.add_child(pick)
	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 999
	count.value = 10
	hg.add_child(count)
	_button(hg, "Добавить", func() -> void: main.farmnet.request("give", [ids[pick.selected], int(count.value)]))
	_button(_buttons(v), "Закрыть (H)", close_dialog)


## Ящик для продажи: урожай кладут сюда, деньги приходят наутро.
func open_ship() -> void:
	var v := _open("ship", "Ящик для продажи", 600)
	_fill_ship(v)


func _fill_ship(v: VBoxContainer) -> void:
	var farm: Farm = main.farmnet.farm
	_text(v, "Положите урожай — утром за него заплатят (на 10% дешевле, чем на рынке). Деньги общие.", 15)
	var any := false
	var total := 0
	for c in Farm.CROPS:
		var k: String = c["key"]
		var n := 0
		for it in main.farmnet.my_inv:
			if it != null and it["id"] == "prod:" + k:
				n += it["n"]
		if n <= 0:
			continue
		any = true
		var price := Farm.bin_price(farm.day, k)
		total += n * price
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		v.add_child(h)
		var icon := TextureRect.new()
		icon.texture = _icon("prod_" + k)
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		h.add_child(icon)
		var l := _text(h, "%s × %d — по %d" % [c["product"], n, price])
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(h, "1", func() -> void: main.farmnet.request("ship", [k, 1]))
		_button(h, "Все за %d" % (n * price), func() -> void: main.farmnet.request("ship", [k, 0]))
	if not any:
		_text(v, "В инвентаре нет урожая.")
	var inbin := 0
	for c in Farm.CROPS:
		inbin += int(farm.shipped.get(c["key"], 0)) * Farm.bin_price(farm.day, c["key"])
	if inbin > 0:
		_text(v, "Уже в ящике: на %d монет. Деньги придут утром." % inbin, 15)
	var h := _buttons(v)
	if any:
		_button(h, "Положить всё за %d" % total, func() -> void: main.farmnet.request("ship", ["", 0]))
	_button(h, "Закрыть", close_dialog)


## Окно торговца на рынке: «Продать» — урожай из своего инвентаря, «Купить» — семена (деньги общие).
var _trader := ""
var _trader_tab := "sell"


func open_trader(who: String, tab := "") -> void:
	_trader = who
	if tab != "":
		_trader_tab = tab
	if who == "any":
		_trader_tab = "buy"
	var tr: Dictionary = Farm.TRADERS[who]
	var farm: Farm = main.farmnet.farm
	var v := _open("trader", tr["name"], 640)
	_text(v, "Монеты: %d" % farm.money).add_theme_color_override("font_color", Color("#f0cf7a"))
	if who != "any":
		var tabs := _buttons(v)
		for t in [["sell", "Продать"], ["buy", "Купить"]]:
			var b := _button(tabs, t[1], func() -> void: open_trader(who, t[0]))
			if t[0] == _trader_tab:
				b.add_theme_stylebox_override("normal", _box(Color("#4a63a8"), Color("#f0cf7a"), 2))
	if _trader_tab == "sell":
		var total := 0
		var any := false
		for k in tr["cat"]:
			var n := 0
			for it in main.farmnet.my_inv:
				if it != null and it["id"] == "prod:" + k:
					n += it["n"]
			if n <= 0:
				continue
			any = true
			var price := Farm.price(farm.day, k)
			total += n * price
			var h := _item_row(v, "prod_" + k, "%s × %d — по %d %s" % [Farm.crop(k)["product"], n, price, _trend_text(farm.day, k)])
			_button(h, "1", func() -> void: main.farmnet.request("sell", [who, k, 1]))
			_button(h, "Все за %d" % (n * price), func() -> void: main.farmnet.request("sell", [who, k, 0]))
		if any:
			_button(_buttons(v), "Продать всё за %d" % total, func() -> void: main.farmnet.request("sell", [who, "", 0]))
		else:
			_text(v, "%s покупает только %s. У вас их сейчас нет." % [tr["name"], tr["what"]])
	else:
		var offers := Farm.trader_seeds(who, farm.day)
		if who == "any":
			_text(v, ("Семена не по сезону, дороже на 50%%. Этот товар до %d-го дня сезона, потом будет другой." % Farm.universal_offer(farm.day)["until"]) if not offers.is_empty() else "Сегодня нечего предложить.", 15)
		elif offers.is_empty():
			_text(v, "Сейчас не сезон для посадки. Загляните к универсальному торговцу: у него бывают семена не по сезону.")
		for o in offers:
			var k: String = o[0]
			var cost: int = o[1]
			var c := Farm.crop(k)
			var info := "%s — %d мон. · %s · растёт %d дн." % [c["seed_name"], cost, Farm.seasons_ru(c.get("plant", c["seasons"])), c["grow"]]
			if c.get("regrow", 0) > 0:
				info += ", потом урожай каждые %d дн." % c["regrow"]
			var h := _item_row(v, "seed_" + k, info)
			var b1 := _button(h, "+1", func() -> void: main.farmnet.request("buy", [who, k, 1]))
			var b5 := _button(h, "+5 за %d" % (cost * 5), func() -> void: main.farmnet.request("buy", [who, k, 5]))
			b1.disabled = farm.money < cost
			b5.disabled = farm.money < cost * 5
	_button(_buttons(v), "Уйти", close_dialog)


func _trend_text(day: int, k: String) -> String:
	match Farm.trend(day, k):
		"up":
			return "(сегодня дорого)"
		"down":
			return "(сегодня дёшево)"
	return ""


## Строка списка: картинка, текст и место для кнопок справа.
func _item_row(v: Control, icon_name: String, text: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var icon := TextureRect.new()
	icon.texture = _icon(icon_name)
	icon.custom_minimum_size = Vector2(32, 32)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	h.add_child(icon)
	var l := _text(h, text, 15)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h


func open_inventory() -> void:
	if is_busy():
		return
	var v := _open("inventory", "Инвентарь", 700)
	_text(v, "Монеты (общие): %d. Перетащите предмет в другую ячейку или за край окна — выбросить на землю. Долгое нажатие — меню." % main.farmnet.farm.money, 14)
	# одежда: слоты есть, сами вещи появятся позже
	var eq := HBoxContainer.new()
	eq.add_theme_constant_override("separation", 8)
	v.add_child(eq)
	_text(eq, "Одежда:", 14)
	for slot_name in ["Голова", "Тело", "Штаны", "Обувь"]:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", _box(Color("#26304e"), Color("#5a6890")))
		var l := _text(p, "%s\nпусто" % slot_name, 12)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		p.custom_minimum_size = Vector2(84, 0)
		eq.add_child(p)
	var grid := GridContainer.new()
	grid.name = "Grid"
	grid.columns = Farm.ROW
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	_fill_inventory_grid()
	_button(_buttons(v), "Закрыть", close_dialog)


func _fill_inventory_grid() -> void:
	var grid: Node = dialog.find_child("Grid", true, false) if dialog else null
	if grid == null:
		return
	for c in grid.get_children():
		c.queue_free()
	for i in Farm.ROW * Farm.ROWS:
		grid.add_child(_slot_button(i))


## Огород изменился (деньги, семена, урожай): обновить открытое окно.
func refresh_farm() -> void:
	if dialog_kind == "ship":
		open_ship()
	elif dialog_kind == "trader":
		open_trader(_trader)
	elif dialog_kind == "inventory":
		_fill_inventory_grid()


# ---------- оформление ----------

func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func _outlined_label(size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func _box(bg: Color, border: Color, width := 1) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(width)
	b.set_corner_radius_all(5)
	b.content_margin_left = 12
	b.content_margin_right = 12
	b.content_margin_top = 6
	b.content_margin_bottom = 6
	return b


## Синие панели с золотой рамкой — как в браузерной версии.
func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.11, 0.15, 0.29, 0.92)
	panel.border_color = Color("#d9b45a")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(12)
	th.set_stylebox("panel", "PanelContainer", panel)
	th.set_stylebox("normal", "Button", _box(Color("#2c4a86"), Color("#d9b45a")))
	th.set_stylebox("hover", "Button", _box(Color("#3a5fa6"), Color("#f0cf7a")))
	th.set_stylebox("pressed", "Button", _box(Color("#1f3563"), Color("#f0cf7a")))
	th.set_stylebox("disabled", "Button", _box(Color("#2a3348"), Color("#5a6070")))
	th.set_color("font_color", "Button", Color("#f4e6c0"))
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_color", "Label", Color("#f4e6c0"))
	return th


## Ячейка инвентаря: тап — взять в руки, перетаскивание — переложить, долгое нажатие — меню.
class SlotButton extends Button:
	const FarmScript := preload("res://scripts/farm.gd")
	var hud: Node
	var index := 0
	var _down_t := -1.0
	var _down_pos := Vector2.ZERO

	func _get_drag_data(_pos: Vector2) -> Variant:
		var inv: Array = hud.main.farmnet.my_inv
		if index >= inv.size() or inv[index] == null:
			return null
		_down_t = -1.0
		var preview := TextureRect.new()
		preview.texture = hud._icon(FarmScript.item_info(inv[index]["id"])["icon"])
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.size = Vector2(48, 48)
		set_drag_preview(preview)
		return {"slot": index}

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return data is Dictionary and data.has("slot") and index < FarmScript.INV_SIZE

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		hud.main.farmnet.request("move", [data["slot"], index])

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton:
			if e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
				hud.open_item_menu(index)
				accept_event()
			elif e.button_index == MOUSE_BUTTON_LEFT:
				if e.pressed:
					_down_t = 0.0
					_down_pos = e.position
				else:
					_down_t = -1.0
		elif e is InputEventMouseMotion and _down_t >= 0.0 and e.position.distance_to(_down_pos) > 10.0:
			_down_t = -1.0

	func _process(delta: float) -> void:
		if _down_t >= 0.0:
			_down_t += delta
			if _down_t > 0.55:
				_down_t = -1.0
				hud.open_item_menu(index)


## Затемнение вокруг окна: предмет, брошенный сюда из инвентаря, падает на землю.
class DropZone extends ColorRect:
	var hud: Node

	func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
		return hud.dialog_kind == "inventory" and data is Dictionary and data.has("slot")

	func _drop_data(_pos: Vector2, data: Variant) -> void:
		hud.drop_slot(data["slot"])


## Стрелка переключения ряда панели.
class ArrowButton extends Button:
	var up := true

	func _draw() -> void:
		var c := size / 2.0
		var w := size.x * 0.28
		var h := size.y * 0.2
		var k := -1.0 if up else 1.0
		var pts := PackedVector2Array([c + Vector2(0, h * k), c + Vector2(w, -h * k), c + Vector2(-w, -h * k)])
		draw_colored_polygon(pts, Color("#f4e6c0"))
