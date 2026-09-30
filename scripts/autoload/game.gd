extends Node
## Global game state, time effects (hit-stop / slow motion) and a signal hub
## used by gameplay systems to talk to the UI, camera and audio.

signal state_changed(state: int)
signal banner(title: String, subtitle: String, style: String)
signal toast(text: String)
signal player_damaged(amount: float, from_dir: Vector3)
signal enemy_killed(enemy: Node, info: Dictionary)
signal camp_cleared(camp_id: String)
signal location_discovered(poi: Dictionary)
signal detection_changed(enemy: Node, value: float)
signal shake_requested(trauma: float)
signal kill_cam_requested(target: Node3D, duration: float)
signal hud_visibility(visible: bool)
## Blood (or rain) landing on the camera lens; amount 0..1 and its colour.
signal lens_splash(amount: float, color: Color)
## Full-screen impact flash (parries, kills).
signal screen_flash(color: Color, amount: float)


## Black & white film flicker (Issen).
signal kurosawa_pulse(duration: float)
## The player landed a cut (power of the blow); the HUD counts combos.
signal combo_hit(power: float)
## Combat juice for the post-processing layer.
signal radial_blur(strength: float, world_pos: Vector3, duration: float)
signal slash_line(world_pos: Vector3, world_dir: Vector3, duration: float)
## A single hard black, white and red frame (deathblows, the last kill of a fight); duration in real seconds.
signal impact_frame(duration: float)


func flash(color: Color, amount := 0.5) -> void:
	screen_flash.emit(color, amount)

## 0..1, written every frame by the player: how fast the world should feel (speed streaks).
var speed_fx := 0.0

enum State { LOADING, TITLE, PLAYING, PAUSED, DEAD, CUTSCENE }

var state: int = State.LOADING
var player: Node3D = null
var world: Node3D = null
var camera_rig: Node3D = null
var hud: Node = null
var rng := RandomNumberGenerator.new()
var debug_mode := false
var auto_test := false

var _hitstop_left := 0.0
var _hitstop_scale := 1.0
var _slow_left := 0.0
var _slow_total := 0.0
var _slow_scale := 1.0
var _last_ticks := 0
var _paused_scale := 1.0


## The live player character, or null (never a freed instance).
func get_player() -> Player:
	if player == null or not is_instance_valid(player):
		return null
	return player as Player


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()
	_last_ticks = Time.get_ticks_usec()
	var args := OS.get_cmdline_user_args()
	debug_mode = args.has("--debug")
	auto_test = args.has("--autotest")


func set_state(s: int) -> void:
	if s == state:
		return
	state = s
	get_tree().paused = (s == State.PAUSED)
	state_changed.emit(s)


func is_playing() -> bool:
	return state == State.PLAYING


## Freezes the simulation for `duration` real seconds (impact frames).
func hitstop(duration: float, scale := 0.03) -> void:
	_hitstop_left = maxf(_hitstop_left, duration)
	_hitstop_scale = minf(scale, _hitstop_scale) if _hitstop_left > 0.0 else scale


## Slow motion that eases back to normal speed.
func slowmo(duration: float, scale := 0.3) -> void:
	if _slow_left > 0.0 and scale > _slow_scale:
		return
	_slow_left = duration
	_slow_total = duration
	_slow_scale = scale


func shake(trauma: float) -> void:
	shake_requested.emit(trauma * float(Settings.get_value("camera_shake", 1.0)))


func show_banner(title: String, subtitle := "", style := "default") -> void:
	banner.emit(title, subtitle, style)


func show_toast(text: String) -> void:
	toast.emit(text)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var real_dt := clampf((now - _last_ticks) / 1000000.0, 0.0, 0.1)
	_last_ticks = now
	var scale := 1.0
	if _slow_left > 0.0:
		_slow_left -= real_dt
		var t := 1.0 - clampf(_slow_left / maxf(_slow_total, 0.001), 0.0, 1.0)
		# hold the slow part, then ease out during the last 35%
		var k := smoothstep(0.65, 1.0, t)
		scale = lerpf(_slow_scale, 1.0, k)
	if _hitstop_left > 0.0:
		_hitstop_left -= real_dt
		scale = minf(scale, _hitstop_scale)
		if _hitstop_left <= 0.0:
			_hitstop_scale = 1.0
	if state == State.PAUSED:
		return
	Engine.time_scale = scale


func real_delta() -> float:
	return get_process_delta_time() / maxf(Engine.time_scale, 0.0001)
