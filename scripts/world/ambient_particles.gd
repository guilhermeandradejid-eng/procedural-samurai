class_name AmbientParticles
extends Node3D
## Atmosphere that follows the camera: rain (collides with the terrain), wind
## blown maple/ginkgo leaves and sakura petals near those trees, golden
## motes over the pampas, fireflies on warm nights and snow up the volcano.
## Emission rates follow the local biome, time of day, weather and wind.

var rain: GPUParticles3D
var leaves := {}        # kind -> GPUParticles3D
var motes: GPUParticles3D
var fireflies: GPUParticles3D
var snow: GPUParticles3D
var _timer := 0.0
var _species := {"maple": 0.0, "ginkgo": 0.0, "sakura": 0.0}


func _ready() -> void:
	rain = _make(4000, 1.1, _rain_material(), _rain_process(), Vector2(0.04, 1.1), true)
	rain.fixed_fps = 0
	for kind in ["maple", "ginkgo", "sakura"]:
		leaves[kind] = _make(90, 9.0, _leaf_material(), _leaf_process(kind), Vector2(0.14, 0.14) if kind != "sakura" else Vector2(0.09, 0.09), false)
	motes = _make(160, 7.0, _glow_material(Color(1.6, 1.3, 0.8, 0.8)), _mote_process(), Vector2(0.03, 0.03), false)
	fireflies = _make(70, 6.0, _glow_material(Color(2.2, 3.0, 1.2, 1.0)), _firefly_process(), Vector2(0.05, 0.05), false)
	snow = _make(1500, 7.0, _glow_material(Color(1.0, 1.0, 1.0, 0.9), false), _snow_process(), Vector2(0.05, 0.05), false)
	for p in [rain, motes, fireflies, snow]:
		p.amount_ratio = 0.0
	for k in leaves:
		(leaves[k] as GPUParticles3D).amount_ratio = 0.0


func _make(amount: int, lifetime: float, mat: Material, pm: ParticleProcessMaterial, size: Vector2, collide: bool) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime * 0.5
	p.randomness = 0.5
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = size
	q.material = mat
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-40, -30, -40), Vector3(80, 60, 80))
	p.local_coords = false
	if collide:
		p.collision_base_size = 0.02
	add_child(p)
	return p


# ------------------------------------------------------------------ materials

func _rain_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/fx/rain_streak.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.albedo_color = Color(0.75, 0.8, 0.88, 0.35)
	m.vertex_color_use_as_albedo = true
	return m


func _leaf_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/fx/leaves_atlas.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.4
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.particles_anim_h_frames = 2
	m.particles_anim_v_frames = 2
	m.particles_anim_loop = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.backlight_enabled = true
	m.backlight = Color(0.5, 0.3, 0.2)
	m.roughness = 0.8
	return m


func _glow_material(c: Color, additive := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/fx/spark.png")
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.albedo_color = c
	m.vertex_color_use_as_albedo = true
	return m


# ------------------------------------------------------------------ processes

func _box(pm: ParticleProcessMaterial, extents: Vector3) -> void:
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = extents


func _rain_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	_box(pm, Vector3(22, 1, 22))
	pm.direction = Vector3.DOWN
	pm.spread = 3.0
	pm.initial_velocity_min = 16.0
	pm.initial_velocity_max = 20.0
	pm.gravity = Vector3(0, -6, 0)
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	return pm


func _leaf_process(kind: String) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	_box(pm, Vector3(18, 5, 18))
	pm.direction = Vector3.DOWN
	pm.spread = 40.0
	pm.initial_velocity_min = 0.3
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, -0.7, 0)
	pm.damping_min = 0.3
	pm.damping_max = 0.6
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.6
	pm.turbulence_noise_scale = 3.0
	pm.turbulence_influence_min = 0.05
	pm.turbulence_influence_max = 0.2
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -160.0
	pm.angular_velocity_max = 160.0
	pm.scale_min = 0.7
	pm.scale_max = 1.3
	# pick frames of the 2x2 atlas: maple (0,1), ginkgo (2), sakura (3)
	match kind:
		"maple":
			pm.anim_offset_min = 0.0
			pm.anim_offset_max = 0.49
		"ginkgo":
			pm.anim_offset_min = 0.5
			pm.anim_offset_max = 0.74
		_:
			pm.anim_offset_min = 0.75
			pm.anim_offset_max = 0.99
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_friction = 0.9
	pm.collision_bounce = 0.05
	return pm


func _mote_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	_box(pm, Vector3(14, 2.5, 14))
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 0.05
	pm.initial_velocity_max = 0.2
	pm.gravity = Vector3(0, 0.02, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 2.0
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	return pm


func _firefly_process() -> ParticleProcessMaterial:
	var pm := _mote_process()
	_box(pm, Vector3(16, 1.2, 16))
	pm.turbulence_noise_strength = 1.4
	pm.initial_velocity_max = 0.4
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	for k in 4:
		g.add_point(0.1 + k * 0.22, Color(1, 1, 1, 1.0 if k % 2 == 0 else 0.1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	return pm


func _snow_process() -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	_box(pm, Vector3(22, 3, 22))
	pm.direction = Vector3.DOWN
	pm.spread = 20.0
	pm.initial_velocity_min = 0.8
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -0.4, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 1.0
	pm.turbulence_noise_scale = 4.0
	pm.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	return pm


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var world := Game.world as World
	if cam == null or world == null:
		return
	var c := cam.global_position
	var wv := world.wind.vector3(1.0) if world.wind else Vector3.ZERO
	rain.global_position = c + Vector3(0, 14, 0) - wv * 0.6
	snow.global_position = c + Vector3(0, 10, 0) - wv * 2.0
	for k in leaves:
		(leaves[k] as GPUParticles3D).global_position = c + Vector3(0, 7, 0) - wv * 3.0
	motes.global_position = c + Vector3(0, 0.5, 0)
	fireflies.global_position = Vector3(c.x, world.data.get_height(c.x, c.z) + 1.0, c.z)
	# the wind carries everything
	(rain.process_material as ParticleProcessMaterial).gravity = Vector3(wv.x * 3.0, -6.0, wv.z * 3.0)
	for k in leaves:
		var pm := (leaves[k] as GPUParticles3D).process_material as ParticleProcessMaterial
		pm.gravity = Vector3(wv.x * 1.6, -0.7, wv.z * 1.6)
	(snow.process_material as ParticleProcessMaterial).gravity = Vector3(wv.x * 1.2, -0.4, wv.z * 1.2)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.5
	var w := world.weather
	var tod := world.time_of_day
	var day := tod.daylight() if tod else 1.0
	var rain_amt := w.rain if w else 0.0
	_sample_biome(c, world.data)
	var alt := clampf((c.y - 200.0) / 60.0, 0.0, 1.0)
	var target_rain := rain_amt * (1.0 - alt)
	var target_snow := maxf(alt * 0.5, rain_amt * alt)
	var windy := clampf(world.wind.strength / 1.5, 0.3, 1.5) if world.wind else 1.0
	rain.amount_ratio = move_toward(rain.amount_ratio, target_rain, 0.2)
	rain.emitting = rain.amount_ratio > 0.01
	snow.amount_ratio = move_toward(snow.amount_ratio, target_snow, 0.1)
	snow.emitting = snow.amount_ratio > 0.01
	for k in leaves:
		var lp := leaves[k] as GPUParticles3D
		lp.amount_ratio = clampf(_species[k] * windy * (1.0 - rain_amt * 0.5), 0.0, 1.0)
		lp.emitting = lp.amount_ratio > 0.02
	var sp := world.data.sample_splat(c.x, c.z)
	motes.amount_ratio = clampf((sp.g * 1.2 + sp.r * 0.3) * day * (1.0 - rain_amt), 0.0, 1.0)
	motes.emitting = motes.amount_ratio > 0.02
	fireflies.amount_ratio = clampf((1.0 - day) * (1.0 - rain_amt) * (sp.r + sp.g) * (1.0 - alt), 0.0, 1.0)
	fireflies.emitting = fireflies.amount_ratio > 0.02


## Tree species density around the camera (from the vegetation map).
func _sample_biome(c: Vector3, data: WorldData) -> void:
	var acc := {"maple": 0.0, "ginkgo": 0.0, "sakura": 0.0}
	for k in 9:
		var a := TAU * k / 9.0
		var r := 0.0 if k == 0 else 18.0
		var v := data.sample_veg(c.x + cos(a) * r, c.z + sin(a) * r)
		var kind := data.tree_type_name(v.g)
		if acc.has(kind):
			acc[kind] += v.r / 9.0
	for k in acc:
		_species[k] = clampf(acc[k] * 2.5, 0.0, 1.0)
