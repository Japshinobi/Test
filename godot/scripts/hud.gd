extends CanvasLayer
## Интерфейс пробы: часы и дни (справа), игра вдвоём (слева), подсказка по управлению (снизу).

var main: Node
var clock: Label
var status: Label
var ip_edit: LineEdit
var host_btn: Button
var join_btn: Button
var leave_btn: Button
var net_box: VBoxContainer
var day_box: HBoxContainer
var fast_btn: Button


func setup(p_main: Node) -> void:
	main = p_main
	var root := Control.new()
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

	# часы и смена дней
	var right := _panel(root)
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.position += Vector2(-12, 12)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	clock = Label.new()
	clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(clock)
	day_box = HBoxContainer.new()
	rv.add_child(day_box)
	_button(day_box, "− день", func() -> void: main.shift_day(-1))
	_button(day_box, "+ день", func() -> void: main.shift_day(1))
	fast_btn = _button(day_box, "Время ×1", func() -> void: main.toggle_fast())

	# подсказка
	var hint := Label.new()
	hint.text = "Клик или тап — идти   ·   WASD — шагать   ·   тянуть или Q/E — повернуть камеру   ·   колесо или два пальца — приблизить"
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 6)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -46
	hint.offset_bottom = -10
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hint)
	refresh()


func refresh() -> void:
	var m := int(main.minutes)
	clock.text = "День %d · %s · %02d:%02d" % [main.day, main.season_text(), m / 60, m % 60]
	var net_state: String = main.net_mode()
	host_btn.visible = net_state == "off"
	join_btn.get_parent().visible = net_state == "off"
	leave_btn.visible = net_state != "off"
	day_box.visible = net_state != "client"
	fast_btn.text = "Время ×%d" % main.time_speed()
	status.text = main.net_status


func _panel(root: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(p)
	return p


func _button(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


## Синие панели с золотой рамкой — как в браузерной версии.
func _theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 18
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.11, 0.15, 0.29, 0.9)
	panel.border_color = Color("#d9b45a")
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(6)
	panel.set_content_margin_all(10)
	th.set_stylebox("panel", "PanelContainer", panel)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"normal": Color("#2c4a86"), "hover": Color("#3a5fa6"), "pressed": Color("#1f3563"), "disabled": Color("#2a3348")}[state]
		b.border_color = Color("#d9b45a")
		b.set_border_width_all(1)
		b.set_corner_radius_all(4)
		b.content_margin_left = 12
		b.content_margin_right = 12
		b.content_margin_top = 6
		b.content_margin_bottom = 6
		th.set_stylebox(state, "Button", b)
	th.set_color("font_color", "Button", Color("#f4e6c0"))
	th.set_color("font_hover_color", "Button", Color.WHITE)
	th.set_color("font_color", "Label", Color("#f4e6c0"))
	return th
