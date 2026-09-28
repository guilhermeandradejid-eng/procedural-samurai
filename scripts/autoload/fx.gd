extends Node
## Visual effects hub: blood sprays and mist, pulsing stump fountains,
## ground decals and pools, sword sparks with light flashes, dust puffs,
## falling leaves bursts. Every effect is pooled or self-freeing.

const MAX_DECALS := 160

var _mat_spray: ParticleProcessMaterial
var _mat_mist: ParticleProcessMaterial
var _mat_sparks: ParticleProcessMaterial
var _mat_dust: ParticleProcessMaterial
var _mat_fountain: ParticleProcessMaterial
var _mesh_drop: Mesh
var _mesh_puff: QuadMesh
var _mesh_spark: QuadMesh
var _drop_mat: StandardMaterial3D
var _mist_mat: StandardMaterial3D
var _spark_mat: StandardMaterial3D
var _dust_mat: StandardMaterial3D
var _splats: Array[Texture2D] = []
var _splat_normals: Array[Texture2D] = []
var _pool_tex: Texture2D
var _decals: Array[Decal] = []
var _collider: GPUParticlesCollisionHeightField3D
var _ready_done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _setup() -> void:
	if _ready_done:
		return
	_ready_done = true
	for i in 4:
		_splats.append(load("res://assets/textures/fx/blood_splat_%d.png" % i))
		_splat_normals.append(load("res://assets/textures/fx/blood_splat_%d_n.png" % i))
	_pool_tex = load("res://assets/textures/fx/blood_pool.png")
	# droplets: tiny stretched spheres aligned to their velocity
	var sm := SphereMesh.new()
	sm.radius = 0.011
	sm.height = 0.045
	sm.radial_segments = 6
	sm.rings = 3
	_mesh_drop = sm
	_drop_mat = StandardMaterial3D.new()
	_drop_mat.albedo_color = Color(0.36, 0.015, 0.015)
	_drop_mat.roughness = 0.12
	_drop_mat.metallic_specular = 0.8
	sm.material = _drop_mat
	_mat_spray = ParticleProcessMaterial.new()
	_mat_spray.direction = Vector3(0, 0, -1)
	_mat_spray.spread = 26.0
	_mat_spray.initial_velocity_min = 2.0
	_mat_spray.initial_velocity_max = 7.5
	_mat_spray.gravity = Vector3(0, -13.0, 0)
	_mat_spray.scale_min = 0.5
	_mat_spray.scale_max = 1.6
	_mat_spray.particle_flag_align_y = true
	_mat_spray.damping_min = 0.3
	_mat_spray.damping_max = 1.2
	_mat_spray.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	# mist
	_mesh_puff = QuadMesh.new()
	_mesh_puff.size = Vector2(0.5, 0.5)
	_mist_mat = StandardMaterial3D.new()
	_mist_mat.albedo_texture = load("res://assets/textures/fx/smoke.png")
	_mist_mat.albedo_color = Color(0.45, 0.02, 0.02, 0.55)
	_mist_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mist_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mist_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mist_mat.vertex_color_use_as_albedo = true
	_mat_mist = ParticleProcessMaterial.new()
	_mat_mist.direction = Vector3(0, 0, -1)
	_mat_mist.spread = 40.0
	_mat_mist.initial_velocity_min = 0.4
	_mat_mist.initial_velocity_max = 1.6
	_mat_mist.gravity = Vector3(0, -0.6, 0)
	_mat_mist.damping_min = 1.5
	_mat_mist.damping_max = 3.0
	_mat_mist.scale_min = 0.4
	_mat_mist.scale_max = 1.1
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.4))
	sc.add_point(Vector2(1, 1.6))
	var sct := CurveTexture.new()
	sct.curve = sc
	_mat_mist.scale_curve = sct
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 0.9))
	grad.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	_mat_mist.color_ramp = gt
	# sparks
	_mesh_spark = QuadMesh.new()
	_mesh_spark.size = Vector2(0.02, 0.16)
	_spark_mat = StandardMaterial3D.new()
	_spark_mat.albedo_texture = load("res://assets/textures/fx/spark.png")
	_spark_mat.albedo_color = Color(1.0, 0.85, 0.5)
	_spark_mat.emission_enabled = true
	_spark_mat.emission = Color(1.0, 0.7, 0.3)
	_spark_mat.emission_energy_multiplier = 8.0
	_spark_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_spark_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spark_mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	_spark_mat.billboard_keep_scale = true
	_mat_sparks = ParticleProcessMaterial.new()
	_mat_sparks.direction = Vector3(0, 0, -1)
	_mat_sparks.spread = 70.0
	_mat_sparks.initial_velocity_min = 3.0
	_mat_sparks.initial_velocity_max = 11.0
	_mat_sparks.gravity = Vector3(0, -9.8, 0)
	_mat_sparks.particle_flag_align_y = true
	_mat_sparks.scale_min = 0.5
	_mat_sparks.scale_max = 1.3
	var sgrad := Gradient.new()
	sgrad.set_color(0, Color(1, 1, 0.9, 1))
	sgrad.set_color(1, Color(1, 0.4, 0.1, 0))
	var sgt := GradientTexture1D.new()
	sgt.gradient = sgrad
	_mat_sparks.color_ramp = sgt
	_spark_mat.vertex_color_use_as_albedo = true
	# dust
	_dust_mat = _mist_mat.duplicate()
	_dust_mat.albedo_color = Color(0.62, 0.55, 0.45, 0.35)
	_mat_dust = _mat_mist.duplicate()
	_mat_dust.direction = Vector3(0, 1, 0)
	_mat_dust.spread = 80.0
	_mat_dust.gravity = Vector3(0, 0.2, 0)
	# stump fountain
	_mat_fountain = _mat_spray.duplicate()
	_mat_fountain.spread = 14.0
	_mat_fountain.initial_velocity_min = 1.5
	_mat_fountain.initial_velocity_max = 4.5
	# particles collide with the ground near the camera
	_collider = GPUParticlesCollisionHeightField3D.new()
	_collider.size = Vector3(60, 40, 60)
	_collider.resolution = GPUParticlesCollisionHeightField3D.RESOLUTION_256
	_collider.update_mode = GPUParticlesCollisionHeightField3D.UPDATE_MODE_WHEN_MOVED
	_collider.follow_camera_enabled = true
	_add(_collider)


func _add(n: Node) -> void:
	var root := get_tree().current_scene
	if root == null:
		root = get_tree().root
	root.add_child(n)


func _gore() -> bool:
	return bool(Settings.get_value("gore", true))


func _particles(pos: Vector3, dir: Vector3, mat: ParticleProcessMaterial, mesh: Mesh, amount: int, lifetime: float,
		material: Material = null) -> GPUParticles3D:
	_setup()
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = maxi(1, amount)
	p.lifetime = lifetime
	p.process_material = mat
	p.draw_pass_1 = mesh
	if material:
		p.material_override = material
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-6, -6, -6), Vector3(12, 12, 12))
	_add(p)
	p.global_position = pos
	if dir.length_squared() > 1e-4:
		var d := dir.normalized()
		var up := Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT
		p.global_basis = Basis.looking_at(d, up)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


# ------------------------------------------------------------------ blood

func blood_hit(pos: Vector3, dir: Vector3, power := 1.0) -> void:
	if not _gore():
		sparks(pos, dir, 0.4)
		return
	var d := (dir + Vector3(0, 0.25, 0)).normalized()
	_particles(pos, d, _mat_spray, _mesh_drop, int(50 * power), 1.4)
	_particles(pos, d, _mat_mist, _mesh_puff, int(6 + 4 * power), 0.9, _mist_mat)
	_splat_ground(pos, d, 3 + int(power * 2), 0.5 + 0.35 * power)


func blood_burst(pos: Vector3, dir: Vector3, power := 1.5) -> void:
	if not _gore():
		return
	_particles(pos, (dir + Vector3.UP * 0.6).normalized(), _mat_spray, _mesh_drop, int(110 * power), 1.8)
	_particles(pos, dir, _mat_mist, _mesh_puff, 14, 1.2, _mist_mat)
	_splat_ground(pos, dir, 6, 1.1)


func blood_flick(pos: Vector3, dir: Vector3, amount: float) -> void:
	if amount < 0.05 or not _gore():
		return
	_particles(pos, dir, _mat_spray, _mesh_drop, int(30 * amount + 6), 1.0)
	_splat_ground(pos, dir, 2, 0.35)


func drip(pos: Vector3) -> void:
	if not _gore():
		return
	_particles(pos, Vector3.DOWN, _mat_spray, _mesh_drop, 2, 0.8)


## Pulsing arterial spray attached to a body part (stumps).
func stump_fountain(parent: Node3D, local_pos: Vector3, local_dir: Vector3, duration := 2.5) -> void:
	if not _gore() or parent == null:
		return
	_setup()
	var p := GPUParticles3D.new()
	p.amount = 90
	p.lifetime = 1.0
	p.explosiveness = 0.0
	p.process_material = _mat_fountain
	p.draw_pass_1 = _mesh_drop
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-5, -5, -5), Vector3(10, 10, 10))
	parent.add_child(p)
	p.position = local_pos
	var d := local_dir.normalized() if local_dir.length_squared() > 1e-4 else Vector3.UP
	p.basis = Basis.looking_at(d, Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT)
	p.emitting = true
	var tw := p.create_tween()
	var beats := int(duration * 1.6)
	for i in beats:
		var k := 1.0 - float(i) / beats
		tw.tween_property(p, "amount_ratio", 1.0 * k, 0.08)
		tw.tween_property(p, "amount_ratio", 0.15 * k, 0.5)
	tw.tween_property(p, "emitting", false, 0.0)
	tw.tween_interval(1.2)
	tw.tween_callback(p.queue_free)
	# a few ground splats along the way
	var gp := parent.global_transform * local_pos
	_splat_ground(gp, parent.global_basis * d, 3, 0.8)


func blood_pool_later(ch: Node3D) -> void:
	if not _gore():
		return
	var t := get_tree().create_timer(1.6)
	t.timeout.connect(func() -> void:
		if not is_instance_valid(ch):
			return
		var body: RagdollBody = ch.get("body")
		if body == null:
			return
		var p: Vector3 = (body.parts["belly"] as RigidBody3D).global_position
		var hit := _ray_down(p)
		if hit.is_empty():
			return
		var dec := _decal(hit.position, hit.normal, 0.3, _pool_tex, null)
		if dec:
			var tw := dec.create_tween()
			tw.tween_property(dec, "size", Vector3(2.2, 1.0, 2.2), 7.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE))


func _ray_down(p: Vector3) -> Dictionary:
	var world := get_tree().current_scene
	if world == null or not (world is Node3D):
		return {}
	var space := (world as Node3D).get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 6.0, 1)
	return space.intersect_ray(q)


func _splat_ground(pos: Vector3, dir: Vector3, count: int, size: float) -> void:
	var flat := Vector3(dir.x, 0, dir.z)
	for i in count:
		var dist := randf_range(0.2, 2.2) * size
		var p := pos + flat.normalized() * dist + Vector3(randf_range(-0.4, 0.4), 0, randf_range(-0.4, 0.4)) * size
		var hit := _ray_down(p)
		if hit.is_empty():
			continue
		var i_tex := randi() % _splats.size()
		_decal(hit.position, hit.normal, randf_range(0.35, 0.9) * size, _splats[i_tex], _splat_normals[i_tex])


func _decal(pos: Vector3, normal: Vector3, size: float, tex: Texture2D, nrm: Texture2D) -> Decal:
	_setup()
	var d: Decal
	var limit := mini(MAX_DECALS, int(Settings.quality().get("decals", 120)))
	if _decals.size() >= limit:
		d = _decals.pop_front()
		if not is_instance_valid(d):
			d = Decal.new()
			_add(d)
	else:
		d = Decal.new()
		_add(d)
	_decals.append(d)
	d.texture_albedo = tex
	d.texture_normal = nrm
	d.modulate = Color(0.9, 0.9, 0.9, 1.0)
	d.albedo_mix = 1.0
	d.normal_fade = 0.3
	d.upper_fade = 0.2
	d.lower_fade = 0.2
	d.cull_mask = 1
	d.size = Vector3(size, 0.8, size)
	var up := normal.normalized()
	var ref := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(up).normalized()
	var z := x.cross(up).normalized()
	d.global_transform = Transform3D(Basis(x, up, z).rotated(up, randf() * TAU), pos)
	return d


# ------------------------------------------------------------------ misc

func sparks(pos: Vector3, dir: Vector3, strength := 1.0) -> void:
	_setup()
	_particles(pos, dir, _mat_sparks, _mesh_spark, int(26 * strength) + 6, 0.45, _spark_mat)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.75, 0.4)
	light.light_energy = 4.0 * strength
	light.omni_range = 4.0
	light.shadow_enabled = false
	_add(light)
	light.global_position = pos
	var tw := light.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.14)
	tw.tween_callback(light.queue_free)


func dust(pos: Vector3, strength := 1.0) -> void:
	_setup()
	_particles(pos + Vector3(0, 0.1, 0), Vector3.UP, _mat_dust, _mesh_puff, int(6 * strength) + 2, 1.1, _dust_mat)
