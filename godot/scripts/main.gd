extends Node3D
## Проба RO-стиля: огород в 3D, Тёма — спрайт, камера вращается вокруг него, можно играть вдвоём по сети.
## Всё создаётся из кода при запуске, поэтому сцена main.tscn почти пустая.

const Location := preload("res://scripts/location.gd")
const Atlas := preload("res://scripts/atlas.gd")
const World := preload("res://scripts/world.gd")
const Avatar := preload("res://scripts/avatar.gd")
const Hud := preload("res://scripts/hud.gd")
const FarmNet := preload("res://scripts/farm_net.gd")
const Sfx := preload("res://scripts/sfx.gd")

const PORT := 24565
const SPEED := 3.6          # клеток в секунду
const RADIUS := 0.28        # «толщина» персонажа для столкновений
const PITCH := 0.87         # наклон камеры, около 50 градусов
const ZOOM_MIN := 8.0
const ZOOM_MAX := 30.0
const GAME_MIN_PER_SEC := 4.0
const FAST := 25

var atlas: Atlas
var map: Location
var world: World
var hud: Hud
var farmnet: FarmNet
var sound: Sfx
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var cursor: MeshInstance3D
var me: Avatar
var remotes := {}            # id игрока в сети -> Avatar
var astar := AStarGrid2D.new()
var path: Array[Vector3] = []
## Где сейчас этот игрок: огород, перекрёсток, рынок, речка, лес.
var loc_id := "farm"
## Переход между локациями: куда идём и как далеко зашло затемнение (0..1..0).
var _travel: Variant = null
var _fade := 0.0
## Клетка, с которой надо что-то сделать, когда дойдём до неё.
var pending_act: Variant = null

var day := 1
var minutes := 7.0 * 60.0
var fast := false
var time_frozen := false
var _save_t := 0.0
var _last_cell := Vector2i(-1, -1)
var _trod_sent := {}
var _snowfall: CPUParticles3D
var _late_warned := false
var yaw := 0.0
var dist := 18.0
var cam_target := Vector3.ZERO

var net_status := ""
var _net_t := 0.0
var _clock_t := 0.0
var _tint_t := 0.0
var _press_pos := Vector2.ZERO
var _pressing := false
var _dragging := false
var _touches := {}
var _pinch := 0.0


func _ready() -> void:
	atlas = Atlas.new()
	map = Location.get_loc(loc_id)
	world = World.new()
	add_child(world)
	world.setup(atlas, map)
	_make_environment()
	_make_cursor()
	_make_astar()

	farmnet = FarmNet.new()
	farmnet.setup(self)
	add_child(farmnet)
	sound = Sfx.new()
	add_child(sound)

	me = Avatar.new()
	add_child(me)
	me.setup(atlas, false, "Тёма")
	me.position = spawn_point()
	cam_target = me.position

	cam = Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.5
	cam.far = 250.0
	add_child(cam)
	cam.make_current()

	world.build(day, farmnet.farm, map, market_open())
	hud = Hud.new()
	add_child(hud)
	hud.setup(self)
	net_status = "Можно играть одному. Чтобы играть вдвоём: один создаёт игру, второй вводит его адрес."

	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_update_camera(1.0)
	_update_light(true)
	_update_snowfall()
	if not farmnet.load_game():
		hud.call_deferred("open_intro")
	else:
		hud.toast("С возвращением! День %d." % day)


func _process(delta: float) -> void:
	minutes += delta * GAME_MIN_PER_SEC * time_speed()
	if minutes >= 23.0 * 60.0 and not _late_warned:
		_late_warned = true
		hud.toast("Уже 23:00. Пора домой спать." if loc_id == "farm" else "Уже 23:00. Пора возвращаться домой.")
	if minutes >= 24.0 * 60.0:
		# в полночь день кончается сам; новый день объявляет хозяин игры
		minutes = 24.0 * 60.0 - 0.01
		if farmnet.is_host():
			farmnet.end_day("Наступила полночь — все уснули прямо там, где были.")
	if _travel != null:
		_update_travel(delta)
	elif hud.is_busy():
		me.moving = false
	else:
		_move(delta)
	farmnet.tick(delta)
	me.tick(delta, yaw)
	for r in remotes.values():
		r.tick(delta, yaw)
	_rotate_keys(delta)
	_update_camera(delta)
	_tint_t += delta
	_update_light(_tint_t > 0.25)
	world.set_market_open(market_open())
	world.tick(delta)
	_net_tick(delta)
	hud.refresh()
	_save_t += delta
	if _save_t >= 20.0:
		_save_t = 0.0
		farmnet.save_game()


# ---------- дни и время ----------

func season_text() -> String:
	return Location.season_name(day)


func time_speed() -> int:
	return 0 if time_frozen else (FAST if fast else 1)


func toggle_fast() -> void:
	fast = not fast


## Админ-панель: сразу перейти на день d (без ночи: ничего не растёт и не вянет).
func admin_set_day(d: int) -> void:
	if not farmnet.is_host():
		return
	d = maxi(1, d)
	var snow := farmnet.farm.snow if Location.season_id(d) == "winter" else false
	farmnet._all("net_set_day", [d, snow])


func admin_set_time(m: float) -> void:
	if not farmnet.is_host():
		return
	minutes = m
	_late_warned = m >= 23.0 * 60.0
	_send_clock()


## Сохраниться перед закрытием игры (и когда телефон сворачивает приложение).
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if farmnet:
			farmnet.save_game()


## После игры у друга: свой мир из своего сохранения (или новый, если сохранения нет).
func load_own_world() -> void:
	farmnet.farm = FarmNet.Farm.new()
	farmnet.my_inv = FarmNet.Farm.new_inventory()
	farmnet.farm.inv = {1: farmnet.my_inv}
	farmnet.my_water = FarmNet.Farm.CAN_CAP
	Location._cache.clear()
	if not farmnet.load_game():
		day = 1
		minutes = 360.0
		enter_location("farm")
	hud.refresh_farm()


## Начать игру заново: новый огород, нетронутые карты, стартовые инвентари.
func restart_game() -> void:
	if not farmnet.is_host():
		return
	farmnet.restart()
	_late_warned = false


## Кнопка «+ день» для проверки: ночь проходит сразу, растения растут.
func skip_day() -> void:
	if farmnet.is_host():
		farmnet.end_day("")


func set_day(d: int) -> void:
	day = d
	_trod_sent.clear()
	world.build(day, farmnet.farm, map, market_open())
	_make_astar()
	_update_light(true)
	_update_snowfall()


func sfx(name_: String) -> void:
	sound.play(name_)


## Тёма ступил на новую клетку: зимой по свежему снегу остаются следы.
func _step_on(cell: Vector2i) -> void:
	if cell == _last_cell:
		return
	_last_cell = cell
	if not Location.snow_cover(day):
		return
	var k := "%s:%d,%d" % [loc_id, cell.x, cell.y]
	if _trod_sent.has(k) or farmnet.farm.snow_trod.get(loc_id, {}).has("%d,%d" % [cell.x, cell.y]):
		return
	_trod_sent[k] = true
	farmnet.request("trod", [loc_id, cell.x, cell.y])


## Падающий снег вокруг камеры в снежные дни.
func _update_snowfall() -> void:
	if _snowfall == null:
		_snowfall = CPUParticles3D.new()
		_snowfall.amount = 260
		_snowfall.lifetime = 4.0
		_snowfall.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		_snowfall.emission_box_extents = Vector3(16, 0.5, 16)
		_snowfall.direction = Vector3(0.15, -1, 0)
		_snowfall.spread = 8.0
		_snowfall.initial_velocity_min = 1.2
		_snowfall.initial_velocity_max = 2.0
		_snowfall.gravity = Vector3.ZERO
		var mesh := QuadMesh.new()
		mesh.size = Vector2(0.07, 0.07)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1, 1, 1, 0.9)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mesh.material = mat
		_snowfall.mesh = mesh
		add_child(_snowfall)
	_snowfall.emitting = Location.snowing(day)
	_snowfall.visible = _snowfall.emitting


## На клетке что-то изменилось (срубили дерево и т. п.): обновить картинку и проходимость.
func on_map_changed(x: int, y: int) -> void:
	world.update_cell(x, y)
	if Rect2i(0, 0, map.W, map.H).has_point(Vector2i(x, y)):
		astar.set_point_solid(Vector2i(x, y), not map.walkable(x, y))


## Рынок открыт с 8:00 до 18:00, кроме последнего дня сезона.
func market_open() -> bool:
	return Location.season_day(day) != Location.SEASON_DAYS and minutes >= 480.0 and minutes < 1080.0


# ---------- переходы между локациями ----------

## Тёма ступил на выход: экран темнеет, и он оказывается в соседней локации.
func _start_travel(to: String) -> void:
	if not Location.exists(to):
		hud.toast("Эта дорога пока никуда не ведёт.")
		return
	_travel = to
	_fade = 0.0
	path.clear()
	pending_act = null
	me.moving = false


func _update_travel(delta: float) -> void:
	var before := _fade
	_fade += delta * 4.0
	if before < 1.0 and _fade >= 1.0:
		enter_location(String(_travel), loc_id)
	if _fade >= 2.0:
		_fade = 0.0
		_travel = null
	hud.set_fade(1.0 - absf(_fade - 1.0) if _travel != null else 0.0)


## Перейти в локацию id (from — откуда пришли: встанем у выхода оттуда). Без from — на «Старт игрока».
func enter_location(id: String, from: String = "") -> void:
	loc_id = id
	map = Location.get_loc(id)
	map.season = Location.season_id(day)
	world.build(day, farmnet.farm, map, market_open())
	_make_astar()
	if from != "":
		var c := map.arrival(from)
		me.position = Vector3(c.x + 0.5, 0, c.y + 0.5)
	else:
		me.position = spawn_point()
	cam_target = me.position
	path.clear()
	pending_act = null
	_update_light(true)
	_update_snowfall()
	_refresh_remotes()
	hud.toast(map.title)


## Утро: все просыпаются у дома, растения подросли, ящик заплатил.
func on_new_day(morning: Dictionary, note: String) -> void:
	minutes = 6.0 * 60.0
	_late_warned = false
	day = farmnet.farm.day
	# утром все просыпаются дома
	_travel = null
	hud.set_fade(0.0)
	enter_location("farm")
	me.face = 0.0
	hud.show_morning(morning, note)


## Где игрок появляется утром: метка «Старт игрока» на карте.
func spawn_point() -> Vector3:
	var spawn: Variant = map.find("spawn")
	if spawn == null:
		return Vector3(map.W / 2.0, 0, map.H / 2.0)
	return Vector3(spawn["x"] + 0.5, 0, spawn["y"] + 0.6)


## Цвет дневного света по времени суток (тот же, что в браузерной версии).
const TINT := [[0, 70, 80, 140], [300, 80, 90, 150], [360, 255, 186, 150], [450, 255, 226, 198], [600, 255, 248, 238],
	[720, 255, 255, 255], [900, 255, 252, 244], [1080, 255, 224, 184], [1200, 242, 168, 128], [1260, 150, 128, 188],
	[1320, 96, 100, 166], [1440, 70, 80, 140]]


static func tint_at(m: float) -> Color:
	for i in range(1, TINT.size()):
		var c0: Array = TINT[i - 1]
		var c1: Array = TINT[i]
		if m <= c1[0]:
			var f: float = (m - c0[0]) / float(c1[0] - c0[0])
			return Color(lerpf(c0[1], c1[1], f) / 255.0, lerpf(c0[2], c1[2], f) / 255.0, lerpf(c0[3], c1[3], f) / 255.0)
	return Color(70 / 255.0, 80 / 255.0, 140 / 255.0)


func _make_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.fog_enabled = true
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 45.0
	add_child(sun)


## Солнце встаёт в 6:00 на востоке, в полдень стоит на юге, садится в 20:30 на западе.
func _update_light(sprites_too: bool) -> void:
	var tint := tint_at(minutes)
	var t := (minutes - 360.0) / 870.0
	if t > 0.0 and t < 1.0:
		var a := t * PI
		var elev := sin(a)
		var dir := Vector3(cos(a), maxf(elev, 0.18) * 1.3, 0.55).normalized()
		sun.basis = Basis.looking_at(-dir, Vector3.UP)
		sun.light_color = tint
		sun.light_energy = 0.15 * minf(1.0, elev * 3.0)
		sun.visible = true
	else:
		sun.visible = false
	env.ambient_light_color = tint
	env.ambient_light_energy = 0.4
	var sky := Color(0.55, 0.74, 0.93) * tint
	env.background_color = sky
	env.fog_light_color = sky
	if sprites_too:
		_tint_t = 0.0
		world.set_tint(tint)
		me.set_tint(tint)
		for r in remotes.values():
			r.set_tint(tint)


# ---------- камера ----------

func _update_camera(delta: float) -> void:
	if _snowfall:
		_snowfall.position = me.position + Vector3(0, 7, 0)
	var target := me.position + Vector3(0, 0.7, 0)
	cam_target = cam_target.lerp(target, 1.0 - exp(-8.0 * delta))
	var off := Vector3(sin(yaw) * cos(PITCH), sin(PITCH), cos(yaw) * cos(PITCH)) * dist
	cam.position = cam_target + off
	cam.look_at(cam_target, Vector3.UP)


func _rotate_keys(delta: float) -> void:
	if _typing():
		return
	if Input.is_key_pressed(KEY_Q):
		yaw -= 1.6 * delta
	if Input.is_key_pressed(KEY_E):
		yaw += 1.6 * delta


func _zoom(factor: float) -> void:
	dist = clampf(dist * factor, ZOOM_MIN, ZOOM_MAX)


# ---------- управление ----------

func _typing() -> bool:
	return get_viewport().gui_get_focus_owner() is LineEdit


## Пальцы на экране телефона: два пальца — приблизить или отдалить.
func _input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position
		else:
			_touches.erase(e.index)
		_pinch = 0.0
		if _touches.size() >= 2:
			_dragging = true
	elif e is InputEventScreenDrag:
		_touches[e.index] = e.position
		if _touches.size() == 2:
			var pts := _touches.values()
			var d: float = pts[0].distance_to(pts[1])
			if _pinch > 0.0 and d > 0.0:
				_zoom(_pinch / d)
			_pinch = d


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(0.9)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.1)
		elif e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT:
			if e.pressed:
				_pressing = true
				_dragging = false
				_press_pos = e.position
			else:
				if _pressing and not _dragging and e.button_index == MOUSE_BUTTON_LEFT:
					_tap(e.position)
				_pressing = false
	elif e is InputEventMouseMotion:
		_update_cursor(e.position)
		if _pressing and _touches.size() < 2:
			if not _dragging and e.position.distance_to(_press_pos) > 12.0:
				_dragging = true
			if _dragging:
				yaw -= e.relative.x * 0.008
	elif e is InputEventMagnifyGesture and _touches.size() < 2:
		_zoom(1.0 / e.factor)
	elif e is InputEventKey and e.pressed and not e.echo and not _typing() and not hud.is_busy():
		if e.keycode == KEY_SPACE:
			_act_front()
		elif e.keycode >= KEY_1 and e.keycode <= KEY_9:
			hud.select_slot(e.keycode - KEY_1)
		elif e.keycode == KEY_0:
			hud.select_slot(9)
		elif e.keycode == KEY_I or e.keycode == KEY_TAB:
			hud.open_inventory()
		elif e.keycode == KEY_H:
			hud.open_admin()


func _ground_point(screen: Vector2) -> Variant:
	var o := cam.project_ray_origin(screen)
	var n := cam.project_ray_normal(screen)
	if n.y > -0.01:
		return null
	return o + n * (-o.y / n.y)


## Тап или клик по земле. Если там есть что сделать (грядка, колодец, ящик…), подходим и делаем;
## иначе просто идём туда.
func _tap(screen: Vector2) -> void:
	if hud.is_busy():
		return
	var p: Variant = _ground_point(screen)
	if p == null:
		return
	var cell := Vector2i(floori(p.x), floori(p.z))
	var from := my_cell()
	pending_act = null
	if farmnet.is_target(cell):
		if cell == from or (absi(cell.x - from.x) + absi(cell.y - from.y) == 1):
			path.clear()
			_do_act(cell)
			return
		# ближайшая свободная клетка рядом с целью
		var best: Array[Vector2i] = []
		for n in [cell + Vector2i.UP, cell + Vector2i.DOWN, cell + Vector2i.LEFT, cell + Vector2i.RIGHT]:
			if not map.walkable(n.x, n.y):
				continue
			var cells := astar.get_id_path(from, n)
			if not cells.is_empty() and (best.is_empty() or cells.size() < best.size()):
				best = cells
		if best.is_empty():
			hud.toast("Туда не подойти.")
			return
		_follow(best, null)
		pending_act = cell
		return
	if not map.walkable(cell.x, cell.y):
		return
	_follow(astar.get_id_path(from, cell), Vector3(p.x, 0, p.z))


func _follow(cells: Array[Vector2i], end: Variant) -> void:
	path.clear()
	for i in range(1, cells.size()):
		path.append(Vector3(cells[i].x + 0.5, 0, cells[i].y + 0.5))
	if end != null:
		path.append(end)
	elif cells.size() == 1:
		path.append(Vector3(cells[0].x + 0.5, 0, cells[0].y + 0.5))


func my_cell() -> Vector2i:
	return Vector2i(floori(me.position.x), floori(me.position.z))


## Повернуться к клетке и сделать с ней то, что в руках.
func _do_act(cell: Vector2i) -> void:
	var d := Vector3(cell.x + 0.5, 0, cell.y + 0.5) - me.position
	if Vector2(d.x, d.z).length() > 0.05:
		me.face = atan2(d.x, d.z)
	farmnet.act(cell)


## Пробел: действие с клеткой, к которой Тёма повёрнут лицом.
func _act_front() -> void:
	var d := Vector2(sin(me.face), cos(me.face))
	var step := Vector2i(signi(roundi(d.x)) if absf(d.x) > absf(d.y) else 0, 0 if absf(d.x) > absf(d.y) else signi(roundi(d.y)))
	if step == Vector2i.ZERO:
		step = Vector2i(0, 1)
	_do_act(my_cell() + step)


func _move(delta: float) -> void:
	var dir := Vector3.ZERO
	if not _typing():
		var v := Vector2.ZERO
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			v.y += 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			v.y -= 1
		if v != Vector2.ZERO:
			path.clear()
			pending_act = null
			# «вперёд» — от камеры, как в играх с вращающейся камерой
			var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
			var right := Vector3(cos(yaw), 0, -sin(yaw))
			dir = (right * v.x + fwd * v.y).normalized()
	var step := SPEED * delta
	if dir == Vector3.ZERO and not path.is_empty():
		var to := path[0] - me.position
		to.y = 0
		if to.length() <= step:
			me.position = Vector3(path[0].x, 0, path[0].z)
			path.remove_at(0)
			me.moving = not path.is_empty()
			if path.is_empty() and pending_act != null:
				var cell: Vector2i = pending_act
				pending_act = null
				_do_act(cell)
			return
		dir = to.normalized()
	if dir == Vector3.ZERO:
		me.moving = false
		return
	me.face = atan2(dir.x, dir.z)
	me.moving = true
	var moved := false
	var p := me.position
	if _can_stand(Vector3(p.x + dir.x * step, 0, p.z)):
		p.x += dir.x * step
		moved = true
	if _can_stand(Vector3(p.x, 0, p.z + dir.z * step)):
		p.z += dir.z * step
		moved = true
	me.position = p
	_step_on(Vector2i(floori(p.x), floori(p.z)))
	var ex: Variant = map.exit_at(floori(p.x), floori(p.z))
	if ex != null and moved:
		_start_travel(String(ex.get("to", "")))
		return
	if not moved:
		path.clear()
		pending_act = null
		me.moving = false


func _can_stand(p: Vector3) -> bool:
	for c in [Vector2(-RADIUS, -RADIUS), Vector2(RADIUS, -RADIUS), Vector2(-RADIUS, RADIUS), Vector2(RADIUS, RADIUS)]:
		if not map.walkable(floori(p.x + c.x), floori(p.z + c.y)):
			return false
	return true


func _make_astar() -> void:
	astar.region = Rect2i(0, 0, map.W, map.H)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in map.H:
		for x in map.W:
			if not map.walkable(x, y):
				astar.set_point_solid(Vector2i(x, y), true)


## Рамка клетки под курсором — как в RO.
func _make_cursor() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for i in 16:
		for c in [Vector2i(i, 0), Vector2i(i, 15), Vector2i(0, i), Vector2i(15, i)]:
			img.set_pixelv(c, Color(1, 1, 1, 0.75))
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = ImageTexture.create_from_image(img)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE
	cursor = MeshInstance3D.new()
	cursor.mesh = mesh
	cursor.material_override = mat
	cursor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cursor.visible = false
	add_child(cursor)


func _update_cursor(screen: Vector2) -> void:
	var p: Variant = _ground_point(screen)
	if p == null:
		cursor.visible = false
		return
	var x := floori(p.x)
	var y := floori(p.z)
	cursor.visible = map.walkable(x, y)
	cursor.position = Vector3(x + 0.5, 0.03, y + 0.5)


# ---------- игра вдвоём ----------
# Один игрок создаёт игру (он «хозяин», у него Тёма), второй подключается по адресу (у него Друг в зелёной рубашке).
# Каждый сам ходит своим персонажем и 20 раз в секунду сообщает другому, где он. Время и день ведёт хозяин.

func net_mode() -> String:
	var peer := multiplayer.multiplayer_peer
	if peer == null or peer is OfflineMultiplayerPeer:
		return "off"
	return "host" if multiplayer.is_server() else "client"


func host_game() -> void:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, 3)
	if err != OK:
		net_status = "Не получилось создать игру (ошибка %d). Может быть, она уже создана в другом окне?" % err
		return
	multiplayer.multiplayer_peer = peer
	net_status = "Игра создана. Другу нужно ввести адрес: " + ", ".join(_local_addresses()) + "\nЖдём друга…"


func join_game(ip: String) -> void:
	if ip == "":
		ip = "127.0.0.1"
	# свой мир сохраняем: пока играем у друга, он не меняется, и после отключения вернёмся в него
	farmnet.save_game()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		net_status = "Не получилось подключиться (ошибка %d)." % err
		return
	multiplayer.multiplayer_peer = peer
	net_status = "Подключаемся к %s…" % ip


func leave_game() -> void:
	if net_mode() == "client":
		farmnet.on_lost_host()
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_remotes()
	me.set_look(false, "Тёма")
	net_status = "Вы играете одни."


func _local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a in IP.get_local_addresses():
		if a.contains(".") and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	if out.is_empty():
		out.append("127.0.0.1")
	return out


func _on_peer_connected(id: int) -> void:
	farmnet.on_peer_connected(id)
	if multiplayer.is_server():
		net_status = "Друг подключился! Адрес игры: " + ", ".join(_local_addresses())


func _on_peer_disconnected(id: int) -> void:
	farmnet.on_peer_disconnected(id)
	if remotes.has(id):
		remotes[id].queue_free()
		remotes.erase(id)
	if multiplayer.is_server():
		net_status = "Друг отключился. Ждём снова, адрес: " + ", ".join(_local_addresses())


func _on_connected() -> void:
	me.set_look(true, "Друг")
	net_status = "Подключено! Вы играете за Друга (зелёная рубашка)."


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	net_status = "Не удалось подключиться. Проверьте адрес и что оба устройства в одной сети Wi-Fi."


func _on_server_disconnected() -> void:
	farmnet.on_lost_host()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_clear_remotes()
	me.set_look(false, "Тёма")
	net_status = "Хозяин игры отключился. Вы играете одни."


func _clear_remotes() -> void:
	for r in remotes.values():
		r.queue_free()
	remotes.clear()


func _net_tick(delta: float) -> void:
	if net_mode() == "off" or multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	_net_t += delta
	if _net_t >= 0.05:
		_net_t = 0.0
		net_state.rpc(me.position, me.face, me.moving, loc_id)
	if multiplayer.is_server():
		_clock_t += delta
		if _clock_t >= 1.0:
			_clock_t = 0.0
			_send_clock()


func _send_clock() -> void:
	if net_mode() == "host":
		net_clock.rpc(day, minutes)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_state(pos: Vector3, p_face: float, p_moving: bool, p_loc: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if not remotes.has(id):
		var a := Avatar.new()
		add_child(a)
		a.setup(atlas, id != 1, "Тёма" if id == 1 else "Друг")
		a.remote = true
		a.position = pos
		a.set_tint(tint_at(minutes))
		remotes[id] = a
	var r: Avatar = remotes[id]
	if r.get_meta("loc", "") != p_loc:
		r.position = pos     # пришёл из другой локации — не тянем через всю карту
	r.set_meta("loc", p_loc)
	r.visible = p_loc == loc_id
	r.net_pos = pos
	r.face = p_face
	r.moving = p_moving


## Других игроков видно, только если они в той же локации.
func _refresh_remotes() -> void:
	for r in remotes.values():
		r.visible = r.get_meta("loc", "") == loc_id


@rpc("authority", "call_remote", "reliable")
func net_clock(_p_day: int, p_minutes: float) -> void:
	# день меняет только утро от хозяина (вместе с огородом), здесь — лишь часы
	minutes = p_minutes
