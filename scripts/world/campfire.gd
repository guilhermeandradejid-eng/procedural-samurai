class_name Campfire
extends Node3D
## A living camp fire: flickering light, additive flames, rising embers and
## smoke that drifts with the wind, plus a looping crackle.

var light: OmniLight3D
var flames: GPUParticles3D
var embers: GPUParticles3D
var smoke: GPUParticles3D
var intensity := 1.0
var _t := 0.0
var _noise := FastNoiseLite.new()
static var _flame_mat: StandardMaterial3D
static var _smoke_mat: StandardMaterial3D
static var _ember_mat: StandardMaterial3D


func _ready() -> void:
	_noise.frequency = 3.0
	_noise.seed = randi()
	light = OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.22)
	light.omni_range = 11.0
	light.omni_attenuation = 1.4
	light.light_energy = 2.6
	light.shadow_enabled = true
	light.light_volumetric_fog_energy = 0.6
	light.distance_fade_enabled = true
	light.distance_fade_begin = 70.0
	light.distance_fade_length = 20.0
	light.position = Vector3(0, 0.8, 0)
	add_child(light)
	_make_materials()
	flames = _particles(46, 0.75, _flame_mat, 0.55, _flame_process())
	embers = _particles(28, 2.6, _ember_mat, 0.05, _ember_process())
	smoke = _particles(18, 5.5, _smoke_mat, 1.1, _smoke_process())
	smoke.position.y = 0.9
	Audio.attach_loop("fire", self, -4.0, 28.0)


static func _make_materials() -> void:
	if _flame_mat:
		return
	_flame_mat = StandardMaterial3D.new()
	_flame_mat.albedo_texture = load("res://assets/textures/fx/smoke.png")
	_flame_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flame_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flame_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flame_mat.vertex_color_use_as_albedo = true
	_flame_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_flame_mat.albedo_color = Color(2.4, 1.2, 0.45)
	_flame_mat.disable_receive_shadows = true
	_smoke_mat = StandardMaterial3D.new()
	_smoke_mat.albedo_texture = load("res://assets/textures/fx/smoke.png")
	_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_smoke_mat.vertex_color_use_as_albedo = true
	_smoke_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_smoke_mat.albedo_color = Color(0.35, 0.33, 0.32, 0.55)
	_smoke_mat.disable_receive_shadows = true
	_ember_mat = StandardMaterial3D.new()
	_ember_mat.albedo_texture = load("res://assets/textures/fx/spark.png")
	_ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ember_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_ember_mat.albedo_color = Color(3.0, 1.3, 0.4)


func _particles(amount: int, lifetime: float, mat: Material, size: float, pm: ParticleProcessMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.randomness = 0.4
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-3, -1, -3), Vector3(6, 12, 6))
	p.position = Vector3(0, 0.15, 0)
	add_child(p)
	return p


func _flame_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.28
	m.direction = Vector3.UP
	m.spread = 12.0
	m.initial_velocity_min = 0.6
	m.initial_velocity_max = 1.3
	m.gravity = Vector3(0, 1.2, 0)
	m.damping_min = 0.5
	m.damping_max = 1.0
	m.scale_min = 0.6
	m.scale_max = 1.3
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.7))
	sc.add_point(Vector2(0.3, 1.0))
	sc.add_point(Vector2(1.0, 0.1))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.55, 0.9))
	g.set_color(1, Color(0.8, 0.12, 0.02, 0.0))
	g.add_point(0.35, Color(1.0, 0.55, 0.15, 0.8))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -90.0
	m.angular_velocity_max = 90.0
	return m


func _ember_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.3
	m.direction = Vector3.UP
	m.spread = 25.0
	m.initial_velocity_min = 1.2
	m.initial_velocity_max = 2.8
	m.gravity = Vector3(0, 0.4, 0)
	m.turbulence_enabled = true
	m.turbulence_noise_strength = 2.0
	m.turbulence_noise_scale = 2.5
	m.turbulence_influence_min = 0.1
	m.turbulence_influence_max = 0.3
	m.scale_min = 0.5
	m.scale_max = 1.2
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	g.set_color(1, Color(1.0, 0.2, 0.05, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	return m


func _smoke_process() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	m.emission_sphere_radius = 0.25
	m.direction = Vector3.UP
	m.spread = 10.0
	m.initial_velocity_min = 0.7
	m.initial_velocity_max = 1.1
	m.gravity = Vector3(0.35, 0.15, 0.1)
	m.scale_min = 0.8
	m.scale_max = 1.4
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 0.4))
	sc.add_point(Vector2(1.0, 3.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	m.scale_curve = sct
	var g := Gradient.new()
	g.set_color(0, Color(0.5, 0.45, 0.4, 0.0))
	g.set_color(1, Color(0.6, 0.6, 0.62, 0.0))
	g.add_point(0.2, Color(0.4, 0.38, 0.36, 0.45))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	m.color_ramp = gt
	m.angle_min = -180.0
	m.angle_max = 180.0
	m.angular_velocity_min = -20.0
	m.angular_velocity_max = 20.0
	return m


func _process(delta: float) -> void:
	_t += delta
	var n := _noise.get_noise_1d(_t * 1.0) * 0.5 + _noise.get_noise_1d(_t * 3.7 + 10.0) * 0.25
	light.light_energy = (2.4 + n * 1.3) * intensity
	light.position = Vector3(n * 0.06, 0.8 + n * 0.08, -n * 0.05)
	# smoke follows the wind
	var world := Game.world as World
	if world and world.wind:
		var wv := world.wind.vector3(0.6)
		(smoke.process_material as ParticleProcessMaterial).gravity = Vector3(wv.x, 0.15, wv.z)
