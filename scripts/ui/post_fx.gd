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
	Game.screen_flash.connect(func(c: Color, amount: float) -> void:
		flash_color = Color(c.r, c.g, c.b, maxf(flash_color.a, amount)))
	Game.lens_splash.connect(func(amount: float, color: Color) -> void:
		lens_blood = clampf(lens_blood + amount, 0.0, 1.2)
		lens_tint = color)
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
	kurosawa = move_toward(kurosawa, 1.0 if kurosawa_on else 0.0, real * 2.0)
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
