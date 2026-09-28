class_name Wind
extends Node
## Global wind: slowly wandering direction with gusts. Feeds the shader
## globals used by grass, trees, cloth, particles and clouds. The "Guiding
## Wind" temporarily bends everything towards an objective.

var direction := Vector2(0.93, 0.37).normalized()
var strength := 1.0
var base_strength := 1.0
var phase := 0.0
var _t := 0.0
var _guide_dir := Vector2.ZERO
var _guide_left := 0.0
var _guide_total := 0.0
var weather_boost := 0.0
var noise := FastNoiseLite.new()


func _ready() -> void:
	noise.seed = 77
	noise.frequency = 0.05


func guide_towards(dir: Vector2, duration := 7.0) -> void:
	if dir.length() < 0.01:
		return
	_guide_dir = dir.normalized()
	_guide_left = duration
	_guide_total = duration


func is_guiding() -> bool:
	return _guide_left > 0.0


func _process(delta: float) -> void:
	_t += delta
	var wander := noise.get_noise_1d(_t * 0.15) * 1.2
	var base_dir := Vector2(0.93, 0.37).rotated(wander).normalized()
	var gust := 0.5 + 0.5 * noise.get_noise_1d(_t * 1.3 + 100.0)
	gust = pow(gust, 2.0)
	var target_strength := base_strength * (0.7 + gust * 0.9) + weather_boost
	var guide := 0.0
	if _guide_left > 0.0:
		_guide_left -= delta
		var k := clampf(_guide_left / _guide_total, 0.0, 1.0)
		guide = smoothstep(0.0, 0.15, 1.0 - k) * smoothstep(0.0, 0.3, k)
		base_dir = base_dir.lerp(_guide_dir, clampf(guide * 1.5, 0.0, 1.0)).normalized()
		target_strength = lerpf(target_strength, 2.4, guide)
	direction = direction.lerp(base_dir, clampf(delta * 1.5, 0.0, 1.0)).normalized()
	strength = lerpf(strength, target_strength, clampf(delta * 2.0, 0.0, 1.0))
	phase += delta * (0.6 + strength)
	RenderingServer.global_shader_parameter_set("wind_dir", direction)
	RenderingServer.global_shader_parameter_set("wind_strength", strength)
	RenderingServer.global_shader_parameter_set("wind_time", phase)
	RenderingServer.global_shader_parameter_set("guide_wind", guide)


func vector3(scale := 1.0) -> Vector3:
	return Vector3(direction.x, 0.0, direction.y) * strength * scale
