class_name RagdollBody
extends Node3D
## Human-Fall-Flat style physical body: one RigidBody3D per rig part joined
## with cone-twist / hinge joints. While alive every part is velocity-driven
## towards the animator's target pose (an "active ragdoll"): strong enough to
## look animated, soft enough to wobble, flinch and get knocked around.
## Muscle strength drops on hits and goes to zero on death. Parts can be
## severed (dismemberment) at any joint.

signal part_severed(part: String, stump_part: String)
## A part was cut clean through: `chunk` is the far half (carrying every child).
signal part_sliced(part: String, chunk: RigidBody3D, world_point: Vector3, world_normal: Vector3)

const LAYER_ALIVE := 1 << 2
const LAYER_DEAD := 1 << 3
const MASK_ALIVE := 1
const MASK_DEAD := 1 | (1 << 3) | (1 << 4)

## joint setup: child part -> [type, swing/lower deg, twist/upper deg]
const JOINTS := {
	"belly": ["cone", 34.0, 28.0], "chest": ["cone", 34.0, 30.0], "head": ["cone", 55.0, 60.0],
	"upper_arm_r": ["cone", 150.0, 85.0], "upper_arm_l": ["cone", 150.0, 85.0],
	"forearm_r": ["hinge", -5.0, 150.0], "forearm_l": ["hinge", -5.0, 150.0],
	"hand_r": ["cone", 45.0, 35.0], "hand_l": ["cone", 45.0, 35.0],
	"thigh_r": ["cone", 100.0, 35.0], "thigh_l": ["cone", 100.0, 35.0],
	"shin_r": ["hinge", -150.0, 5.0], "shin_l": ["hinge", -150.0, 5.0],
	"foot_r": ["cone", 28.0, 12.0], "foot_l": ["cone", 28.0, 12.0],
}

var character: Node3D
var style_name := "ronin"
var scale_factor := 1.0
var parts := {}           # part -> RigidBody3D
var part_meshes := {}     # part -> Array[MeshInstance3D] (body + gear, for shader fx)
var com := {}             # part -> Vector3 (scaled centre of mass offset from pivot)
var joints := {}          # child part -> Joint3D
var targets := {}         # part -> Transform3D world pivot transforms (set by the animator)
var strength := 1.0
var part_strength := {}
var severed := {}
var dead := false
var kinematic := false
var gear := {}            # piece name -> MeshInstance3D
var overrides := {}
var face: Face
var chunks: Array[RigidBody3D] = []   # far halves of sliced parts
var _swing := []          # secondary motion state for hanging armour
var _prev_vel := {}
var _flash := {}
var _blood := {}
var rng := RandomNumberGenerator.new()

static var _phys_mat: PhysicsMaterial
static var _cap_mesh: ArrayMesh
static var _bone_mesh: CapsuleMesh


func build(p_character: Node3D, style: String, scale := 1.0, seed := 0) -> void:
	Rig.ensure_loaded()
	character = p_character
	style_name = style
	scale_factor = scale
	rng.seed = seed if seed != 0 else randi()
	if _phys_mat == null:
		_phys_mat = PhysicsMaterial.new()
		_phys_mat.friction = 0.9
		_phys_mat.bounce = 0.02
	var body_scene: Node3D = (load("res://assets/models/characters/body.glb") as PackedScene).instantiate()
	var gear_scene: Node3D = (load("res://assets/models/characters/gear.glb") as PackedScene).instantiate()
	overrides = CharacterStyle.overrides_for(style, rng if seed != 0 else null)
	var wanted := CharacterStyle.gear_for(style, rng if seed != 0 else null)
	var root_xf: Transform3D = character.global_transform if character.is_inside_tree() else Transform3D.IDENTITY
	for part in Rig.ORDER:
		var rb := RigidBody3D.new()
		rb.name = part
		rb.top_level = true
		var shape_def: Dictionary = Rig.shapes[part]
		rb.mass = float(shape_def.mass) * pow(scale, 3.0)
		rb.collision_layer = LAYER_ALIVE
		rb.collision_mask = MASK_ALIVE
		rb.physics_material_override = _phys_mat
		rb.can_sleep = false
		rb.linear_damp = 0.05
		rb.angular_damp = 0.6
		rb.set_meta("character", character)
		rb.set_meta("part", part)
		var c: Vector3 = Rig.com_offset(part) * scale
		com[part] = c
		var cs := CollisionShape3D.new()
		_make_shape(cs, part, scale)
		rb.add_child(cs)
		var meshes: Array[MeshInstance3D] = []
		var src := body_scene.get_node_or_null(part) as MeshInstance3D
		if src:
			var mi := MeshInstance3D.new()
			mi.mesh = src.mesh
			mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale), -c)
			rb.add_child(mi)
			meshes.append(mi)
		part_meshes[part] = meshes
		add_child(rb)
		rb.global_transform = root_xf * Transform3D(Basis(), Rig.pivot[part] * scale) * Transform3D(Basis(), c)
		parts[part] = rb
		part_strength[part] = 1.0
		_prev_vel[part] = Vector3.ZERO
		_flash[part] = 0.0
		_blood[part] = 0.0
	# gear pieces: "<part>__<piece>", origin at their hinge/pivot (rest coords)
	for n in gear_scene.get_children():
		var nm := String(n.name)
		if not (nm in wanted) or not (n is MeshInstance3D):
			continue
		var part := nm.get_slice("__", 0)
		if not parts.has(part):
			continue
		var rb: RigidBody3D = parts[part]
		var mi := MeshInstance3D.new()
		mi.name = nm
		mi.mesh = (n as MeshInstance3D).mesh
		var hinge: Vector3 = (n as Node3D).position * scale
		mi.transform = Transform3D(Basis.from_scale(Vector3.ONE * scale), hinge - Rig.pivot[part] * scale - com[part])
		rb.add_child(mi)
		part_meshes[part].append(mi)
		gear[nm] = mi
		if nm.contains("kusazuri") or nm.contains("sode") or nm.contains("sashimono"):
			_swing.append({"node": mi, "part": part, "base": mi.transform, "ang": Vector2.ZERO, "vel": Vector2.ZERO,
				"k": 60.0 if nm.contains("sashimono") else 90.0, "limit": 0.6 if nm.contains("kusazuri") else 0.45})
	body_scene.free()
	gear_scene.free()
	for part in parts:
		for mi in part_meshes[part]:
			MaterialLibrary.apply(mi, overrides)
	_build_joints(root_xf)
	face = Face.new()
	face.setup(self)


func _make_shape(cs: CollisionShape3D, part: String, scale: float) -> void:
	var s: Dictionary = Rig.shapes[part]
	match s.type:
		"capsule":
			var a: Vector3 = s.a
			var b: Vector3 = s.b
			var cap := CapsuleShape3D.new()
			cap.radius = float(s.radius) * scale
			cap.height = maxf((b - a).length() * scale + cap.radius * 2.0, cap.radius * 2.01)
			cs.shape = cap
			var d := (b - a).normalized()
			cs.basis = _basis_y_to(d)
		"box":
			var bx := BoxShape3D.new()
			bx.size = (s.size as Vector3) * scale
			cs.shape = bx
		"sphere":
			var sp := SphereShape3D.new()
			sp.radius = float(s.radius) * scale
			cs.shape = sp


static func _basis_y_to(d: Vector3) -> Basis:
	var y := d.normalized()
	var ref := Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


func _build_joints(root_xf: Transform3D) -> void:
	for part in Rig.ORDER:
		var par: String = Rig.parent[part]
		if par == "":
			continue
		var def: Array = JOINTS[part]
		var piv: Vector3 = root_xf * (Rig.pivot[part] * scale_factor)
		var bone_dir: Vector3 = root_xf.basis * (Rig.end[part] - Rig.pivot[part]).normalized()
		var j: Joint3D
		if def[0] == "hinge":
			var h := HingeJoint3D.new()
			# hinge axis = local Z, aligned with the character's lateral axis
			var z := root_xf.basis.x.normalized()
			var y := bone_dir
			var x := y.cross(z).normalized()
			h.global_transform = Transform3D(Basis(x, y, z).orthonormalized(), piv)
			h.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
			h.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(def[1]))
			h.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(def[2]))
			j = h
		else:
			var c := ConeTwistJoint3D.new()
			var x := bone_dir
			var ref := root_xf.basis.z if absf(x.dot(root_xf.basis.z)) < 0.9 else root_xf.basis.x
			var y := ref.cross(x).normalized()
			var z := x.cross(y).normalized()
			c.global_transform = Transform3D(Basis(x, y, z), piv)
			c.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(def[1]))
			c.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(def[2]))
			j = c
		j.name = "J_" + part
		j.exclude_nodes_from_collision = true
		add_child(j)
		j.top_level = true
		if def[0] == "hinge":
			j.global_transform = (j as Node3D).global_transform
		j.node_a = j.get_path_to(parts[par])
		j.node_b = j.get_path_to(parts[part])
		joints[part] = j
	# keep every part from colliding with every other part of the same body
	var list: Array = parts.values()
	for i in list.size():
		for k in range(i + 1, list.size()):
			(list[i] as RigidBody3D).add_collision_exception_with(list[k])


## Places every part exactly on its target (spawning, respawn, far LOD).
func snap_to_targets() -> void:
	for part in parts:
		if severed.has(part) or not targets.has(part):
			continue
		var rb: RigidBody3D = parts[part]
		rb.global_transform = targets[part] * Transform3D(Basis(), com[part])
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.reset_physics_interpolation()


func set_kinematic(on: bool) -> void:
	if on == kinematic or dead:
		return
	kinematic = on
	for part in parts:
		if severed.has(part):
			continue
		var rb: RigidBody3D = parts[part]
		rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		rb.freeze = on


## Velocity-driven tracking of the target pose (called every physics tick).
func drive(delta: float) -> void:
	if dead:
		_update_fx(delta)
		return
	if kinematic:
		for part in parts:
			if severed.has(part) or not targets.has(part):
				continue
			(parts[part] as RigidBody3D).global_transform = targets[part] * Transform3D(Basis(), com[part])
		_update_fx(delta)
		return
	var inv_dt := 1.0 / maxf(delta, 1e-4)
	for part in Rig.ORDER:
		if severed.has(part) or not targets.has(part):
			continue
		var rb: RigidBody3D = parts[part]
		part_strength[part] = move_toward(part_strength[part], 1.0, delta * 1.8)
		var k: float = clampf(strength * part_strength[part] * Rig.STIFFNESS[part], 0.0, 1.0)
		if k < 0.01:
			continue
		var tgt: Transform3D = targets[part] * Transform3D(Basis(), com[part])
		var cur := rb.global_transform
		var err := tgt.origin - cur.origin
		if err.length_squared() > 4.0 and strength > 0.5:
			rb.global_transform = tgt
			rb.linear_velocity = Vector3.ZERO
			rb.angular_velocity = Vector3.ZERO
			continue
		var v_des := (err * inv_dt).limit_length(45.0)
		rb.linear_velocity = rb.linear_velocity.lerp(v_des, k)
		var q_cur := cur.basis.get_rotation_quaternion()
		var q_tgt := tgt.basis.get_rotation_quaternion()
		var dq := q_tgt * q_cur.inverse()
		if dq.w < 0.0:
			dq = -dq
		var s := sqrt(maxf(1.0 - dq.w * dq.w, 0.0))
		var w_des := Vector3.ZERO
		if s > 1e-5:
			var angle := 2.0 * acos(clampf(dq.w, -1.0, 1.0))
			w_des = (Vector3(dq.x, dq.y, dq.z) / s) * angle * inv_dt
		rb.angular_velocity = rb.angular_velocity.lerp(w_des.limit_length(60.0), k)
	_update_fx(delta)


func _update_fx(delta: float) -> void:
	# armour plates swing from their hinges (secondary motion)
	for st in _swing:
		var rb: RigidBody3D = parts[st.part]
		var v := rb.linear_velocity
		var acc: Vector3 = (v - _prev_vel.get(st.part, v)) / maxf(delta, 1e-4)
		var local := rb.global_basis.inverse() * (acc + Vector3(0, 12.0, 0) * 0.0)
		var force := Vector2(-local.z, local.x) * 0.012
		st.vel += (force - st.ang * st.k - st.vel * 7.0) * delta
		st.ang += st.vel * delta
		st.ang = st.ang.limit_length(st.limit)
		(st.node as Node3D).transform = st.base * Transform3D(Basis.from_euler(Vector3(st.ang.x, 0.0, st.ang.y)), Vector3.ZERO)
	for part in parts:
		_prev_vel[part] = (parts[part] as RigidBody3D).linear_velocity
		if _flash[part] > 0.0:
			_flash[part] = maxf(0.0, _flash[part] - delta * 5.0)
			for mi in part_meshes[part]:
				mi.set_instance_shader_parameter("hit_flash", _flash[part])


# ------------------------------------------------------------------ reactions

func flash(part: String, amount := 1.0, color := Color(1.0, 0.35, 0.25)) -> void:
	for p in [part, Rig.parent.get(part, "")]:
		if p == "" or not parts.has(p):
			continue
		_flash[p] = maxf(_flash[p], amount)
		for mi in part_meshes[p]:
			mi.set_instance_shader_parameter("flash_color", color)
			mi.set_instance_shader_parameter("hit_flash", _flash[p])


## Paints a blood wound on a part at a world position.
func add_blood(part: String, world_pos: Vector3, radius := 0.07, spread := 0.15) -> void:
	if not parts.has(part):
		return
	var rb: RigidBody3D = parts[part]
	var local: Vector3 = rb.global_transform.affine_inverse() * world_pos + com[part]
	for mi in part_meshes[part]:
		var mesh_local: Vector3 = mi.transform.affine_inverse() * (local - com[part])
		mi.set_instance_shader_parameter("blood_hit", Vector4(mesh_local.x, mesh_local.y, mesh_local.z, radius / scale_factor))
	for p in parts:
		var d := (parts[p] as RigidBody3D).global_position.distance_to(world_pos)
		if d < 0.6:
			_blood[p] = minf(1.0, _blood[p] + spread * (1.0 - d / 0.6))
			for mi in part_meshes[p]:
				mi.set_instance_shader_parameter("blood_amount", _blood[p])


func impulse(part: String, imp: Vector3, at_world := Vector3.INF) -> void:
	if not parts.has(part):
		return
	var rb: RigidBody3D = parts[part]
	if at_world == Vector3.INF:
		rb.apply_central_impulse(imp)
	else:
		rb.apply_impulse(imp, at_world - rb.global_position)


func weaken(part: String, amount: float) -> void:
	if part_strength.has(part):
		part_strength[part] = minf(part_strength[part], amount)
		for c in Rig.children[part]:
			part_strength[c] = minf(part_strength[c], amount * 1.5)


func die() -> void:
	if dead:
		return
	dead = true
	strength = 0.0
	for part in parts:
		var rb: RigidBody3D = parts[part]
		rb.freeze = false
		rb.can_sleep = true
		rb.linear_damp = 0.25
		rb.angular_damp = 2.2
	# switch layers slightly later so the killing blow can still resolve
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		for p in parts:
			var body: RigidBody3D = parts[p]
			body.collision_layer = LAYER_DEAD
			body.collision_mask = MASK_DEAD)


## Detaches `part` (and everything below it). Returns false if already cut.
func sever(part: String, imp := Vector3.ZERO) -> bool:
	if not joints.has(part) or severed.has(part):
		return false
	var par: String = Rig.parent[part]
	var j: Joint3D = joints[part]
	joints.erase(part)
	j.queue_free()
	for p in Rig.subtree(part):
		severed[p] = true
		var rb: RigidBody3D = parts[p]
		rb.collision_layer = LAYER_DEAD
		rb.collision_mask = MASK_DEAD
		rb.can_sleep = true
		rb.linear_damp = 0.2
		rb.angular_damp = 1.2
		rb.freeze = false
	var cut: RigidBody3D = parts[part]
	cut.apply_central_impulse(imp)
	cut.apply_torque_impulse(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * imp.length() * 0.04)
	var bone_dir: Vector3 = (Rig.end[part] - Rig.pivot[part]).normalized()
	var r := _cap_radius(part)
	# stump on the parent, facing the lost limb; cap on the limb facing back
	_add_cap(par, Rig.pivot[part] * scale_factor, bone_dir, r)
	_add_cap(part, Rig.pivot[part] * scale_factor, -bone_dir, r)
	part_severed.emit(part, par)
	return true


const SLICEABLE := ["head", "chest", "belly", "upper_arm_r", "forearm_r", "upper_arm_l", "forearm_l",
	"thigh_r", "shin_r", "thigh_l", "shin_l"]
const SLICE_SHADERS := ["skin", "cloth", "armor"]


func _mesh_takes_slice(mi: MeshInstance3D) -> bool:
	if mi.mesh == null:
		return false
	for i in mi.mesh.get_surface_count():
		var m := mi.get_surface_override_material(i)
		if m is ShaderMaterial and (m as ShaderMaterial).shader:
			var path := (m as ShaderMaterial).shader.resource_path
			for s in SLICE_SHADERS:
				if path.ends_with(s + ".gdshader"):
					return true
	return false


## Cuts `part` in two along a plane (world point + normal). The half beyond
## the plane becomes a free body that takes all the children of the part with
## it; the near half stays attached as a stump. Returns the far half.
func slice(part: String, wpoint: Vector3, wnormal: Vector3, imp := Vector3.ZERO) -> RigidBody3D:
	if not parts.has(part) or not joints.has(part) or severed.has(part) or not (part in SLICEABLE):
		return null
	_ensure_cap_meshes()
	var rb: RigidBody3D = parts[part]
	var xf := rb.global_transform
	var pivot_l: Vector3 = -com[part]
	var end_l: Vector3 = pivot_l + (Rig.end[part] - Rig.pivot[part]) * scale_factor
	var p_l: Vector3 = xf.affine_inverse() * wpoint
	var n_l: Vector3 = (xf.basis.transposed() * wnormal).normalized()
	if n_l.dot(pivot_l - p_l) > 0.0:
		n_l = -n_l        # the normal points to the far (distal) side
	var denom := n_l.dot(end_l - pivot_l)
	var t := 0.5 if absf(denom) < 1e-4 else clampf(n_l.dot(p_l - pivot_l) / denom, 0.25, 0.75)
	var cut_l := pivot_l.lerp(end_l, t)
	var r := _cap_radius(part) / 1.05
	# far half
	var chunk := RigidBody3D.new()
	chunk.name = part + "_chunk"
	chunk.top_level = true
	chunk.mass = maxf(rb.mass * (1.0 - t), 0.2)
	chunk.collision_layer = LAYER_DEAD
	chunk.collision_mask = MASK_DEAD
	chunk.physics_material_override = _phys_mat
	chunk.linear_damp = 0.15
	chunk.angular_damp = 0.9
	add_child(chunk)
	chunk.global_transform = xf
	chunk.linear_velocity = rb.linear_velocity
	chunk.angular_velocity = rb.angular_velocity
	chunks.append(chunk)
	var stump_shape: CollisionShape3D = null
	for c in rb.get_children():
		if c is CollisionShape3D:
			stump_shape = c
			break
	_set_capsule(stump_shape, pivot_l, cut_l, r)
	var cs := CollisionShape3D.new()
	chunk.add_child(cs)
	_set_capsule(cs, cut_l, end_l, r)
	rb.mass = maxf(rb.mass * t, 0.3)
	# meshes: sliceable ones are duplicated and clipped from opposite sides,
	# the rest (hats, hair) go to whichever side their origin lies on
	var keep: Array[MeshInstance3D] = []
	var chunk_meshes: Array[MeshInstance3D] = []
	for mi in part_meshes[part]:
		if not is_instance_valid(mi):
			continue
		if _mesh_takes_slice(mi):
			var dup := mi.duplicate() as MeshInstance3D
			chunk.add_child(dup)
			dup.transform = mi.transform
			var bt: Basis = mi.transform.basis.transposed()
			var n_m: Vector3 = bt * n_l
			var d_m: float = n_l.dot(p_l - mi.transform.origin)
			mi.set_instance_shader_parameter("slice_plane", Vector4(n_m.x, n_m.y, n_m.z, d_m))
			dup.set_instance_shader_parameter("slice_plane", Vector4(-n_m.x, -n_m.y, -n_m.z, -d_m))
			keep.append(mi)
			chunk_meshes.append(dup)
		elif n_l.dot(mi.transform.origin - p_l) > 0.0:
			rb.remove_child(mi)
			chunk.add_child(mi)
			chunk_meshes.append(mi)
		else:
			keep.append(mi)
	part_meshes[part] = keep
	# every child joint now hangs from the far half
	for c in Rig.children[part]:
		if joints.has(c):
			var j: Joint3D = joints[c]
			j.node_a = j.get_path_to(chunk)
		for p in Rig.subtree(c):
			severed[p] = true
			var crb: RigidBody3D = parts[p]
			crb.collision_layer = LAYER_DEAD
			crb.collision_mask = MASK_DEAD
			crb.can_sleep = true
			crb.linear_damp = 0.2
			crb.angular_damp = 1.2
			crb.freeze = false
			crb.add_collision_exception_with(chunk)
		joints.erase(c)
	# the two halves may not collide with each other, nor the stump with the rest
	chunk.add_collision_exception_with(rb)
	for p in parts:
		chunk.add_collision_exception_with(parts[p])
	chunk.apply_central_impulse(imp)
	chunk.apply_torque_impulse(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * imp.length() * 0.05)
	rb.apply_central_impulse(-imp * 0.15)
	# the stump loses strength: it flops
	part_strength[part] = minf(part_strength[part], 0.25)
	part_sliced.emit(part, chunk, wpoint, xf.basis * n_l)
	return chunk


func _set_capsule(cs: CollisionShape3D, a: Vector3, b: Vector3, radius: float) -> void:
	if cs == null:
		return
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf((b - a).length() + radius * 2.0, radius * 2.02)
	cs.shape = cap
	cs.transform = Transform3D(_basis_y_to((b - a).normalized() if (b - a).length() > 1e-4 else Vector3.UP), (a + b) * 0.5)


func _ensure_cap_meshes() -> void:
	if _cap_mesh == null:
		_cap_mesh = _make_cap_mesh()
		_bone_mesh = CapsuleMesh.new()
		_bone_mesh.radius = 0.5
		_bone_mesh.height = 2.0


func _cap_radius(part: String) -> float:
	var s: Dictionary = Rig.shapes[part]
	match s.type:
		"capsule":
			return float(s.radius) * scale_factor * 1.05
		"sphere":
			return 0.075 * scale_factor
		_:
			return minf((s.size as Vector3).x, (s.size as Vector3).z) * 0.45 * scale_factor


func _add_cap(on_part: String, pivot_char_space: Vector3, normal_rest: Vector3, radius: float) -> void:
	if _cap_mesh == null:
		_cap_mesh = _make_cap_mesh()
		_bone_mesh = CapsuleMesh.new()
		_bone_mesh.radius = 0.5
		_bone_mesh.height = 2.0
	var rb: RigidBody3D = parts[on_part]
	# rest-space position relative to the part's body origin (pivot + com)
	var local: Vector3 = pivot_char_space - Rig.pivot[on_part] * scale_factor - com[on_part]
	var mi := MeshInstance3D.new()
	mi.mesh = _cap_mesh
	var b := _basis_y_to(normal_rest)
	mi.transform = Transform3D(b.scaled(Vector3(radius, radius, radius)), local + normal_rest * 0.012)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/fx/flesh_cap.png")
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.roughness = 0.25
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	rb.add_child(mi)
	var bone := MeshInstance3D.new()
	bone.mesh = _bone_mesh
	bone.transform = Transform3D(b.scaled(Vector3(radius * 0.28, radius * 0.06, radius * 0.28)), local + normal_rest * 0.02)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.92, 0.88, 0.8)
	bm.roughness = 0.4
	bone.material_override = bm
	rb.add_child(bone)
	part_meshes[on_part].append(mi)


static func _make_cap_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0.5, 0.5))
		st.add_vertex(Vector3(0, 0.02, 0))
		st.set_uv(Vector2(0.5 + cos(a1) * 0.5, 0.5 + sin(a1) * 0.5))
		st.add_vertex(Vector3(cos(a1), 0, sin(a1)))
		st.set_uv(Vector2(0.5 + cos(a0) * 0.5, 0.5 + sin(a0) * 0.5))
		st.add_vertex(Vector3(cos(a0), 0, sin(a0)))
	return st.commit()


# ------------------------------------------------------------------ queries

func part_transform(part: String) -> Transform3D:
	## Current physical pivot transform of a part (world).
	var rb: RigidBody3D = parts[part]
	return rb.global_transform * Transform3D(Basis(), -com[part])


func part_interp_transform(part: String) -> Transform3D:
	var rb: RigidBody3D = parts[part]
	return rb.get_global_transform_interpolated() * Transform3D(Basis(), -com[part])


func center_of_mass() -> Vector3:
	return (parts["pelvis"] as RigidBody3D).global_position


func is_limb_attached(part: String) -> bool:
	return not severed.has(part)


func all_bodies() -> Array:
	return parts.values()


func cleanup_later(seconds: float) -> void:
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		for p in parts:
			var rb: RigidBody3D = parts[p]
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			rb.freeze = true
		for c in chunks:
			if is_instance_valid(c):
				c.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				c.freeze = true)
