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
	mat.set_shader_parameter("damage", damage)
	mat.set_shader_parameter("aberration", aberration)
	mat.set_shader_parameter("focus", minf(focus, 1.0))
	mat.set_shader_parameter("kurosawa", kurosawa)
	mat.set_shader_parameter("low_health", low)
	mat.set_shader_parameter("fade", fade)
	mat.set_shader_parameter("letterbox", letterbox)
	mat.set_shader_parameter("grain", 0.022 + low * 0.03)
