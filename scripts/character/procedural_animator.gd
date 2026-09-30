class_name ProceduralAnimator
extends RefCounted
## Computes the target pose of a RagdollBody every physics tick from baked
## skeletal animation clips (assets/motion, made by tools/motion from retargeted
## motion capture, authored key poses or text-to-motion output) plus a layer of
## runtime adaptation:
##  * locomotion: idle / walk / run / sprint clips blended by speed on a shared
##    gait phase, with stride warping and orientation warping (strafing and
##    backpedalling keep the torso facing the target)
##  * actions: attacks, blocks, rolls, reactions... are clips selected by the
##    character's action; switching clips uses inertialisation (the previous
##    pose's offset decays) instead of a freeze-frame crossfade
##  * feet: the clip's ground contacts pin the feet to the real terrain (raycasts)
##    with two-bone IK, idle re-stepping and reach-limited pelvis drop
##  * arms: FK from the clip, or two-bone IK to the two-hand weapon grip
##  * head: look-at layered over the clip
## The physical ragdoll then tracks these targets, adding weight and wobble.

const HEAD := 3
const CHEST := 2
const PELVIS := 0

class Foot:
	var side := 1
	var part := 12               # rig index of the foot part
	var pin := Vector3.ZERO      # ground point under the ankle while planted
	var pin_yaw := 0.0
	var pin_normal := Vector3.UP
	var locked := false
	var lock_w := 0.0            # 0..1 how much the pin overrides the clip
	var was_contact := false
	var stepping := false        # idle re-step in progress
	var step_t := 0.0
	var step_from := Vector3.ZERO
	var step_to := Vector3.ZERO
	var step_yaw := 0.0
	var ankle := Vector3.ZERO    # last solved ankle target (world)
	var swing_height := 0.0

var ch: Node3D
var body: RagdollBody
var s := 1.0
var feet: Array[Foot] = []
var initialized := false
var space: PhysicsDirectSpaceState3D
var grip_char := Transform3D()    # weapon grip in character space (for the weapon node)
var grip_weight := 0.0
var extra := {}
var land_squash := 0.0
var breath := 0.0
var head_yaw := 0.0
var head_pitch := 0.0
var look_w := 0.0
var smoothed_speed := 0.0
var pelvis_drop := 0.0
var prev_yaw := 0.0
var yaw_rate := 0.0

# weapon relative to the hand pivot (hand local frame): handle through the fist,
# blade forward, edge down when the arm hangs in rest pose
var hand_to_weapon := Transform3D(Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)), Vector3(0.0, -0.064, -0.004))

var _ray := PhysicsRayQueryParameters3D.new()
var _time := 0.0
var _parent: Array[int] = []
var _off: Array[Vector3] = []          # rest offset of every part from its parent (scaled)
var _w: Array[Transform3D] = []        # world transform of every part this frame
var _base := MotionPose.new()          # pose sampled from the clips
var _final := MotionPose.new()         # base + inertialisation + overlays
var _tmp := MotionPose.new()
var _tmp2 := MotionPose.new()
var _last := MotionPose.new()          # last base pose (source of the next transition offset)
var _key := ""
var _off_rot: Array[Quaternion] = []
var _off_pelvis := Vector3.ZERO
var _off_grip := {"active": false, "pos": Vector3.ZERO, "blade": Vector3.UP, "edge": Vector3.FORWARD, "w": 0.0, "left": 1.0}
var _off_t := 99.0
var _off_half := 0.1
var _phase := 0.0
var _theta := 0.0                      # smoothed movement direction relative to facing
var _backward := false
var _gait_rate := 1.0
var _stride_k := 1.0
var _grip_def := {"pos": Vector3.ZERO, "blade": Vector3.UP, "edge": Vector3.FORWARD, "w": 0.0, "left": 1.0}
var _left_grip := 1.0
var _clip_grip_active := false
var _legacy_grip := false
var _legacy_xf := Transform3D()
var _leg_len := 0.6
var _last_action := ""


func setup(p_ch: Node3D, p_body: RagdollBody, scale: float) -> void:
	ch = p_ch
	body = p_body
	s = scale
	Rig.ensure_loaded()
	hand_to_weapon.origin = Vector3(0.0, -float(Rig.meta.get("hand_grip_drop", 0.064)), -0.006) * s
	_parent.resize(MotionPose.N)
	_off.resize(MotionPose.N)
	_w.resize(MotionPose.N)
	_off_rot.resize(MotionPose.N)
	for i in MotionPose.N:
		var part: String = Rig.ORDER[i]
		var par: String = Rig.parent[part]
		_parent[i] = Rig.ORDER.find(par) if par != "" else -1
		_off[i] = (Rig.pivot[part] - Rig.pivot[par]) * s if par != "" else Vector3.ZERO
		_w[i] = Transform3D.IDENTITY
		_off_rot[i] = Quaternion.IDENTITY
	for side in [1, -1]:
		var f := Foot.new()
		f.side = side
		f.part = Rig.ORDER.find("foot_r" if side > 0 else "foot_l")
		feet.append(f)
	_leg_len = (Rig.bone_length("thigh_r") + Rig.bone_length("shin_r")) * s
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


## Two-bone IK. Returns [mid_point, end_point, hinge_axis]; the hinge axis is
## the normal of the bend plane (stable even when the limb is nearly straight).
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
	return [mid, end, bend.cross(dir).normalized()]


# ---------------------------------------------------------------- main

func update(delta: float, st: Dictionary) -> void:
	## `st` = state snapshot from the Character (see Character.anim_state()).
	_time += delta
	breath += delta
	space = ch.get_world_3d().direct_space_state
	_ray.exclude = st.get("exclude", [])
	var root: Transform3D = st.root
	var vel: Vector3 = st.velocity
	var hvel := Vector3(vel.x, 0.0, vel.z)
	var speed := hvel.length()
	smoothed_speed = lerpf(smoothed_speed, speed, clampf(delta * 8.0, 0.0, 1.0))
	var yaw := root.basis.get_euler().y
	var dyaw := wrapf(yaw - prev_yaw, -PI, PI)
	prev_yaw = yaw
	yaw_rate = lerpf(yaw_rate, dyaw / maxf(delta, 1e-4), clampf(delta * 6.0, 0.0, 1.0))
	var action: String = st.get("action", "")
	if not initialized:
		_reset(root)
		initialized = true
	if absf(dyaw) > 0.05 and action == "attack" and (st.get("attack", {}) as Dictionary).has("spin"):
		# a spin carries the planted feet round with the body instead of dragging them
		var spin_basis := Basis(Vector3.UP, dyaw)
		for f in feet:
			f.pin = root.origin + spin_basis * (f.pin - root.origin)
			f.step_from = root.origin + spin_basis * (f.step_from - root.origin)
			f.step_to = root.origin + spin_basis * (f.step_to - root.origin)
			f.pin_yaw += dyaw
			f.step_yaw += dyaw
	var airborne: bool = not st.get("on_floor", true)

	# ------------------------------------------------ pose from clips
	var sel := _select(st, root, hvel)
	_sample(delta, st, sel, root, hvel, airborne)
	# inertialisation: the offset between the previous and the new pose decays away
	_off_t += delta
	_apply_offset(_base, _final)
	_last.copy_from(_final)
	# torso motion is damped while the hands hold a guard
	var armed_guard: bool = st.get("weapon_in_hand", false) and sel.get("loco", false)
	if armed_guard:
		for i in [1, 2]:
			_final.rot[i] = Quaternion.IDENTITY.slerp(_final.rot[i], 0.55)
	# land squash: knees give way when hitting the ground
	land_squash = move_toward(land_squash, 0.0, delta * 1.6)
	if st.get("landed", 0.0) > 0.0:
		land_squash = maxf(land_squash, float(st.landed))
	_final.pelvis.y -= land_squash * 0.12
	# orientation warping (only for locomotion clips)
	var warp := _orientation_warp(sel, root, hvel, delta)
	if warp != 0.0:
		_final.rot[PELVIS] = Quaternion(Vector3.UP, warp) * _final.rot[PELVIS]
		_final.rot[1] = Quaternion(Vector3.UP, -warp * 0.45) * _final.rot[1]
		_final.rot[CHEST] = Quaternion(Vector3.UP, -warp * 0.55) * _final.rot[CHEST]
		_final.pelvis = Quaternion(Vector3.UP, warp) * _final.pelvis
	# banking: runners lean into their turns
	if sel.get("loco", false) and _key != "loco_air" and smoothed_speed > 1.2:
		var bank := clampf(atan(0.35 * smoothed_speed * yaw_rate / 9.8), -0.32, 0.32)
		if absf(bank) > 0.005:
			_final.rot[PELVIS] = Quaternion(Vector3.BACK, bank * 0.5) * _final.rot[PELVIS]
			_final.rot[CHEST] = Quaternion(Vector3.BACK, bank * 0.5) * _final.rot[CHEST]
	# rolls go in the roll direction whatever the body faces
	if action == "roll":
		var rd: Vector3 = st.get("roll_dir", -root.basis.z)
		var local_dir := root.basis.inverse() * rd
		local_dir.y = 0.0
		if local_dir.length() > 0.01:
			var ang := atan2(-local_dir.x, -local_dir.z)
			_final.rot[PELVIS] = Quaternion(Vector3.UP, ang) * _final.rot[PELVIS]
			_final.pelvis = Quaternion(Vector3.UP, ang) * _final.pelvis

	# ------------------------------------------------ weapon grip selection
	_choose_grip(delta, root, st, sel)

	# ------------------------------------------------ forward kinematics
	var pelvis_local := Transform3D(Basis(_final.rot[PELVIS]), _final.pelvis * s)
	_w[PELVIS] = root * pelvis_local
	for i in range(1, MotionPose.N):
		_w[i] = _w[_parent[i]] * Transform3D(Basis(_final.rot[i]), _off[i])
	# head look-at over the clip
	_update_head(delta, st)
	# feet, pelvis drop, legs
	_solve_legs(delta, root, st, airborne, hvel)
	# arms and weapon grip
	_solve_arms(root, st)
	# write targets
	var T := body.targets
	for i in MotionPose.N:
		T[Rig.ORDER[i]] = _w[i]


func _reset(root: Transform3D) -> void:
	_key = ""
	_off_t = 99.0
	pelvis_drop = 0.0
	for f in feet:
		f.locked = false
		f.lock_w = 0.0
		f.was_contact = false
		f.stepping = false
	prev_yaw = root.basis.get_euler().y
	_phase = 0.0


# ---------------------------------------------------------------- clip selection

func _select(st: Dictionary, root: Transform3D, hvel: Vector3) -> Dictionary:
	## Chooses what to play: {key, clip, t, loco, half}
	var action: String = st.get("action", "")
	var at: float = st.get("action_time", 0.0)
	var res := {"key": "loco", "clip": null, "t": 0.0, "loco": true, "half": 0.12}
	var cname := ""
	var t := at
	match action:
		"attack":
			var att: Dictionary = st.get("attack", {})
			cname = str(att.get("clip", att.get("name", "")))
			var dur := float(att.get("duration", 0.0))
			var c := MotionClip.get_clip(cname)
			if c != null and dur > 0.0:
				t = at * c.duration / dur
				# line the clip's strike up with the middle of the gameplay sweep window, whatever
				# the clip's own length or timing (generated clips are rarely on the beat)
				var act: Array = att.get("active", [])
				if c.meta.has("strike") and act.size() == 2:
					var sg := lerpf(float(act[0]), float(act[1]), 0.45)
					var sc := float(c.meta.strike) * c.duration / maxf(c.duration, 0.01)
					if sg > 0.02 and sg < dur - 0.02:
						if at < sg:
							t = at / sg * sc
						else:
							t = sc + (at - sg) / (dur - sg) * (c.duration - sc)
			res.half = 0.05
		"block":
			cname = "block"
		"parry":
			cname = "parry"
			res.half = 0.04
		"chiburi", "draw":
			cname = action
			var c2 := MotionClip.get_clip(cname)
			var ad := float(st.get("action_duration", 0.0))
			if c2 != null and ad > 0.0 and ad < 90.0:
				t = at * c2.duration / ad
		"roll":
			cname = "roll"
			var c3 := MotionClip.get_clip(cname)
			if c3 != null:
				t = clampf(at / 0.62, 0.0, 1.0) * c3.duration
			res.half = 0.05
		"hit":
			var hd: Vector3 = root.basis.inverse() * (st.get("hit_dir", Vector3.ZERO) as Vector3)
			var v := "hit_b" if hd.z < -0.5 else ("hit_f" if hd.z > 0.5 else ("hit_l" if hd.x > 0.0 else "hit_r"))
			cname = v
			res.half = 0.03
		"stagger", "getup", "sit", "kneel", "pray", "heal", "standoff", "iai_ready":
			cname = action
			var c4 := MotionClip.get_clip(cname)
			var ad2 := float(st.get("action_duration", 0.0))
			if action == "getup" and c4 != null and ad2 > 0.0 and ad2 < 90.0:
				t = at * c4.duration / ad2
		"knockdown":
			cname = "fall"
	if cname != "":
		var clip := MotionClip.get_clip(cname)
		if clip != null:
			res.key = "action:" + cname
			res.clip = clip
			res.t = t
			res.loco = false
	return res


func _sample(delta: float, st: Dictionary, sel: Dictionary, root: Transform3D, hvel: Vector3, airborne: bool) -> void:
	var clip: MotionClip = sel.clip
	var key: String = sel.key
	if clip != null:
		clip.sample(sel.t, _base)
	elif airborne and MotionClip.get_clip("air") != null:
		key = "loco_air"
		MotionClip.get_clip("air").sample(_time, _base)
	else:
		key = "loco_crouch" if st.get("crouching", false) else "loco"
		_locomotion(delta, st, root, hvel)
	if key != _key:
		if _key != "":
			_begin_transition(float(sel.half) if clip != null else 0.14)
		_key = key


func _begin_transition(half: float) -> void:
	_off_half = half
	_off_t = 0.0
	for i in MotionPose.N:
		_off_rot[i] = _last.rot[i] * _base.rot[i].inverse()
	_off_pelvis = _last.pelvis - _base.pelvis
	_off_grip.active = _last.grip_w > 0.001
	_off_grip.pos = _last.grip_pos
	_off_grip.blade = _last.grip_blade
	_off_grip.edge = _last.grip_edge
	_off_grip.w = _last.grip_w
	_off_grip.left = _last.grip_left


func _apply_offset(src: MotionPose, out: MotionPose) -> void:
	out.copy_from(src)
	if _off_t > _off_half * 8.0:
		return
	var k := pow(0.5, _off_t / maxf(_off_half, 0.01))
	for i in MotionPose.N:
		out.rot[i] = Quaternion.IDENTITY.slerp(_off_rot[i], k) * src.rot[i]
	out.pelvis = src.pelvis + _off_pelvis * k
	# grip: blend from the previous grip
	if _off_grip.active and out.grip_w > 0.001:
		out.grip_pos = src.grip_pos.lerp(_off_grip.pos, k)
		out.grip_blade = src.grip_blade.lerp(_off_grip.blade, k).normalized()
		out.grip_edge = src.grip_edge.lerp(_off_grip.edge, k).normalized()
	out.grip_w = lerpf(src.grip_w, _off_grip.w, k) if _off_grip.active else src.grip_w
	out.grip_left = lerpf(src.grip_left, _off_grip.left, k) if _off_grip.active else src.grip_left


# ---------------------------------------------------------------- locomotion

func _gait_clip(n: String) -> MotionClip:
	return MotionClip.get_clip(n)


func _locomotion(delta: float, st: Dictionary, root: Transform3D, hvel: Vector3) -> void:
	var crouching: bool = st.get("crouching", false)
	var armed: bool = st.get("weapon_in_hand", false) and st.get("combat", false) and st.get("action", "") == ""
	var idle_name := "crouch_idle" if crouching else ("guard_idle" if armed else "idle")
	var idle := _gait_clip(idle_name)
	if idle == null:
		idle = _gait_clip("idle")
	var walk := _gait_clip("crouch_walk" if crouching and _gait_clip("crouch_walk") != null else "walk")
	var run := _gait_clip("run")
	var sprint := _gait_clip("sprint") if st.get("sprinting", false) else null
	var speed := smoothed_speed
	var w_move := smoothstep(0.12, 0.6, speed)
	var w_run := smoothstep(1.15, 1.8, speed) if run != null and not crouching else 0.0
	var w_sprint := smoothstep(4.0, 5.0, speed) if sprint != null else 0.0
	if walk == null:
		w_run = 1.0 if run != null else 0.0
	# effective weight of each gait
	var gaits: Array = []
	if walk != null:
		gaits.append([walk, (1.0 - w_run) * (1.0 - w_sprint)])
	if run != null:
		gaits.append([run, w_run * (1.0 - w_sprint)])
	if sprint != null:
		gaits.append([sprint, w_sprint])
	# gait timing: every gait clip starts on the right foot strike, so one phase drives them all.
	# Each clip plays at the rate that matches its native ground speed; stride warping absorbs the rest.
	var cyc := 0.0
	var kk := 0.0
	var wsum := 0.0
	for g in gaits:
		var c: MotionClip = g[0]
		var w: float = g[1]
		if w <= 0.001:
			continue
		var vn := maxf(c.speed * s, 0.05)
		var r := clampf(speed / vn, 0.7, 1.45)
		var k := clampf(speed / (vn * r), 0.7, 1.7)
		cyc += w * r / maxf(c.duration, 0.1)
		kk += w * k
		wsum += w
	if wsum > 0.001:
		cyc /= wsum
		_stride_k = kk / wsum
		var dir := -1.0 if _backward else 1.0
		_phase = fposmod(_phase + cyc * delta * dir, 1.0)
	else:
		_stride_k = 1.0
	# idle pose, then the gaits mixed over it in proportion to the speed
	if idle != null and (w_move < 0.999 or wsum <= 0.001):
		idle.sample(_time, _base)
	elif idle == null:
		_base.copy_from(MotionPose.new())
	if wsum > 0.001:
		var first := true
		for g in gaits:
			var c2: MotionClip = g[0]
			var w2: float = g[1]
			if w2 <= 0.001:
				continue
			if first:
				c2.sample(_phase * c2.duration, _tmp2)
				first = false
				continue
			c2.sample(_phase * c2.duration, _tmp)
			# blend fraction relative to what the gait mix already holds
			var mixed := 0.0
			for g2 in gaits:
				if g2[0] == c2:
					break
				mixed += g2[1]
			_tmp2.blend(_tmp, w2 / maxf(mixed + w2, 0.0001))
		if w_move >= 0.999:
			_base.copy_from(_tmp2)
		else:
			_base.blend(_tmp2, w_move)
	_base.grip_w = 0.0


func _orientation_warp(sel: Dictionary, root: Transform3D, hvel: Vector3, delta: float) -> float:
	## Angle (rad) the legs are turned towards the movement direction while the
	## torso keeps its facing. Backward movement plays the gait in reverse.
	if not sel.get("loco", false) or _key == "loco_air" or hvel.length() < 0.5:
		_theta = lerp_angle(_theta, 0.0, clampf(delta * 6.0, 0.0, 1.0))
		_backward = false
		return 0.0
	var lv := root.basis.inverse() * hvel
	var target := atan2(-lv.x, -lv.z)
	_theta = lerp_angle(_theta, target, clampf(delta * 12.0, 0.0, 1.0))
	var a := absf(_theta)
	if _backward:
		if a < deg_to_rad(120.0):
			_backward = false
	elif a > deg_to_rad(145.0):
		_backward = true
	if _backward:
		return wrapf(_theta - signf(_theta) * PI, -PI, PI) * 0.9
	return clampf(_theta, deg_to_rad(-105.0), deg_to_rad(105.0))


# ---------------------------------------------------------------- weapon grip

func _choose_grip(delta: float, root: Transform3D, st: Dictionary, sel: Dictionary) -> void:
	var action: String = st.get("action", "")
	var weapon: String = st.get("weapon", "katana")
	var in_hand: bool = st.get("weapon_in_hand", false)
	var hand_on_hilt: bool = action in ["chiburi", "draw", "standoff", "iai_ready"]
	var clip: MotionClip = sel.clip
	_legacy_grip = false
	_clip_grip_active = clip != null and clip.has_grip and _final.grip_w > 0.001 and (in_hand or hand_on_hilt)
	if _clip_grip_active:
		# the clip's own grip (attacks, blocks, draws...)
		_grip_def.pos = _final.grip_pos
		_grip_def.blade = _final.grip_blade
		_grip_def.edge = _final.grip_edge
		_grip_def.w = _final.grip_w
		_grip_def.left = _final.grip_left
		return
	# default stances: guard, blade back while sprinting, hand on the sheathed hilt
	var key := {}
	var target_w := 0.0
	var left_t := 1.0 if AttackLibrary.WEAPONS.get(weapon, {}).get("two_handed", true) else 0.0
	if in_hand:
		target_w = 1.0
		if action in ["roll", "knockdown", "getup"]:
			target_w = 0.0
			key = AttackLibrary.guard(weapon)
		elif action == "stagger":
			target_w = 0.35
			key = AttackLibrary.guard(weapon)
		elif st.get("run_blade_back", false):
			key = AttackLibrary.key(0, Vector3(0.3, 1.06, 0.08), Vector3(0.25, -0.35, 0.9), Vector3(0, -1, 0))
			left_t = 0.0
		elif action == "attack":
			# attack without a clip: legacy key frames hold the grip in character space
			var att: Dictionary = st.get("attack", {})
			if att.has("keys"):
				var k := AttackLibrary.sample(att.keys, float(st.get("action_time", 0.0)))
				if not k.is_empty():
					_legacy_grip = true
					_legacy_xf = root * Transform3D(AttackLibrary.grip_basis(k.dir, k.edge), (k.pos + Vector3(0.0, Rig.upper_shift(), 0.0)) * s)
			key = AttackLibrary.guard(weapon)
		else:
			key = AttackLibrary.guard(weapon)
			var br := sin(breath * 1.6) * 0.012
			key = key.duplicate()
			key.pos = key.pos + Vector3(0.0, br, 0.0)
	elif hand_on_hilt:
		target_w = 1.0
		key = AttackLibrary.hilt_pose()
		left_t = 0.0
	if key.is_empty():
		_grip_def.w = move_toward(_grip_def.w, 0.0, delta * 6.0)
		return
	# root-space key -> chest frame (keys are authored on the rest body)
	var chest_rest: Vector3 = Rig.pivot["chest"]
	var pos_c: Vector3 = key.pos + Vector3(0.0, Rig.upper_shift(), 0.0) - chest_rest
	var blend := 1.0 if _grip_def.w < 0.05 else clampf(delta * 14.0, 0.0, 1.0)
	_grip_def.pos = (_grip_def.pos as Vector3).lerp(pos_c, blend)
	_grip_def.blade = (_grip_def.blade as Vector3).lerp(key.dir, blend).normalized()
	_grip_def.edge = (_grip_def.edge as Vector3).lerp(key.edge, blend).normalized()
	_grip_def.w = move_toward(_grip_def.w, target_w, delta * 6.0)
	_grip_def.left = move_toward(_grip_def.left, left_t, delta * 6.0)


# ---------------------------------------------------------------- head

func _update_head(delta: float, st: Dictionary) -> void:
	var look: Variant = st.get("look_target", null)
	var t_yaw := 0.0
	var t_pitch := 0.0
	var has := look is Vector3
	var head_base: Vector3 = _w[HEAD].origin + _w[HEAD].basis * (Rig.com_offset("head") * s)
	if has:
		var chest_b: Basis = _w[CHEST].basis
		var to_t: Vector3 = chest_b.inverse() * ((look as Vector3) - head_base)
		t_yaw = clampf(atan2(-to_t.x, -to_t.z), -1.1, 1.1)
		t_pitch = clampf(atan2(to_t.y, Vector2(to_t.x, to_t.z).length()), -0.7, 0.6)
	var action: String = st.get("action", "")
	if action in ["pray", "heal"]:
		t_pitch = -0.45
	look_w = move_toward(look_w, 1.0 if has else 0.0, delta * 4.0)
	head_yaw = lerpf(head_yaw, t_yaw, clampf(delta * 7.0, 0.0, 1.0))
	head_pitch = lerpf(head_pitch, t_pitch, clampf(delta * 7.0, 0.0, 1.0))
	if look_w > 0.01:
		var q_look := Quaternion(Basis.from_euler(Vector3(head_pitch, head_yaw, 0.0)))
		var q := _final.rot[HEAD].slerp(q_look, look_w)
		_final.rot[HEAD] = q
		_w[HEAD] = _w[CHEST] * Transform3D(Basis(q), _off[HEAD])


# ---------------------------------------------------------------- legs

func _solve_legs(delta: float, root: Transform3D, st: Dictionary, airborne: bool, hvel: Vector3) -> void:
	var ankle_h := Rig.ankle_height() * s
	var contact := _final.contact
	if airborne:
		contact = Vector2.ZERO
	var sel_loco: bool = _key.begins_with("loco")
	var k := _stride_k if (sel_loco and _key != "loco_air") else 1.0
	var dirm := Vector3.ZERO
	if hvel.length() > 0.3:
		dirm = hvel.normalized()
	# pelvis-relative ankle targets from the clip (stride warped), before any pinning
	var fk_target: Array[Vector3] = []
	for f in feet:
		var a: Vector3 = _w[f.part].origin
		if k != 1.0 and dirm != Vector3.ZERO:
			var rel := a - Vector3(_w[PELVIS].origin.x, a.y, _w[PELVIS].origin.z)
			var along := rel.dot(dirm)
			a += dirm * (k - 1.0) * along
		fk_target.append(a)
	# pins: lock when the clip plants a foot, release when it lifts it
	var busy := false
	for f in feet:
		if f.stepping:
			busy = true
	for i in feet.size():
		var f := feet[i]
		var c := (contact.x if f.side > 0 else contact.y) > 0.5
		var a: Vector3 = fk_target[i]
		var fk_yaw := _foot_yaw(_w[f.part].basis)
		if c and not f.was_contact:
			# plant: pin the ankle's ground point where the clip puts it
			var g := _ground(a, root.origin.y)
			f.pin = g[0]
			f.pin_normal = g[1]
			f.pin_yaw = fk_yaw
			f.locked = true
			f.stepping = false
			if smoothed_speed > 0.8 and ch.has_method("on_footstep") and _key.begins_with("loco"):
				ch.on_footstep(f.pin, smoothed_speed)
		elif not c and f.was_contact:
			f.locked = false
		f.was_contact = c
		f.lock_w = move_toward(f.lock_w, 1.0 if (f.locked or f.stepping) else 0.0, delta * (14.0 if f.locked else 10.0))
		if f.locked and not f.stepping:
			# idle re-step: the clip's stance moved away from the pin (turned on the spot, pushed)
			var ideal := a
			var off := f.pin - Vector3(ideal.x, f.pin.y, ideal.z)
			off.y = 0.0
			var turned := absf(wrapf(f.pin_yaw - fk_yaw, -PI, PI))
			var idle_like := smoothed_speed < 0.6 and _key != "loco_air"
			if idle_like and not busy and (off.length() > 0.2 * s or turned > 0.6):
				var g2 := _ground(ideal, root.origin.y)
				f.stepping = true
				f.step_t = 0.0
				f.step_from = f.pin
				f.step_to = g2[0]
				f.pin_normal = g2[1]
				f.step_yaw = fk_yaw
				busy = true
			elif off.length() > 0.9 * s:
				var g3 := _ground(ideal, root.origin.y)
				f.pin = g3[0]
				f.pin_yaw = fk_yaw
	# a planted foot that ends up out of reach (the character lunged further than the clip
	# expected) is dragged along the ground towards where the clip wants it; the pelvis only
	# drops for what is left (slopes)
	var drop_needed := 0.0
	for i in feet.size():
		var f := feet[i]
		var thigh_idx := 10 if f.side > 0 else 13
		var hip: Vector3 = _w[thigh_idx].origin
		if f.locked and not f.stepping:
			var want: Vector3 = fk_target[i]
			for it in 5:
				if hip.distance_to(f.pin + Vector3(0, ankle_h, 0)) <= _leg_len * 0.97:
					break
				f.pin = f.pin.lerp(Vector3(want.x, f.pin.y, want.z), 0.45)
		var pin_a := (f.pin if f.locked or f.stepping else fk_target[i]) + Vector3(0, ankle_h, 0)
		if f.stepping:
			pin_a = f.step_from.lerp(f.step_to, 0.5) + Vector3(0, ankle_h, 0)
		var dist := hip.distance_to(pin_a)
		if f.lock_w > 0.2 and dist > _leg_len * 0.985:
			drop_needed = maxf(drop_needed, (dist - _leg_len * 0.985) * 1.02)
	pelvis_drop = lerpf(pelvis_drop, drop_needed, clampf(delta * 14.0, 0.0, 1.0))
	if pelvis_drop > 0.0005:
		for i in MotionPose.N:
			var xf := _w[i]
			xf.origin.y -= pelvis_drop
			_w[i] = xf
		for i in fk_target.size():
			fk_target[i].y -= pelvis_drop
	# solve each leg
	for i in feet.size():
		var f := feet[i]
		var sfx := "_r" if f.side > 0 else "_l"
		var thigh_idx := 10 if f.side > 0 else 13
		var shin_idx := thigh_idx + 1
		var hip: Vector3 = _w[thigh_idx].origin
		# ankle target
		var swing_a: Vector3 = fk_target[i]
		# swinging feet follow the terrain when they are near the ground
		var h_above := (swing_a.y - root.origin.y - ankle_h) / maxf(s, 0.01)
		var near := 1.0 - smoothstep(0.03, 0.2, h_above)
		var target := swing_a
		if near > 0.01 and space != null:
			var gs := _ground(swing_a, root.origin.y)
			target.y += (gs[0].y - root.origin.y) * near
		var pinned_pos: Vector3
		var pinned_yaw := f.pin_yaw
		if f.stepping:
			f.step_t = minf(1.0, f.step_t + delta / 0.24)
			var e := f.step_t * f.step_t * (3.0 - 2.0 * f.step_t)
			pinned_pos = f.step_from.lerp(f.step_to, e) + Vector3(0, 0.09 * s * sin(f.step_t * PI), 0)
			pinned_yaw = lerp_angle(f.pin_yaw, f.step_yaw, e)
			if f.step_t >= 1.0:
				f.stepping = false
				f.locked = true
				f.pin = f.step_to
				f.pin_yaw = f.step_yaw
				pinned_pos = f.pin
		else:
			pinned_pos = f.pin
		var pin_ankle := pinned_pos + Vector3(0, ankle_h, 0)
		var ankle := target.lerp(pin_ankle, f.lock_w)
		f.ankle = ankle
		# IK that keeps the clip's own knee axis: the bend plane is the one the clip's thigh
		# already bends in (its lateral axis, made perpendicular to the new hip-ankle line).
		# A pole taken from the knee position flips when the leg is nearly straight (heel
		# strike), and the twist of the thigh flips with it - more than the hip joint can follow.
		var chord := (ankle - hip)
		var chord_dir := chord.normalized() if chord.length_squared() > 1e-8 else Vector3.DOWN
		var axis_fk: Vector3 = (_w[thigh_idx] as Transform3D).basis.x
		var axis := axis_fk - chord_dir * axis_fk.dot(chord_dir)
		if axis.length_squared() < 1e-4:
			axis = root.basis.x
			axis = axis - chord_dir * axis.dot(chord_dir)
		var pole := axis.normalized().cross(chord_dir)
		var l1 := Rig.bone_length("thigh" + sfx) * s
		var l2 := Rig.bone_length("shin" + sfx) * s
		var r := solve_ik(hip, ankle, l1, l2, pole)
		var knee: Vector3 = r[0]
		var ank: Vector3 = r[1]
		var hinge: Vector3 = -(r[2] as Vector3)
		_w[thigh_idx] = Transform3D(_basis_from_bone(knee - hip, hinge), hip)
		_w[shin_idx] = Transform3D(_basis_from_bone(ank - knee, hinge), knee)
		# foot orientation: clip pose when free, flat on the ground with the pinned yaw when planted
		var fb_fk: Basis = _w[f.part].basis
		var fb: Basis = fb_fk
		if f.lock_w > 0.01:
			var n := f.pin_normal if f.pin_normal.y > 0.5 else Vector3.UP
			var flat := Basis(Quaternion(Vector3.UP, n)) * Basis(Vector3.UP, pinned_yaw)
			fb = Basis(fb_fk.get_rotation_quaternion().slerp(flat.get_rotation_quaternion(), f.lock_w))
		_w[f.part] = Transform3D(fb, ank)


func _foot_yaw(b: Basis) -> float:
	var fwd := -b.z
	fwd.y = 0.0
	if fwd.length_squared() < 1e-6:
		return 0.0
	fwd = fwd.normalized()
	return atan2(-fwd.x, -fwd.z)


# ---------------------------------------------------------------- arms

func _solve_arms(root: Transform3D, st: Dictionary) -> void:
	var weapon: String = st.get("weapon", "katana")
	var chest_w: Transform3D = _w[CHEST]
	var gp: Dictionary = _grip_def
	grip_weight = gp.w
	var grip_local := Transform3D(AttackLibrary.grip_basis(gp.blade, gp.edge), (gp.pos as Vector3) * s)
	var grip_w: Transform3D = _legacy_xf if _legacy_grip else chest_w * grip_local
	grip_char = root.affine_inverse() * grip_w
	var left_off: float = AttackLibrary.WEAPONS.get(weapon, {}).get("left_hand", -0.16)
	var two_handed: bool = AttackLibrary.WEAPONS.get(weapon, {}).get("two_handed", true)
	for side in [1, -1]:
		var sfx := "_r" if side > 0 else "_l"
		var ua_i := Rig.ORDER.find("upper_arm" + sfx)
		var fa_i := ua_i + 1
		var hd_i := ua_i + 2
		var hold_w: float = gp.w
		if side < 0:
			hold_w *= gp.left if two_handed else 0.0
		if hold_w > 0.01:
			var g := grip_w
			if side < 0:
				g = grip_w * Transform3D(Basis(), Vector3(0, left_off * s, 0))
			var hand_xf := g * hand_to_weapon.affine_inverse()
			var hand_target := (_w[hd_i] as Transform3D).interpolate_with(hand_xf, hold_w) as Transform3D
			_arm_ik(chest_w, _w[ua_i].origin, hand_target, side, ua_i, fa_i, hd_i)


func _arm_ik(chest_w: Transform3D, shoulder: Vector3, hand_xf: Transform3D, side: int, ua_i: int, fa_i: int, hd_i: int) -> void:
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
	var hinge: Vector3 = r[2]
	_w[ua_i] = Transform3D(_basis_from_bone(d1, hinge), shoulder)
	_w[fa_i] = Transform3D(_basis_from_bone(d2, hinge), elbow)
	_w[hd_i] = Transform3D(hand_xf.basis, wrist)


## World transform of the weapon grip (for the weapon node while held).
func grip_world(root: Transform3D) -> Transform3D:
	return root * grip_char
