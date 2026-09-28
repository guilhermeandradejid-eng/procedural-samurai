class_name Weapon
extends Node3D
## A melee weapon carried by a Character: lives on the physical hand while
## drawn (so it swings with the ragdoll) or on the hip while sheathed.
## During an attack's active window it sweeps rays between the previous and
## current positions of points along the blade, so fast swings never tunnel.

signal struck(target: Node, part: String, point: Vector3, direction: Vector3)

const HIT_MASK := RagdollBody.LAYER_ALIVE

var kind := "katana"
var ch: Node3D
var body: RagdollBody
var animator: ProceduralAnimator
var model: Node3D
var saya: Node3D
var blade_mat: ShaderMaterial
var trail: SlashTrail
var blood := 0.0
var in_hand := false
var sweeping := false
var dropped := false
var hit_set := {}
var _prev_pts: Array[Vector3] = []
var _query := PhysicsRayQueryParameters3D.new()
var _glint := 0.0
var data := {}


func setup(p_ch: Node3D, p_body: RagdollBody, p_anim: ProceduralAnimator, p_kind: String) -> void:
	ch = p_ch
	body = p_body
	animator = p_anim
	kind = p_kind
	data = AttackLibrary.WEAPONS.get(kind, AttackLibrary.WEAPONS["katana"])
	var scene: Node3D = (load("res://assets/models/weapons/%s.glb" % kind) as PackedScene).instantiate()
	model = scene.get_node_or_null(kind) as Node3D
	blade_mat = ShaderMaterial.new()
	blade_mat.shader = load("res://shaders/blade.gdshader")
	if model:
		model.owner = null
		scene.remove_child(model)
		model.transform = Transform3D.IDENTITY
		add_child(model)
		MaterialLibrary.apply(model, {"blade": blade_mat})
	var sy := scene.get_node_or_null("saya") as Node3D
	if sy:
		sy.owner = null
		scene.remove_child(sy)
		saya = sy
		MaterialLibrary.apply(saya)
	scene.free()
	scale = Vector3.ONE * body.scale_factor
	trail = SlashTrail.new()
	trail.name = "Trail"
	ch.add_child.call_deferred(trail)
	_query.collision_mask = HIT_MASK
	_query.hit_from_inside = true
	_query.collide_with_areas = false
	var ex: Array[RID] = []
	for rb in body.all_bodies():
		ex.append((rb as RigidBody3D).get_rid())
	_query.exclude = ex
	if saya:
		_attach_saya()


func _attach_saya() -> void:
	var pelvis: RigidBody3D = body.parts["pelvis"]
	var s := body.scale_factor
	if saya.get_parent():
		saya.get_parent().remove_child(saya)
	pelvis.add_child(saya)
	var b := AttackLibrary.grip_basis(AttackLibrary.SHEATH_DIR, Vector3(0, 1, 0))
	var mouth := (AttackLibrary.SHEATH_GRIP + b.y * 0.03) * s
	saya.transform = Transform3D(b.scaled(Vector3.ONE * s), mouth - Rig.pivot["pelvis"] * s - body.com["pelvis"])


func _reparent_to(rb: RigidBody3D, local: Transform3D) -> void:
	if get_parent():
		get_parent().remove_child(self)
	rb.add_child(self)
	transform = local
	scale = Vector3.ONE * body.scale_factor


## Puts the weapon in the right hand.
func hold() -> void:
	if dropped:
		return
	var rb: RigidBody3D = body.parts["hand_r"]
	var local := Transform3D(Basis(), -body.com["hand_r"]) * animator.hand_to_weapon
	_reparent_to(rb, local)
	in_hand = true


## Slides the weapon into the scabbard at the left hip.
func sheathe() -> void:
	if dropped:
		return
	var pelvis: RigidBody3D = body.parts["pelvis"]
	var s := body.scale_factor
	if kind == "katana":
		var b := AttackLibrary.grip_basis(AttackLibrary.SHEATH_DIR, Vector3(0, 1, 0))
		var pos: Vector3 = AttackLibrary.SHEATH_GRIP * s
		_reparent_to(pelvis, Transform3D(b, pos - Rig.pivot["pelvis"] * s - body.com["pelvis"]))
	else:
		# big weapons are slung on the back
		var chest: RigidBody3D = body.parts["chest"]
		var b := AttackLibrary.grip_basis(Vector3(0.35, -0.9, 0.2), Vector3(0, 0, 1))
		var pos := Vector3(0.1, 1.45, 0.2) * s
		_reparent_to(chest, Transform3D(b, pos - Rig.pivot["chest"] * s - body.com["chest"]))
	in_hand = false


## Drops the weapon as a free rigid body (disarm / death).
func drop(impulse := Vector3.ZERO) -> void:
	if dropped:
		return
	dropped = true
	in_hand = false
	sweeping = false
	var xf := global_transform
	var rb := RigidBody3D.new()
	rb.mass = float(data.get("mass", 1.2))
	rb.collision_layer = 1 << 4
	rb.collision_mask = 1 | (1 << 3) | (1 << 4)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var length: float = float(data.get("blade_end", 0.75)) + 0.25
	cap.radius = 0.025 * body.scale_factor
	cap.height = length * body.scale_factor
	cs.shape = cap
	cs.position = Vector3(0, (length * 0.5 - 0.25) * body.scale_factor, 0)
	rb.add_child(cs)
	ch.get_tree().current_scene.add_child(rb)
	rb.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)
	if get_parent():
		get_parent().remove_child(self)
	rb.add_child(self)
	transform = Transform3D(Basis.from_scale(Vector3.ONE * body.scale_factor), Vector3.ZERO)
	rb.apply_central_impulse(impulse)
	rb.apply_torque_impulse(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 0.6)


func blade_points(n := 6) -> Array[Vector3]:
	var pts: Array[Vector3] = []
	var a: float = data.get("blade_start", 0.05)
	var b: float = data.get("blade_end", 0.75)
	var xf := global_transform
	for i in n:
		var t := float(i) / float(n - 1)
		pts.append(xf * Vector3(0.0, lerpf(a, b, t), 0.0))
	return pts


func tip() -> Vector3:
	return global_transform * Vector3(0.0, float(data.get("blade_end", 0.75)), 0.0)


func begin_sweep() -> void:
	sweeping = true
	hit_set.clear()
	_prev_pts = blade_points()
	trail.active = true


func end_sweep() -> void:
	sweeping = false
	trail.active = false


func set_blood(v: float) -> void:
	blood = clampf(v, 0.0, 1.0)
	blade_mat.set_shader_parameter("blood", blood)


func add_blood(v: float) -> void:
	set_blood(blood + v)


func glint(color: Color, strength := 1.0) -> void:
	_glint = strength
	blade_mat.set_shader_parameter("glint_color", color)


func physics_update(delta: float) -> void:
	if _glint > 0.0:
		_glint = maxf(0.0, _glint - delta * 1.6)
		blade_mat.set_shader_parameter("glint", _glint)
		blade_mat.set_shader_parameter("glint_pos", fmod(Time.get_ticks_msec() / 400.0, 1.2) - 0.1)
	if not in_hand:
		return
	var pts := blade_points()
	if trail.active or sweeping:
		trail.push(pts[1], pts[pts.size() - 1])
	if not sweeping:
		return
	var space := get_world_3d().direct_space_state
	var n := pts.size()
	for i in n:
		if _prev_pts.size() != n:
			break
		var from := _prev_pts[i]
		var to := pts[i]
		if from.distance_squared_to(to) < 1e-6:
			continue
		_query.from = from
		_query.to = to
		var hit := space.intersect_ray(_query)
		if hit.is_empty():
			continue
		var col: Object = hit.collider
		if not col.has_meta("character"):
			continue
		var target: Node = col.get_meta("character")
		if target == ch or hit_set.has(target):
			continue
		hit_set[target] = true
		struck.emit(target, String(col.get_meta("part")), hit.position, (to - from).normalized())
	# also test the blade itself this frame (thrusts / point-blank)
	_query.from = pts[0]
	_query.to = pts[n - 1]
	var h2 := space.intersect_ray(_query)
	if not h2.is_empty() and h2.collider.has_meta("character"):
		var t2: Node = h2.collider.get_meta("character")
		if t2 != ch and not hit_set.has(t2):
			hit_set[t2] = true
			var mv := (pts[n - 1] - _prev_pts[n - 1]) if _prev_pts.size() == n else (pts[n - 1] - pts[0])
			struck.emit(t2, String(h2.collider.get_meta("part")), h2.position, mv.normalized())
	_prev_pts = pts
