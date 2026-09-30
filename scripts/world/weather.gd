class_name Weather
extends Node
## Weather state machine (clear, windy, cloudy, fog, rain, storm) blending
## smoothly between parameter sets. Rain wets the ground (global `wetness`).

signal changed(state: String)
signal lightning_flash(strength: float)

const STATES := {
	"clear": {"cover": 0.46, "storm": 0.0, "fog": 0.0, "rain": 0.0, "wind": 0.0, "weight": 5.0},
	"windy": {"cover": 0.52, "storm": 0.0, "fog": 0.0, "rain": 0.0, "wind": 0.9, "weight": 3.0},
	"cloudy": {"cover": 0.66, "storm": 0.18, "fog": 0.1, "rain": 0.0, "wind": 0.3, "weight": 2.0},
	"fog": {"cover": 0.55, "storm": 0.1, "fog": 0.9, "rain": 0.0, "wind": 0.0, "weight": 1.3},
	"rain": {"cover": 0.85, "storm": 0.55, "fog": 0.25, "rain": 0.7, "wind": 0.6, "weight": 1.5},
	"storm": {"cover": 0.97, "storm": 0.9, "fog": 0.3, "rain": 1.0, "wind": 1.3, "weight": 0.6},
}

var state := "clear"
var cover := 0.46
var storm := 0.0
var fog := 0.0
var rain := 0.0
var wind_boost := 0.0
var wetness := 0.0
var lightning := 0.0
var sky_mat: ShaderMaterial
var wind: Wind
var auto_change := true
var _timer := 240.0
var _flash_timer := 8.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


func set_state(s: String, instant := false) -> void:
	if not STATES.has(s):
		return
	state = s
	_timer = _rng.randf_range(180.0, 420.0)
	if instant:
		var p: Dictionary = STATES[s]
		cover = p.cover
		storm = p.storm
		fog = p.fog
		rain = p.rain
		wind_boost = p.wind
	changed.emit(s)


func _pick_next() -> String:
	var total := 0.0
	for k in STATES:
		total += float(STATES[k].weight)
	var r := _rng.randf() * total
	for k in STATES:
		r -= float(STATES[k].weight)
		if r <= 0.0:
			return k
	return "clear"


func _process(delta: float) -> void:
	if auto_change:
		_timer -= delta
		if _timer <= 0.0:
			set_state(_pick_next())
	var p: Dictionary = STATES[state]
	var k := clampf(delta * 0.04, 0.0, 1.0)
	cover = lerpf(cover, p.cover, k)
	storm = lerpf(storm, p.storm, k)
	fog = lerpf(fog, p.fog, k)
	rain = lerpf(rain, p.rain, k * 1.5)
	wind_boost = lerpf(wind_boost, p.wind, k)
	if rain > 0.1:
		wetness = minf(1.0, wetness + delta * 0.03 * rain)
	else:
		wetness = maxf(0.0, wetness - delta * 0.006)
	if storm > 0.75:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash_timer = _rng.randf_range(6.0, 20.0)
			lightning = 1.0
			lightning_flash.emit(_rng.randf_range(0.6, 1.0))
	lightning = maxf(0.0, lightning - delta * 3.5)
	var flicker := lightning * (0.6 + 0.4 * sin(Time.get_ticks_msec() * 0.05))
	if sky_mat:
		sky_mat.set_shader_parameter("cloud_coverage", cover)
		sky_mat.set_shader_parameter("lightning", flicker)
	if wind:
		wind.weather_boost = wind_boost
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("rain_amount", rain)
