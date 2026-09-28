class_name TimeOfDay
extends Node
## Drives the sun, the moon, the sky shader, fog and exposure from the time
## of day. Colour palettes are keyed on sun elevation so dawn and dusk match.

signal hour_changed(hour: int)

var time := 16.9
var day_minutes := 36.0
var paused := false
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var weather: Weather
var _last_hour := -1

const SUN_NOON := Color(1.0, 0.95, 0.88)
const SUN_GOLD := Color(1.0, 0.72, 0.43)
const SUN_HORIZON := Color(1.0, 0.44, 0.2)
const MOON_COL := Color(0.58, 0.68, 0.95)
const FOG_DAY := Color(0.72, 0.78, 0.86)
const FOG_GOLD := Color(0.98, 0.74, 0.52)
const FOG_NIGHT := Color(0.07, 0.09, 0.15)


func setup(p_sun: DirectionalLight3D, p_moon: DirectionalLight3D, p_env: Environment, p_sky: ShaderMaterial) -> void:
	sun = p_sun
	moon = p_moon
	env = p_env
	sky_mat = p_sky
	day_minutes = float(Settings.get_value("day_length_minutes", 36.0))
	apply()


func sun_direction(t: float) -> Vector3:
	var a := (t - 6.0) / 12.0 * PI
	return Vector3(cos(a), sin(a) * 0.92, 0.45).normalized()


func moon_direction(t: float) -> Vector3:
	var a := (t - 18.0) / 12.0 * PI
	return Vector3(cos(a) * 0.9, sin(a) * 0.8 + 0.12, -0.35).normalized()


func is_night() -> bool:
	return sun_direction(time).y < -0.05


func daylight() -> float:
	return smoothstep(-0.1, 0.2, sun_direction(time).y)


func _process(delta: float) -> void:
	if not paused and day_minutes > 0.0:
		time = fmod(time + delta * 24.0 / (day_minutes * 60.0), 24.0)
	apply()
	var h := int(time)
	if h != _last_hour:
		_last_hour = h
		hour_changed.emit(h)


func apply() -> void:
	if sun == null:
		return
	var sd := sun_direction(time)
	var md := moon_direction(time)
	var elev := sd.y
	var day := smoothstep(-0.1, 0.2, elev)
	var golden := 1.0 - smoothstep(0.06, 0.5, elev)
	var horizon := 1.0 - smoothstep(-0.02, 0.14, elev)
	var storm := weather.storm if weather else 0.0
	var fog_extra := weather.fog if weather else 0.0

	# --- sun ------------------------------------------------------------------
	sun.basis = Basis.looking_at(-sd, Vector3.UP if absf(sd.y) < 0.99 else Vector3.FORWARD)
	var sc := SUN_NOON.lerp(SUN_GOLD, golden).lerp(SUN_HORIZON, horizon)
	sun.light_color = sc
	var sun_e := smoothstep(-0.03, 0.1, elev) * lerpf(1.35, 2.1, smoothstep(0.1, 0.8, elev))
	sun_e *= lerpf(1.0, 0.28, storm)
	sun.light_energy = sun_e
	sun.visible = sun_e > 0.005
	sun.shadow_enabled = sun_e > 0.02

	# --- moon -----------------------------------------------------------------
	var night := 1.0 - smoothstep(-0.2, 0.02, elev)
	moon.basis = Basis.looking_at(-md, Vector3.UP if absf(md.y) < 0.99 else Vector3.FORWARD)
	moon.light_color = MOON_COL
	moon.light_energy = night * smoothstep(0.0, 0.2, md.y) * 0.42 * lerpf(1.0, 0.4, storm)
	moon.visible = moon.light_energy > 0.005
	moon.shadow_enabled = moon.visible and not sun.visible

	# --- environment ----------------------------------------------------------
	var fog_col := FOG_NIGHT.lerp(FOG_DAY, day).lerp(FOG_GOLD, golden * day * 0.8)
	fog_col = fog_col.lerp(Color(0.45, 0.48, 0.52) * (0.3 + 0.7 * day), storm * 0.8)
	env.fog_light_color = fog_col
	env.fog_density = lerpf(0.00022, 0.00042, golden) + fog_extra * 0.003 + storm * 0.0009
	env.fog_sun_scatter = lerpf(0.05, 0.35, golden) * day
	env.ambient_light_energy = lerpf(0.55, 1.0, day)
	env.tonemap_exposure = lerpf(1.9, 1.0, day) * lerpf(1.0, 1.15, storm)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = lerpf(0.0012, 0.0032, golden) + fog_extra * 0.025 + storm * 0.004
		env.volumetric_fog_albedo = fog_col.lerp(Color.WHITE, 0.5)
		env.volumetric_fog_anisotropy = lerpf(0.35, 0.72, golden)
	if sky_mat:
		sky_mat.set_shader_parameter("sky_energy", lerpf(0.6, 1.0, day))
		sky_mat.set_shader_parameter("storm", storm)

	RenderingServer.global_shader_parameter_set("sun_dir", sd if sun.visible else md)
	RenderingServer.global_shader_parameter_set("sun_color", sc * sun_e if sun.visible else MOON_COL * moon.light_energy)
	RenderingServer.global_shader_parameter_set("fog_color", fog_col)
	RenderingServer.global_shader_parameter_set("ambient_color", fog_col.lerp(Color(0.4, 0.5, 0.7), 0.5) * lerpf(0.25, 1.0, day))
