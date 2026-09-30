class_name PostFX
extends CanvasLayer
## Screen-space grade driven by gameplay: hits pulse chromatic aberration,
## damage flashes red, low health drains colour, perfect dodges/parries and
## kill cams add focus, and F3 toggles the black & white Kurosawa mode.

var rect: ColorRect
var mat: ShaderMaterial
var damage := 0.0
var aberration := 0.0
var focus := 0.0
var kurosawa := 0.0
var kurosawa_on := false
var fade := 0.0
var fade_target := 0.0
var fade_speed := 2.0
var letterbox := 0.0
var letterbox_target := 0.0
var lens_blood := 0.0
var lens_tint := Color(0.5, 0.02, 0.02)
var lens_rain := 0.0
var flash_color := Color(1, 1, 1, 0)
var _pulse_left := 0.0
# combat juice
var _blur := 0.0
var _blur_peak := 0.0
var _blur_time := 0.0
var _blur_total := 0.1
var _blur_world := Vector3.ZERO
var _cut := 0.0
var _cut_total := 0.3
var _cut_world := Vector3.ZERO
var _cut_angle := 0.0
var _speed := 0.0


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/post_fx.gdshader")
	rect.material = mat
	add_child(rect)
	Game.player_damaged.connect(func(amount: float, _d: Vector3) -> void:
		damage = clampf(damage + 0.35 + amount / 60.0, 0.0, 1.0)
		aberration = maxf(aberration, 0.012))
	Game.shake_requested.connect(func(t: float) -> void: aberration = maxf(aberration, t * 0.018))
	Game.kurosawa_pulse.connect(func(d: float) -> void: _pulse_left = d)
	Game.screen_flash.connect(func(c: Color, amount: float) -> void:
		flash_color = Color(c.r, c.g, c.b, maxf(flash_color.a, amount)))
	Game.lens_splash.connect(func(amount: float, color: Color) -> void:
		lens_blood = clampf(lens_blood + amount, 0.0, 1.2)
		lens_tint = color)
	Game.radial_blur.connect(func(strength: float, world_pos: Vector3, duration: float) -> void:
		if strength >= _blur:
			_blur_peak = strength
			_blur = strength
			_blur_time = 0.0
			_blur_total = maxf(duration, 0.04)
			_blur_world = world_pos)
	Game.slash_line.connect(func(world_pos: Vector3, world_dir: Vector3, duration: float) -> void:
		_cut = 1.0
		_cut_total = maxf(duration, 0.08)
		_cut_world = world_pos
		# the cut follows the blow as it looks on screen
		var a := _screen_uv(world_pos)
		var b := _screen_uv(world_pos + world_dir.normalized())
		var size := get_viewport().get_visible_rect().size
		var v := Vector2((b.x - a.x) * size.x / size.y, b.y - a.y)
		_cut_angle = atan2(v.y, v.x) if v.length() > 0.001 else 0.6)
	kurosawa_on = bool(Settings.get_value("kurosawa", false))


func pulse_focus(amount := 1.0) -> void:
	focus = maxf(focus, amount)


func fade_to(target: float, speed := 2.0, color := Color.BLACK) -> void:
	fade_target = target
	fade_speed = speed
	mat.set_shader_parameter("fade_color", color)


func set_letterbox(on: bool) -> void:
	letterbox_target = 1.0 if on else 0.0


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("kurosawa"):
		kurosawa_on = not kurosawa_on
		Settings.set_value("kurosawa", kurosawa_on)
		Game.show_toast("Modo Kurosawa " + ("ativado" if kurosawa_on else "desativado"))


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.02)
	damage = maxf(0.0, damage - real * 1.4)
	aberration = maxf(0.0, aberration - real * 0.05)
	focus = maxf(0.0, focus - real * 0.9)
	if Engine.time_scale < 0.6:
		focus = maxf(focus, (0.6 - Engine.time_scale) * 1.6)
	_pulse_left = maxf(0.0, _pulse_left - real)
	kurosawa = move_toward(kurosawa, 1.0 if (kurosawa_on or _pulse_left > 0.0) else 0.0, real * 6.0)
	fade = move_toward(fade, fade_target, real * fade_speed)
	letterbox = move_toward(letterbox, letterbox_target, real * 2.5)
	var low := 0.0
	var p := Game.get_player()
	if p and not p.dead:
		low = clampf(1.0 - p.health / (p.max_health * 0.35), 0.0, 1.0)
	elif p and p.dead:
		low = 1.0
	lens_blood = maxf(0.0, lens_blood - real * 0.16)
	var world := Game.world as World
	var rain_target := 0.0
	if world and world.weather:
		rain_target = world.weather.rain
	lens_rain = lerpf(lens_rain, rain_target * 0.55, clampf(real * 0.5, 0.0, 1.0))
	flash_color.a = maxf(0.0, flash_color.a - real * 4.5)
	_update_juice(real)
	mat.set_shader_parameter("flash_color", flash_color)
	mat.set_shader_parameter("lens_blood", lens_blood)
	mat.set_shader_parameter("lens_tint", Vector3(lens_tint.r, lens_tint.g, lens_tint.b))
	mat.set_shader_parameter("lens_rain", lens_rain)
	mat.set_shader_parameter("damage", damage)
	mat.set_shader_parameter("aberration", aberration)
	mat.set_shader_parameter("focus", minf(focus, 1.0))
	mat.set_shader_parameter("kurosawa", kurosawa)
	mat.set_shader_parameter("low_health", low)
	mat.set_shader_parameter("fade", fade)
	mat.set_shader_parameter("letterbox", letterbox)
	mat.set_shader_parameter("grain", 0.022 + low * 0.03)


## Screen position (uv) of a world point; the centre of the screen when it is behind the camera.
func _screen_uv(world: Vector3) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null or cam.is_position_behind(world):
		return Vector2(0.5, 0.5)
	var size := get_viewport().get_visible_rect().size
	var p := cam.unproject_position(world)
	return Vector2(clampf(p.x / size.x, -0.2, 1.2), clampf(p.y / size.y, -0.2, 1.2))


func _update_juice(real: float) -> void:
	# zoom blur: a hard snap that eases out
	if _blur > 0.0:
		_blur_time += real
		var k := clampf(_blur_time / _blur_total, 0.0, 1.0)
		_blur = _blur_peak * (1.0 - k) * (1.0 - k)
		if k >= 1.0:
			_blur = 0.0
	# fast movement: a little blur and streaks around the edges
	_speed = lerpf(_speed, Game.speed_fx, clampf(real * 6.0, 0.0, 1.0))
	var blur_total := _blur + _speed * 0.018
	mat.set_shader_parameter("radial_blur", blur_total * float(Settings.get_value("motion_blur", 1.0)))
	var centre := _screen_uv(_blur_world) if _blur > 0.0 else Vector2(0.5, 0.5)
	mat.set_shader_parameter("radial_center", centre)
	mat.set_shader_parameter("speed_lines", _speed * float(Settings.get_value("motion_blur", 1.0)))
	# the cut across the screen
	if _cut > 0.0:
		_cut = maxf(0.0, _cut - real / _cut_total)
	var c := _screen_uv(_cut_world)
	mat.set_shader_parameter("slash_line", Vector4(c.x, c.y, _cut_angle, _cut))
