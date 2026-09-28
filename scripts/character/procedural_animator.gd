class_name ProceduralAnimator
extends RefCounted
## Computes the target pose of a RagdollBody every physics tick, without any
## pre-made animation clips:
##  * legs: stride-wheel gait with planted feet, predictive foot placement,
##    idle re-stepping and two-bone IK on the real ground (raycasts)
##  * hips/torso: bob, sway, twist, lean from speed/acceleration/turning
##  * arms: two-bone IK to the weapon grip (both hands on the hilt) or
##    natural counter-swing when the hands are free
##  * actions: keyframed sword paths (AttackLibrary), rolls, hit reactions,
##    staggers, get-ups, blocking, idles
## The physical body then tracks these targets, adding weight and wobble.

class Foot:
	var side := 1
	var pos := Vector3.ZERO
	var normal := Vector3.UP
	var yaw := 0.0
	var planted := true
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var t := 1.0
	var swing_time := 0.3
	var lift := 0.12
	var phase_swing := false

var ch: Node3D
var body: RagdollBody
var s := 1.0
var phase := 0.0
var feet: Array[Foot] = []
var initialized := false
var pelvis_drop := 0.0
var lean := Vector2.ZERO          # x = pitch (forward), y = roll (sideways)
var smoothed_speed := 0.0
var prev_vel := Vector3.ZERO
var accel := Vector3.ZERO
var prev_yaw := 0.0
var yaw_rate := 0.0
var head_yaw := 0.0
var head_pitch := 0.0
var breath := 0.0
var grip_char := Transform3D()    # current grip in character space
var grip_weight := 0.0            # 0 hands free .. 1 holding the weapon
var left_on_grip := 1.0
var attack_blend_from := Transform3D()
var extra := {}                   # misc per-frame values (twist/lean/crouch from actions)
var land_squash := 0.0
var space: PhysicsDirectSpaceState3D
var _ray := PhysicsRayQueryParameters3D.new()
var _time := 0.0
var _last_grip_valid := false

# weapon relative to the hand pivot (hand local frame): handle through the fist,
# blade forward, edge down when the arm hangs in rest pose
var hand_to_weapon := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0.0, -0.064, -0.004))


func setup(p_ch: Node3D, p_body: RagdollBody, scale: float) -> void:
	ch = p_ch
	body = p_body
	s = scale
	Rig.ensure_loaded()
	hand_to_weapon.origin *= s
	for side in [1, -1]:
		var f := Foot.new()
		f.side = side
		feet.append(f)
	_ray.collision_mask = 1
	_ray.hit_from_inside = false


# ---------------------------------------------------------------- helpers

func _p(part: String) -> Vector3:
	return Rig.pivot[part] * s


func _ground(at: Vector3, fallback_y: float) -> Array:
	## Returns [position, normal] of the ground under `at`.
	if space == null:
		return [Vector3(at.x, fallback_y, at.z), Vector3.UP]
	_ray.from = Vector3(at.x, at.y + 1.1, at.z)
	_ray.to = Vector3(at.x, at.y - 1.6, at.z)
	var hit := space.intersect_ray(_ray)
	if hit.is_empty():
		var d := WorldData.current
		if d != null:
			var h := d.get_height(at.x, at.z)
			return [Vector3(at.x, h, at.z), d.get_normal(at.x, at.z)]
		return [Vector3(at.x, fallback_y, at.z), Vector3.UP]
	return [hit.position, hit.normal]


static func _basis_from_bone(bone_dir: Vector3, hinge: Vector3) -> Basis:
	## Global basis for a limb segment whose rest direction is -Y and whose
	## rest hinge axis is +X.
	var y := -bone_dir.normalized()
	var x := (hinge - y * hinge.dot(y)).normalized()
	if x.length_squared() < 0.5:
		x = Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.FORWARD
		x = (x - y * x.dot(y)).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Two-bone IK. Returns [mid_point, end_point].
static func solve_ik(root: Vector3, target: Vector3, l1: float, l2: float, pole_dir: Vector3) -> Array:
	var to_t := target - root
	var dist := clampf(to_t.length(), maxf(absf(l1 - l2) + 0.001, 0.02), l1 + l2 - 0.0005)
	var dir := to_t.normalized() if to_t.length_squared() > 1e-8 else Vector3.DOWN
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a := acos(cos_a)
	var bend := pole_dir - dir * pole_dir.dot(dir)
	if bend.length_squared() < 1e-6:
		bend = Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
	bend = bend.normalized()
	var mid := root + (dir * cos(a) + bend * sin(a)) * l1
	var end := root + dir * dist
	return [mid, end]


# ---------------------------------------------------------------- main

func update(delta: float, st: Dictionary) -> void:
	## `st` = state snapshot from the Character (see Character.anim_state()).
	_time += delta
	space = ch.get_world_3d().direct_space_state
	_ray.exclude = st.get("exclude", [])
	var root: Transform3D = st.root
	var vel: Vector3 = st.velocity
	var hvel := Vector3(vel.x, 0.0, vel.z)
	var speed := hvel.length()
	smoothed_speed = lerpf(smoothed_speed, speed, clampf(delta * 8.0, 0.0, 1.0))
	accel = accel.lerp((vel - prev_vel) / maxf(delta, 1e-4), clampf(delta * 6.0, 0.0, 1.0))
	prev_vel = vel
	var yaw := root.basis.get_euler().y
	yaw_rate = lerpf(yaw_rate, wrapf(yaw - prev_yaw, -PI, PI) / maxf(delta, 1e-4), clampf(delta * 6.0, 0.0, 1.0))
	prev_yaw = yaw
	breath += delta
	if not initialized:
		_init_feet(root)
		initialized = true
	var action: String = st.get("action", "")
	var at: float = st.get("action_time", 0.0)

	# ------------------------------------------------ weapon grip target
	var grip_target_w := 0.0
	var key := {}
	var weapon: String = st.get("weapon", "katana")
	if st.get("weapon_in_hand", false):
		grip_target_w = 1.0
		var att: Dictionary = st.get("attack", {})
		if action == "attack" and not att.is_empty():
			key = AttackLibrary.sample(att.keys, at)
		elif action == "block":
			key = AttackLibrary.block_pose(weapon)
		elif action in ["parry", "chiburi", "draw"]:
			var a2 := AttackLibrary.get_attack(action)
			key = AttackLibrary.sample(a2.keys, at)
		elif action == "roll" or action == "knockdown" or action == "getup" or action == "stagger":
			grip_target_w = 0.35 if action == "stagger" else 0.0
			key = AttackLibrary.guard(weapon)
		elif st.get("run_blade_back", false):
			key = AttackLibrary.key(0, Vector3(0.3, 0.92, 0.12), Vector3(0.25, -0.35, 0.9), Vector3(0, -1, 0))
			left_on_grip = move_toward(left_on_grip, 0.0, delta * 6.0)
		else:
			key = AttackLibrary.guard(weapon)
			var br := sin(breath * 1.6) * 0.012
			key = key.duplicate()
			key.pos = key.pos + Vector3(0.0, br, 0.0)
		if not st.get("run_blade_back", false):
			left_on_grip = move_toward(left_on_grip, 1.0 if AttackLibrary.WEAPONS.get(weapon, {}).get("two_handed", true) else 0.0, delta * 5.0)
	elif action in ["chiburi", "draw", "standoff", "iai_ready"]:
		grip_target_w = 1.0
		var hp := AttackLibrary.hilt_pose()
		if action in ["chiburi", "draw"]:
			key = AttackLibrary.sample(AttackLibrary.get_attack(action).keys, at)
		else:
			key = hp
		left_on_grip = move_toward(left_on_grip, 0.0, delta * 6.0)
	grip_weight = move_toward(grip_weight, grip_target_w, delta * 6.0)
	var twist: float = key.get("twist", 0.0)
	var a_lean: float = key.get("lean", 0.0)
	var crouch: float = key.get("crouch", 0.0)
	if not key.is_empty():
		var target_grip := Transform3D(AttackLibrary.grip_basis(key.dir, key.edge), key.pos * s)
		if action == "attack" or action == "parry" or action == "chiburi" or action == "draw":
			grip_char = target_grip if _last_grip_valid else target_grip
			# fast but not instant blend so combos flow into each other
			grip_char = _blend_xf(grip_char, target_grip, 1.0)
		else:
			grip_char = _blend_xf(grip_char, target_grip, clampf(delta * 14.0, 0.0, 1.0)) if _last_grip_valid else target_grip
		_last_grip_valid = true

	# ------------------------------------------------ locomotion lean / hips
	var fwd := -root.basis.z
	var right := root.basis.x
	var local_acc := Vector2(accel.dot(fwd), accel.dot(right))
	var target_lean := Vector2(
		clampf(smoothed_speed * 2.3 + local_acc.x * 1.4, -12.0, 22.0),
		clampf(-yaw_rate * smoothed_speed * 2.2 + local_acc.y * 0.8, -16.0, 16.0))
	if st.get("crouching", false):
		target_lean.x += 14.0
		crouch += 0.2
	if st.get("combat", false):
		crouch += 0.05
	if action == "block":
		crouch += 0.04
	lean = lean.lerp(target_lean, clampf(delta * 6.0, 0.0, 1.0))
	land_squash = move_toward(land_squash, 0.0, delta * 1.6)
	if st.get("landed", 0.0) > 0.0:
		land_squash = maxf(land_squash, float(st.landed))

	# ------------------------------------------------ feet
	var airborne: bool = not st.get("on_floor", true)
	var special_legs := action in ["roll", "knockdown", "sit", "kneel", "getup"] or airborne
	if not special_legs:
		_update_feet(delta, root, hvel, st)
	var cycle := phase * TAU
	var moving := smoothed_speed > 0.35
	var bob := 0.0
	var sway := 0.0
	var hip_twist := 0.0
	if moving and not special_legs:
		var amp := lerpf(0.018, 0.045, clampf((smoothed_speed - 1.5) / 5.0, 0.0, 1.0))
		bob = -amp * (0.5 - 0.5 * cos(cycle * 2.0))
		sway = sin(cycle) * lerpf(0.025, 0.012, clampf(smoothed_speed / 6.0, 0.0, 1.0))
		hip_twist = sin(cycle) * lerpf(7.0, 11.0, clampf(smoothed_speed / 6.0, 0.0, 1.0))
	else:
		sway = sin(breath * 0.7) * 0.006

	# pelvis height: rest minus crouch/bob, lowered further if a foot cannot be reached
	var pelvis_rest := _p("pelvis")
	var drop_needed := 0.0
	var leg_len := (Rig.bone_length("thigh_r") + Rig.bone_length("shin_r")) * s
	if not special_legs:
		for f in feet:
			var hip_local := _p("thigh_r" if f.side > 0 else "thigh_l")
			var hip_world := root * (hip_local + Vector3(0, -crouch * s + bob, 0))
			var ankle := f.pos + Vector3(0, 0.095 * s, 0)
			var dist := hip_world.distance_to(ankle)
			if dist > leg_len * 0.985:
				drop_needed = maxf(drop_needed, (dist - leg_len * 0.985) * 1.02)
	pelvis_drop = lerpf(pelvis_drop, drop_needed, clampf(delta * 14.0, 0.0, 1.0))
	var pelvis_y := pelvis_rest.y - crouch * s + bob - pelvis_drop - land_squash * 0.12 * s

	# ------------------------------------------------ root/pelvis transform
	var pelvis_basis := Basis.from_euler(Vector3(deg_to_rad(-lean.x * 0.25), deg_to_rad(hip_twist + twist * 0.35), deg_to_rad(lean.y * 0.4)))
	var pelvis_pos := Vector3(sway * s, pelvis_y, 0.0)
	var root_rot := Basis()
	var root_pivot := Vector3.ZERO
	if action == "roll":
		var rt := clampf(at / 0.62, 0.0, 1.0)
		var ang := AttackLibrary.ease(clampf((rt - 0.06) / 0.84, 0.0, 1.0), "inout") * TAU
		var dirv: Vector3 = st.get("roll_dir", fwd)
		var local_dir := root.basis.inverse() * dirv
		local_dir.y = 0.0
		local_dir = local_dir.normalized() if local_dir.length() > 0.01 else Vector3.FORWARD
		var axis := Vector3.UP.cross(local_dir).normalized()
		root_rot = Basis(axis, ang)
		root_pivot = Vector3(0, 0.52 * s, 0)
		pelvis_pos.y = lerpf(pelvis_rest.y, 0.55 * s, sin(rt * PI))
	var pelvis_local := Transform3D(pelvis_basis, pelvis_pos)
	if action == "roll":
		pelvis_local = Transform3D(root_rot, root_pivot) * Transform3D(Basis(), -root_pivot) * pelvis_local
	if action == "sit" or action == "kneel":
		pelvis_local.origin.y = (0.26 if action == "sit" else 0.48) * s
	if action == "getup":
		pelvis_local.origin.y = lerpf(0.3 * s, pelvis_y, AttackLibrary.ease(clampf(at / 0.9, 0.0, 1.0), "inout"))
		pelvis_local.basis = Basis.from_euler(Vector3(deg_to_rad(lerpf(55.0, 0.0, clampf(at / 0.9, 0.0, 1.0))), 0, 0)) * pelvis_local.basis
	var pelvis_w := root * pelvis_local

	# ------------------------------------------------ spine & head
	var spine_pitch := lean.x * 0.55 + a_lean
	var spine_roll := -lean.y * 0.4
	var chest_twist := -hip_twist * 1.3 + twist * 0.65
	var breathing := sin(breath * 1.6) * 1.2
	var hit_dir: Vector3 = st.get("hit_dir", Vector3.ZERO)
	var hit_env := 0.0
	if action == "hit":
		hit_env = sin(clampf(at / 0.35, 0.0, 1.0) * PI)
	elif action == "stagger":
		hit_env = sin(clampf(at / 0.9, 0.0, 1.0) * PI) * 1.8
	var local_hit := root.basis.inverse() * hit_dir
	spine_pitch -= local_hit.z * -20.0 * hit_env
	spine_roll += local_hit.x * 16.0 * hit_env
	if action == "roll":
		spine_pitch += 35.0
	if action == "heal":
		spine_pitch += 18.0 * sin(clampf(at, 0.0, 1.0) * PI)
	if action == "kneel" or action == "pray":
		spine_pitch += 22.0
	if action == "getup":
		spine_pitch += lerpf(30.0, 0.0, clampf(at / 0.9, 0.0, 1.0))
	var belly_rot := Basis.from_euler(Vector3(deg_to_rad(-spine_pitch * 0.45 + breathing * 0.3), deg_to_rad(chest_twist * 0.4), deg_to_rad(spine_roll * 0.5)))
	var chest_rot := Basis.from_euler(Vector3(deg_to_rad(-spine_pitch * 0.55 - breathing), deg_to_rad(chest_twist * 0.6), deg_to_rad(spine_roll * 0.5)))
	var belly_w := pelvis_w * Transform3D(Basis(), _p("belly") - _p("pelvis")) * Transform3D(belly_rot, Vector3.ZERO)
	var chest_w := belly_w * Transform3D(Basis(), _p("chest") - _p("belly")) * Transform3D(chest_rot, Vector3.ZERO)
	# head look-at (clamped), compensating the body lean
	var look: Variant = st.get("look_target", null)
	var t_yaw := 0.0
	var t_pitch := 0.0
	var head_base := chest_w * (_p("head") - _p("chest") + Vector3(0, 0.16 * s, 0))
	if look is Vector3:
		var to_t: Vector3 = chest_w.basis.inverse() * ((look as Vector3) - head_base)
		t_yaw = clampf(atan2(-to_t.x, -to_t.z), -1.1, 1.1)
		t_pitch = clampf(atan2(to_t.y, Vector2(to_t.x, to_t.z).length()), -0.7, 0.6)
	if action == "roll":
		t_pitch = -0.8
	if action == "pray" or action == "heal":
		t_pitch = -0.45
	t_pitch -= deg_to_rad(hit_env * local_hit.z * -10.0)
	head_yaw = lerpf(head_yaw, t_yaw, clampf(delta * 7.0, 0.0, 1.0))
	head_pitch = lerpf(head_pitch, t_pitch, clampf(delta * 7.0, 0.0, 1.0))
	var head_rot := Basis.from_euler(Vector3(head_pitch, head_yaw, 0.0))
	var head_w := chest_w * Transform3D(Basis(), _p("head") - _p("chest")) * Transform3D(head_rot, Vector3.ZERO)

	var T := body.targets
	T["pelvis"] = pelvis_w
	T["belly"] = belly_w
	T["chest"] = chest_w
	T["head"] = head_w

	# ------------------------------------------------ legs
	if special_legs:
		_legs_fk(root, pelvis_w, action, at, st, airborne)
	else:
		for f in feet:
			_leg_ik(root, pelvis_w, f)

	# ------------------------------------------------ arms
	var grip_w := root * grip_char
	for side in [1, -1]:
		var sfx := "_r" if side > 0 else "_l"
		var shoulder_w := chest_w * (_p("upper_arm" + sfx) - _p("chest"))
		var free := _free_arm(root, chest_w, side, action, at, st)
		var hold_w := grip_weight
		if side < 0:
			hold_w *= left_on_grip
		if hold_w > 0.01:
			var gw := grip_w
			if side < 0:
				var off: float = AttackLibrary.WEAPONS.get(weapon, {}).get("left_hand", -0.16)
				gw = grip_w * Transform3D(Basis(), Vector3(0, off * s, 0))
			var hand_xf := gw * hand_to_weapon.affine_inverse()
			var hand_target := free[2].interpolate_with(hand_xf, hold_w) as Transform3D
			_arm_ik(chest_w, shoulder_w, hand_target, side)
		else:
			T["upper_arm" + sfx] = free[0]
			T["forearm" + sfx] = free[1]
			T["hand" + sfx] = free[2]


func _blend_xf(a: Transform3D, b: Transform3D, k: float) -> Transform3D:
	return a.interpolate_with(b, clampf(k, 0.0, 1.0))


# ---------------------------------------------------------------- legs

func _init_feet(root: Transform3D) -> void:
	for f in feet:
		var p := root * (Vector3(0.12 * f.side * s, 0.0, 0.0))
		var g := _ground(p, root.origin.y)
		f.pos = g[0]
		f.normal = g[1]
		f.yaw = root.basis.get_euler().y
		f.planted = true
		f.t = 1.0


func _ideal_foot(root: Transform3D, f: Foot, st: Dictionary) -> Vector3:
	var off := Vector3(0.12 * f.side, 0.0, 0.0)
	if st.get("combat", false) or st.get("weapon_in_hand", false):
		# kendo-like stance: right foot forward, left foot back
		off = Vector3(0.15 * f.side, 0.0, -0.17 if f.side > 0 else 0.15)
	if st.get("action", "") == "block":
		off.z += 0.05
	return root * (off * s)


func _update_feet(delta: float, root: Transform3D, hvel: Vector3, st: Dictionary) -> void:
	var speed := hvel.length()
	var yaw := root.basis.get_euler().y
	if speed > 0.35:
		var sprintiness := clampf((speed - 1.6) / 5.5, 0.0, 1.0)
		var stride := lerpf(1.25, 3.1, sprintiness) * s
		var duty := lerpf(0.6, 0.36, sprintiness)
		var cycle_time := stride / maxf(speed, 0.1)
		phase = fposmod(phase + speed * delta / stride, 1.0)
		for f in feet:
			var lp := fposmod(phase + (0.0 if f.side > 0 else 0.5), 1.0)
			var swinging := lp >= duty
			if swinging and not f.phase_swing:
				f.from = f.pos
				f.planted = false
			f.phase_swing = swinging
			if swinging:
				var t := (lp - duty) / (1.0 - duty)
				var remaining := (1.0 - t) * (1.0 - duty) * cycle_time + duty * cycle_time * 0.5
				var ideal := root.origin + hvel * remaining + root.basis.x * (0.12 * f.side * s)
				var g := _ground(ideal, root.origin.y)
				f.to = g[0]
				f.normal = f.normal.slerp(g[1], 0.3)
				var e := AttackLibrary.ease(t, "inout")
				var lift := lerpf(0.1, 0.22, sprintiness) * s
				f.pos = f.from.lerp(f.to, e) + Vector3(0, lift * sin(t * PI), 0)
				f.yaw = lerp_angle(f.yaw, yaw, clampf(delta * 12.0, 0.0, 1.0))
				f.t = t
			else:
				if not f.planted:
					f.pos = f.to
					f.planted = true
				f.t = 1.0
	else:
		# standing: re-step feet that are too far from where they should be
		var busy := false
		for f in feet:
			if not f.planted:
				busy = true
		for f in feet:
			if f.planted:
				f.phase_swing = false
				var ideal := _ideal_foot(root, f, st)
				var off := (f.pos - ideal)
				off.y = 0.0
				var turned := absf(wrapf(f.yaw - yaw, -PI, PI))
				if not busy and (off.length() > 0.2 * s or turned > 0.6):
					var g := _ground(ideal, root.origin.y)
					f.from = f.pos
					f.to = g[0]
					f.normal = g[1]
					f.t = 0.0
					f.swing_time = 0.24
					f.planted = false
					busy = true
			else:
				f.t = minf(1.0, f.t + delta / f.swing_time)
				var e := AttackLibrary.ease(f.t, "inout")
				f.pos = f.from.lerp(f.to, e) + Vector3(0, 0.09 * s * sin(f.t * PI), 0)
				f.yaw = lerp_angle(f.yaw, yaw, clampf(delta * 10.0, 0.0, 1.0))
				if f.t >= 1.0:
					f.pos = f.to
					f.planted = true
		phase = lerpf(phase, 0.0 if phase < 0.5 else 1.0, 0.0)
	# planted feet that got dragged too far (knockback, sliding) re-step next frame
	for f in feet:
		if f.planted:
			var d := Vector2(f.pos.x - root.origin.x, f.pos.z - root.origin.z).length()
			if d > 0.9 * s:
				var g := _ground(_ideal_foot(root, f, st), root.origin.y)
				f.pos = g[0]


func _leg_ik(root: Transform3D, pelvis_w: Transform3D, f: Foot) -> void:
	var sfx := "_r" if f.side > 0 else "_l"
	var hip := pelvis_w * (_p("thigh" + sfx) - _p("pelvis"))
	var ankle := f.pos + Vector3(0, 0.095 * s, 0)
	var l1 := Rig.bone_length("thigh" + sfx) * s
	var l2 := Rig.bone_length("shin" + sfx) * s
	var fwd := -root.basis.z
	var pole := fwd + root.basis.x * 0.12 * f.side
	var r := solve_ik(hip, ankle, l1, l2, pole)
	var knee: Vector3 = r[0]
	var ank: Vector3 = r[1]
	var d1 := knee - hip
	var d2 := ank - knee
	var hinge := d1.cross(d2)
	if hinge.length_squared() < 1e-7:
		hinge = -root.basis.x
	# legs bend the other way round than arms: rest hinge maps to -X
	var h := -hinge.normalized()
	var T := body.targets
	T["thigh" + sfx] = Transform3D(_basis_from_bone(d1, h), hip)
	T["shin" + sfx] = Transform3D(_basis_from_bone(d2, h), knee)
	# foot: yaw of the foot, aligned to the ground, toes lifted mid-swing
	var toe_pitch := 0.0
	if not f.planted:
		toe_pitch = sin(f.t * PI) * 0.35 - 0.15 * (1.0 - f.t)
	var fb := Basis.from_euler(Vector3(toe_pitch, f.yaw, 0.0))
	var n := f.normal if f.normal.y > 0.5 else Vector3.UP
	var align := Quaternion(Vector3.UP, n)
	fb = Basis(align) * fb
	T["foot" + sfx] = Transform3D(fb, ank)


func _legs_fk(root: Transform3D, pelvis_w: Transform3D, action: String, at: float, st: Dictionary, airborne: bool) -> void:
	var T := body.targets
	for side in [1, -1]:
		var sfx := "_r" if side > 0 else "_l"
		var thigh_pitch := 0.0
		var knee := 0.0
		var spread := 0.0
		if action == "roll":
			thigh_pitch = 105.0
			knee = -125.0
		elif action == "sit":
			thigh_pitch = 80.0
			knee = -95.0
			spread = 28.0 * side
		elif action == "kneel" or action == "pray":
			thigh_pitch = 80.0 if side > 0 else 5.0
			knee = -90.0 if side > 0 else -110.0
		elif action == "getup":
			var k := clampf(at / 0.9, 0.0, 1.0)
			thigh_pitch = lerpf(85.0, 5.0, k) if side > 0 else lerpf(10.0, 2.0, k)
			knee = lerpf(-95.0, -8.0, k) if side > 0 else lerpf(-110.0, -6.0, k)
		elif airborne:
			var up := clampf(-(st.velocity as Vector3).y * 0.06, -1.0, 1.0)
			thigh_pitch = 35.0 + 15.0 * side * sin(breath * 5.0) - up * 20.0
			knee = -55.0
		var hip := pelvis_w * (_p("thigh" + sfx) - _p("pelvis"))
		var thigh_rot := pelvis_w.basis * Basis.from_euler(Vector3(deg_to_rad(thigh_pitch), 0.0, deg_to_rad(spread)))
		var thigh_xf := Transform3D(thigh_rot, hip)
		var shin_xf := thigh_xf * Transform3D(Basis(), _p("shin" + sfx) - _p("thigh" + sfx)) * Transform3D(Basis.from_euler(Vector3(deg_to_rad(knee), 0, 0)), Vector3.ZERO)
		var foot_xf := shin_xf * Transform3D(Basis(), _p("foot" + sfx) - _p("shin" + sfx)) * Transform3D(Basis.from_euler(Vector3(deg_to_rad(-knee * 0.3 - thigh_pitch * 0.2), 0, 0)), Vector3.ZERO)
		T["thigh" + sfx] = thigh_xf
		T["shin" + sfx] = shin_xf
		T["foot" + sfx] = foot_xf
	# keep the foot planting state sane for when the action ends
	for f in feet:
		f.planted = true
		f.phase_swing = false
		f.pos = (T["foot_r" if f.side > 0 else "foot_l"] as Transform3D).origin - Vector3(0, 0.095 * s, 0)


# ---------------------------------------------------------------- arms

func _free_arm(root: Transform3D, chest_w: Transform3D, side: int, action: String, at: float, st: Dictionary) -> Array:
	## FK arm pose when the hand is not on the weapon: counter-swing while
	## moving, relaxed idle, tucked during rolls, flailing when staggered.
	var sfx := "_r" if side > 0 else "_l"
	var cycle := phase * TAU
	var amp := lerpf(12.0, 50.0, clampf((smoothed_speed - 1.0) / 6.0, 0.0, 1.0)) if smoothed_speed > 0.35 else 0.0
	var swing := sin(cycle + (PI if side > 0 else 0.0)) * amp
	var elbow := lerpf(12.0, 75.0, clampf((smoothed_speed - 1.0) / 6.0, 0.0, 1.0)) + maxf(0.0, swing) * 0.3
	var abduct := 8.0 + sin(breath * 1.6) * 1.0
	if action == "roll":
		swing = 50.0
		elbow = 110.0
		abduct = 5.0
	elif action == "stagger" or action == "hit":
		var k := sin(clampf(at / (0.9 if action == "stagger" else 0.35), 0.0, 1.0) * PI)
		swing = 40.0 * k
		abduct = 8.0 + 45.0 * k
		elbow = 30.0 + 40.0 * k
	elif action == "heal" and side < 0:
		swing = 55.0
		elbow = 110.0
		abduct = -10.0
	elif action == "pray":
		swing = 45.0
		elbow = 105.0
		abduct = -25.0
	elif action == "sit":
		swing = 35.0
		elbow = 60.0
	elif not st.get("on_floor", true):
		swing = 30.0
		abduct = 35.0
		elbow = 40.0
	elif st.get("crouching", false):
		swing *= 0.5
		elbow += 20.0
	var shoulder := chest_w * (_p("upper_arm" + sfx) - _p("chest"))
	var ua_rot := chest_w.basis * Basis.from_euler(Vector3(deg_to_rad(swing), 0.0, deg_to_rad(abduct * side)))
	var ua := Transform3D(ua_rot, shoulder)
	var fa := ua * Transform3D(Basis(), _p("forearm" + sfx) - _p("upper_arm" + sfx)) * Transform3D(Basis.from_euler(Vector3(deg_to_rad(elbow), 0, 0)), Vector3.ZERO)
	var hd := fa * Transform3D(Basis(), _p("hand" + sfx) - _p("forearm" + sfx)) * Transform3D(Basis.from_euler(Vector3(deg_to_rad(8.0), 0, 0)), Vector3.ZERO)
	return [ua, fa, hd]


func _arm_ik(chest_w: Transform3D, shoulder: Vector3, hand_xf: Transform3D, side: int) -> void:
	var sfx := "_r" if side > 0 else "_l"
	var l1 := Rig.bone_length("upper_arm" + sfx) * s
	var l2 := Rig.bone_length("forearm" + sfx) * s
	var down := -chest_w.basis.y
	var back := chest_w.basis.z
	var out := chest_w.basis.x * side
	var pole := down * 0.6 + back * 0.35 + out * 0.55
	var r := solve_ik(shoulder, hand_xf.origin, l1, l2, pole)
	var elbow: Vector3 = r[0]
	var wrist: Vector3 = r[1]
	var d1 := elbow - shoulder
	var d2 := wrist - elbow
	var hinge := d1.cross(d2)
	if hinge.length_squared() < 1e-7:
		hinge = chest_w.basis.x
	var T := body.targets
	T["upper_arm" + sfx] = Transform3D(_basis_from_bone(d1, hinge.normalized()), shoulder)
	T["forearm" + sfx] = Transform3D(_basis_from_bone(d2, hinge.normalized()), elbow)
	T["hand" + sfx] = Transform3D(hand_xf.basis, wrist)


## World transform of the weapon grip (for the weapon node while held).
func grip_world(root: Transform3D) -> Transform3D:
	return root * grip_char
