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
	var ref: WeakRef = weakref(ch)   # the character may be freed before the pool forms
	t.timeout.connect(func() -> void:
		var who := ref.get_ref() as Node3D
		if who == null:
			return
		var body: RagdollBody = who.get("body")
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


## Red warning triangle that flashes above an enemy about to land a perilous
## (unblockable) attack; a symbol instead of text so it reads in any language.
func peril(pos: Vector3) -> void:
	var l := Sprite3D.new()
	l.texture = _peril_texture()
	l.pixel_size = 0.0055
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.shaded = false
	l.render_priority = 11
	_add(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 0.3
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE * 1.15, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.2).set_delay(0.5)
	tw.chain().tween_callback(l.queue_free)
	shockwave(pos, Color(1.0, 0.15, 0.1), 0.8)


var _peril_tex: Texture2D


func _peril_texture() -> Texture2D:
	if _peril_tex != null:
		return _peril_tex
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var pts := [Vector2(n * 0.5, 6.0), Vector2(n - 5.0, n - 12.0), Vector2(5.0, n - 12.0)]
	var centroid: Vector2 = (pts[0] + pts[1] + pts[2]) / 3.0
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5)
			var m := 1e9
			for k in 3:
				var a: Vector2 = pts[k]
				var b: Vector2 = pts[(k + 1) % 3]
				var e := (b - a).normalized()
				var nrm := Vector2(-e.y, e.x)
				if nrm.dot(centroid - a) < 0.0:
					nrm = -nrm
				m = minf(m, nrm.dot(p - a))
			if m <= 0.0:
				continue
			var col := Color(0.1, 0.0, 0.0, 1.0) if m < 5.0 else Color(0.95, 0.1, 0.06, 1.0)
			# exclamation mark
			var bar := absf(p.x - n * 0.5) < 5.0 and p.y > 34.0 and p.y < 62.0
			var dot := p.distance_to(Vector2(n * 0.5, 71.0)) < 6.0
			if bar or dot:
				col = Color(1, 1, 1, 1)
			col.a = clampf(m / 1.5, 0.0, 1.0)
			img.set_pixel(x, y, col)
	_peril_tex = ImageTexture.create_from_image(img)
	return _peril_tex


## Onimusha-style souls: glowing orbs pour out of a fallen enemy and stream
## into the player, restoring health (blue) and Resolve (gold).
func souls(origin: Vector3, count: int, target: Node3D) -> void:
	_setup()
	for i in count:
		var gold := i % 3 == 0
		var col := Color(1.0, 0.8, 0.3) if gold else Color(0.35, 0.65, 1.0)
		var orb := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.055
		sm.height = 0.11
		sm.radial_segments = 8
		sm.rings = 4
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 5.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		sm.material = mat
		orb.mesh = sm
		orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 0.9
		light.omni_range = 2.2
		orb.add_child(light)
		var trail := CPUParticles3D.new()
		trail.amount = 14
		trail.lifetime = 0.35
		trail.local_coords = false
		trail.mesh = sm
		trail.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		trail.emission_sphere_radius = 0.03
		trail.gravity = Vector3.ZERO
		trail.scale_amount_min = 0.25
		trail.scale_amount_max = 0.45
		trail.scale_amount_curve = _fade_curve()
		orb.add_child(trail)
		_add(orb)
		orb.global_position = origin
		var up := Vector3(randf_range(-1.2, 1.2), randf_range(1.2, 2.4), randf_range(-1.2, 1.2))
		var delay := randf() * 0.35
		var dur := randf_range(0.8, 1.15)
		var tw := orb.create_tween()
		var tref: WeakRef = weakref(target)   # the target may be freed while the orbs are still flying
		tw.tween_interval(delay)
		tw.tween_method(func(t: float) -> void:
			var tgt := tref.get_ref() as Node3D
			var dest: Vector3 = tgt.global_position + Vector3(0, 1.0, 0) if tgt else origin
			var ctrl := origin + up
			var k := t * t * (3.0 - 2.0 * t)
			orb.global_position = origin.lerp(ctrl, k).lerp(ctrl.lerp(dest, k), k), 0.0, 1.0, dur)
		tw.tween_callback(func() -> void:
			var tgt := tref.get_ref() as Node3D
			if tgt and tgt.has_method("absorb_soul"):
				tgt.absorb_soul(gold)
			orb.queue_free())


func _fade_curve() -> Curve:
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.0))
	return c


## Expanding ring + flash, used for parries and heavy impacts.
func shockwave(pos: Vector3, color := Color(1.0, 0.9, 0.6), size := 1.0) -> void:
	_setup()
	var m := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var gt := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.6, Color(1, 1, 1, 0))
	g.add_point(0.86, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = gt
	mat.albedo_color = Color(color.r * 2.2, color.g * 2.2, color.b * 2.2, 1.0)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = true
	q.material = mat
	m.mesh = q
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add(m)
	m.global_position = pos
	m.scale = Vector3.ONE * 0.1
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * 2.6 * size, 0.28).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(mat, "albedo_color:a", 0.0, 0.28)
	tw.chain().tween_callback(m.queue_free)


func dust(pos: Vector3, strength := 1.0) -> void:
	_setup()
	_particles(pos + Vector3(0, 0.1, 0), Vector3.UP, _mat_dust, _mesh_puff, int(6 * strength) + 2, 1.1, _dust_mat)


# ------------------------------------------------------------------ swing juice (Devil May Cry style)

var _wind_shader: Shader
var _wind_mesh: QuadMesh
var _ghost_shader: Shader
var _mat_streaks: ParticleProcessMaterial
var _streak_mat: StandardMaterial3D
var _ghosts_alive := 0


func _combat_fx() -> float:
	return float(Settings.get_value("combat_fx", 1.0))


func _setup_swing_fx() -> void:
	if _wind_shader != null:
		return
	_setup()
	_wind_shader = load("res://shaders/wind_slash.gdshader")
	_ghost_shader = load("res://shaders/afterimage.gdshader")
	_wind_mesh = QuadMesh.new()
	_wind_mesh.size = Vector2(3.6, 1.8)
	# thin streaks of air that outrun the crescent
	_streak_mat = _spark_mat.duplicate()
	_streak_mat.albedo_color = Color(0.85, 0.95, 1.0)
	_streak_mat.emission = Color(0.7, 0.85, 1.0)
	_streak_mat.emission_energy_multiplier = 5.0
	# camera-facing strips that keep their length along the velocity
	_streak_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_streak_mat.billboard_keep_scale = true
	_mat_streaks = ParticleProcessMaterial.new()
	_mat_streaks.direction = Vector3(0, 0, -1)
	_mat_streaks.spread = 16.0
	_mat_streaks.initial_velocity_min = 8.0
	_mat_streaks.initial_velocity_max = 20.0
	_mat_streaks.damping_min = 5.0
	_mat_streaks.damping_max = 9.0
	_mat_streaks.gravity = Vector3.ZERO
	_mat_streaks.particle_flag_align_y = true
	_mat_streaks.scale_min = 1.2
	_mat_streaks.scale_max = 3.0
	_mat_streaks.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	_mat_streaks.emission_sphere_radius = 0.9
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.9))
	g.set_color(1, Color(1, 1, 1, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	_mat_streaks.color_ramp = gt


## A crescent of cut air thrown along `forward` by a swing whose blade moved along `sweep`
## (world direction). It bends the picture behind it, leaves streaks and stirs the dust.
## `size` 1 is a light slash; `color` follows the move.
func wind_slash(origin: Vector3, forward: Vector3, sweep: Vector3, size := 1.0, color := Color(0.85, 0.95, 1.0), life := 0.3, crescent := true) -> void:
	var k := _combat_fx()
	if k <= 0.01:
		return
	_setup_swing_fx()
	var fwd := Vector3(forward.x, 0.0, forward.z)
	fwd = fwd.normalized() if fwd.length_squared() > 1e-4 else Vector3.FORWARD
	if not crescent:
		# a thrust pierces: streaks of air only
		_particles(origin, fwd, _mat_streaks, _mesh_spark, int(8 + 6 * size * k), 0.3, _streak_mat)
		return
	# roll: the crescent's chord follows the swing as it appears on screen, bulging upwards
	var roll := 0.0
	var cam := get_viewport().get_camera_3d()
	if cam:
		var sx := sweep.dot(cam.global_basis.x)
		var sy := sweep.dot(cam.global_basis.y)
		if absf(sx) + absf(sy) > 0.05:
			roll = atan2(sy, sx)
			if roll > PI * 0.5:
				roll -= PI
			elif roll <= -PI * 0.5:
				roll += PI
	var mi := MeshInstance3D.new()
	mi.mesh = _wind_mesh
	var mat := ShaderMaterial.new()
	mat.shader = _wind_shader
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("roll", roll)
	mat.set_shader_parameter("energy", 2.4 * clampf(k, 0.4, 1.5))
	mat.set_shader_parameter("bend", 0.05 * size)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 8.0
	_add(mi)
	mi.global_position = origin
	mi.scale = Vector3(0.55, 0.55, 1.0) * size
	var travel := fwd * (3.4 + 2.4 * size)
	var tw := mi.create_tween().set_parallel(true)
	tw.tween_property(mi, "global_position", origin + travel, life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(mi, "scale", Vector3(1.3, 1.3, 1.0) * size, life).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("age", v), 0.0, 1.0, life)
	tw.chain().tween_callback(mi.queue_free)
	# streaks of air and a puff of dust where the wave grazes the ground
	_particles(origin, fwd, _mat_streaks, _mesh_spark, int(10 + 8 * size * k), 0.34, _streak_mat)
	var ground := _ray_down(origin)
	if not ground.is_empty() and origin.y - (ground.position as Vector3).y < 1.4:
		dust((ground.position as Vector3) + fwd * 0.9, 0.5 + 0.4 * size)


## A short-lived translucent copy of a character's pose (dashes, lunges, big strikes).
func afterimage(ch: Node3D, color := Color(0.55, 0.8, 1.0), life := 0.34, alpha := 0.5) -> void:
	if _combat_fx() <= 0.01 or ch == null or _ghosts_alive >= 14:
		return
	var body: RagdollBody = ch.get("body")
	if body == null or body.dead:
		return
	_setup_swing_fx()
	var root := Node3D.new()
	_add(root)
	var mat := ShaderMaterial.new()
	mat.shader = _ghost_shader
	mat.set_shader_parameter("tint", color)
	mat.set_shader_parameter("alpha", alpha * clampf(_combat_fx(), 0.3, 1.4))
	var sources: Array[MeshInstance3D] = []
	for part in body.part_meshes:
		for mi in body.part_meshes[part]:
			sources.append(mi)
	var weapon: Node = ch.get("weapon")
	if weapon and weapon.get("in_hand"):
		for c in weapon.find_children("*", "MeshInstance3D", true, false):
			sources.append(c)
	for src in sources:
		if not src.is_visible_in_tree() or src.mesh == null:
			continue
		var g := MeshInstance3D.new()
		g.mesh = src.mesh
		g.material_override = mat
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(g)
		g.global_transform = src.global_transform
	_ghosts_alive += 1
	var tw := root.create_tween()
	tw.tween_method(func(v: float) -> void: mat.set_shader_parameter("alpha", v), alpha * clampf(_combat_fx(), 0.3, 1.4), 0.0, life)
	tw.tween_callback(func() -> void:
		_ghosts_alive -= 1
		root.queue_free())
