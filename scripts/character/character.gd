class_name Character
extends CharacterBody3D
## Base class for the player and every enemy. The CharacterBody3D capsule
## handles robust locomotion on the open-world terrain; the RagdollBody is
## the visible, physical HFF-style body that follows the procedural
## animation. Actions (attacks, rolls, blocks, reactions...) are small timed
## states; combat results are resolved in receive_hit().

signal died(ch: Character, info: Dictionary)
signal damaged(ch: Character, amount: float, info: Dictionary)
signal attack_started(ch: Character, attack: Dictionary)
signal hit_landed(ch: Character, target: Character, result: String, info: Dictionary)

enum Team { PLAYER, ENEMY }

const PARRY_WINDOW := 0.2
const ROLL_TIME := 0.62
const ROLL_DISTANCE := 4.6

var style := "ronin"
var team := Team.ENEMY
var scale_factor := 1.0
var seed := 0
var body: RagdollBody
var animator: ProceduralAnimator
var weapon: Weapon
var weapon_kind := "katana"

var max_health := 100.0
var health := 100.0
var max_guard := 100.0
var guard := 100.0
var guard_regen := 16.0
var dead := false
var disarmed := false
var invulnerable := 0.0
var bleeding := 0.0
var terrified := 0.0

var move_dir := Vector3.ZERO
var move_speed := 0.0
var face_dir := Vector3.FORWARD
var turn_rate := 12.0
var gravity_accel := 17.0
var accel_ground := 32.0
var accel_air := 5.0
var external_velocity := Vector3.ZERO
var crippled := false
var posture_broken := 0.0        # seconds left of the Sekiro-style opening
var can_lose_limbs := true
var attack_target: Character = null
var attack_step := 0.0
var attack_step_window := Vector2.ZERO
var _loco := Vector3.ZERO   # locomotion part of the horizontal velocity
var landed := 0.0
var _was_on_floor := true
var _fall_speed := 0.0

var action := ""
var action_time := 0.0
var action_duration := 0.0
var attack := {}
var queued_attack := ""
var roll_dir := Vector3.FORWARD
var hit_dir := Vector3.ZERO
var weapon_drawn := false
var combat := false
var crouching := false
var sprinting := false
var blocking := false
var block_time := 0.0
var look_target: Variant = null
var knock_timer := 0.0
var kill_info := {}
var _sweep_sound_done := false
var _exclude: Array[RID] = []


const BODY_SCALE := 0.8   # base size of every character (HFF bodies are small)


func _ready() -> void:
	scale_factor *= BODY_SCALE
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 1)
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.45
	safe_margin = 0.02
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var body_h := Rig.height() * scale_factor
	cap.radius = 0.3 * scale_factor
	cap.height = body_h
	cs.shape = cap
	cs.position = Vector3(0, body_h * 0.5, 0)
	add_child(cs)
	var st: Dictionary = CharacterStyle.STYLES.get(style, CharacterStyle.STYLES["ronin"])
	max_health = float(st.hp)
	health = max_health
	weapon_kind = st.weapon
	body = RagdollBody.new()
	body.name = "Body"
	add_child(body)
	body.top_level = true
	body.global_transform = Transform3D.IDENTITY
	body.build(self, style, scale_factor, seed)
	animator = ProceduralAnimator.new()
	animator.setup(self, body, scale_factor)
	for rb in body.all_bodies():
		_exclude.append((rb as RigidBody3D).get_rid())
	_exclude.append(get_rid())
	weapon = Weapon.new()
	weapon.name = "Weapon"
	weapon.setup(self, body, animator, weapon_kind)
	weapon.struck.connect(_on_weapon_struck)
	if weapon_drawn:
		weapon.hold()
	else:
		weapon.sheathe()
	body.part_severed.connect(_on_part_severed)
	body.part_sliced.connect(_on_part_sliced)
	face_dir = -global_basis.z
	# settle the body on the initial pose
	animator.update(1.0 / 60.0, anim_state())
	body.snap_to_targets()


func anim_state() -> Dictionary:
	return {
		"root": Transform3D(global_basis.orthonormalized(), global_position),
		"velocity": velocity,
		"on_floor": is_on_floor() or action == "knockdown",
		"weapon": weapon_kind,
		"weapon_in_hand": weapon != null and weapon.in_hand and not disarmed,
		"action": action,
		"action_time": action_time,
		"action_duration": action_duration,
		"attack": attack,
		"combat": combat,
		"crouching": crouching,
		"run_blade_back": weapon_drawn and sprinting and action == "",
		"look_target": look_target,
		"hit_dir": hit_dir,
		"roll_dir": roll_dir,
		"landed": landed,
		"exclude": _exclude,
	}


# ------------------------------------------------------------------ loop

func _physics_process(delta: float) -> void:
	if dead:
		body.drive(delta)
		if body.face and body.face.has_eyes():
			body.face.update(delta, body.part_transform("head"), null, "dead")
		return
	_think(delta)
	_update_action(delta)
	_update_stats(delta)
	_move(delta)
	animator.update(delta, anim_state())
	landed = 0.0
	body.drive(delta)
	if body.face and body.face.has_eyes():
		body.face.update(delta, body.part_transform("head"), look_target, _mood())
	if weapon:
		weapon.physics_update(delta)


## Overridden by Player (input) and Enemy (AI).
func _think(_delta: float) -> void:
	pass


func _update_stats(delta: float) -> void:
	invulnerable = maxf(0.0, invulnerable - delta)
	posture_broken = maxf(0.0, posture_broken - delta)
	terrified = maxf(0.0, terrified - delta)
	if action != "block" and action != "attack":
		guard = minf(max_guard, guard + guard_regen * delta)
	if blocking:
		block_time += delta
	if bleeding > 0.0:
		var d := bleeding * delta
		health -= d
		if Game.rng.randf() < delta * 3.0:
			FX.drip(body.parts["chest"].global_position + Vector3(0, -0.2, 0))
		if health <= 0.0:
			die({"cause": "bleed"})


func _move(delta: float) -> void:
	if action == "knockdown":
		# the capsule follows the ragdoll while it tumbles
		var p: Vector3 = body.parts["pelvis"].global_position
		var target := Vector3(p.x, global_position.y, p.z)
		velocity = (target - global_position) / maxf(delta, 1e-3)
		velocity.y -= gravity_accel * delta
		_loco = Vector3.ZERO
		move_and_slide()
		return
	var desired := move_dir * move_speed
	var locked := action in ["hit", "stagger", "getup", "heal", "parry", "chiburi", "pray", "sit", "kneel", "standoff", "iai_ready"]
	if action == "attack":
		desired *= 0.15
		var sw := attack_step_window
		if action_time >= sw.x and action_time <= sw.y and sw.y > sw.x:
			# the lunge eases in and out (same total distance as a constant-speed step)
			var lu := clampf((action_time - sw.x) / (sw.y - sw.x), 0.0, 1.0)
			var step_speed: float = attack_step * 6.0 * lu * (1.0 - lu) / (sw.y - sw.x)
			var fwd := -global_basis.z
			if attack_target and is_instance_valid(attack_target) and not attack_target.dead:
				var to := attack_target.global_position - global_position
				to.y = 0.0
				if to.length() > 0.2:
					fwd = to.normalized()
			desired += fwd * step_speed
	elif action == "roll":
		var k := clampf(action_time / ROLL_TIME, 0.0, 1.0)
		desired = roll_dir * (ROLL_DISTANCE / ROLL_TIME) * (1.4 - k * 0.9)
	elif action == "block":
		desired *= 0.45
	elif locked:
		desired = Vector3.ZERO
	var acc := accel_ground if is_on_floor() else accel_air
	if action == "roll" or (action == "attack"):
		acc = 60.0
	if action == "attack" and action_time >= attack_step_window.x and action_time <= attack_step_window.y:
		_loco = desired   # the lunge is exact so the swing lands where aimed
	else:
		_loco = _loco.move_toward(desired, acc * delta)
	external_velocity = external_velocity.lerp(Vector3.ZERO, clampf(delta * 5.0, 0.0, 1.0))
	velocity.x = _loco.x + external_velocity.x
	velocity.z = _loco.z + external_velocity.z
	if is_on_floor():
		if velocity.y < 0.0:
			velocity.y = -1.0
	else:
		velocity.y -= gravity_accel * delta
		_fall_speed = maxf(_fall_speed, -velocity.y)
	move_and_slide()
	if get_slide_collision_count() > 0:
		# walls eat locomotion speed so it does not build up against them
		var real := Vector3(velocity.x, 0.0, velocity.z) - external_velocity
		if real.length() < _loco.length():
			_loco = real
	var on_floor := is_on_floor()
	if on_floor and not _was_on_floor:
		_on_landed(_fall_speed)
		_fall_speed = 0.0
	_was_on_floor = on_floor
	# spinning attacks turn the whole body at a fixed rate
	var spinning := false
	if action == "attack" and attack.has("spin"):
		var sp: Array = attack.spin
		if action_time >= float(sp[0]) and action_time <= float(sp[1]):
			rotation.y += deg_to_rad(float(sp[2])) * delta / (float(sp[1]) - float(sp[0]))
			face_dir = -global_basis.z
			spinning = true
	# turning
	if not spinning and face_dir.length_squared() > 0.01 and action != "roll" and action != "knockdown":
		var target_yaw := atan2(-face_dir.x, -face_dir.z)
		var rate := turn_rate
		if action == "attack":
			rate = 9.0 if action_time < float(attack.get("active", [0.2])[0]) else 0.6
			if attack_target and is_instance_valid(attack_target) and not attack_target.dead:
				var tt := attack_target.global_position - global_position
				if tt.length_squared() > 0.04:
					target_yaw = atan2(-tt.x, -tt.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, clampf(rate * delta, 0.0, 1.0))
	# keep the body from being left behind if the capsule got teleported
	if global_position.distance_squared_to(body.parts["pelvis"].global_position) > 36.0 and not dead:
		animator.initialized = false
		animator.update(delta, anim_state())
		body.snap_to_targets()


func on_footstep(pos: Vector3, speed: float) -> void:
	if dead or crouching and speed < 2.5:
		return
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_squared_to(pos) > 900.0:
		return
	Audio.play_at("step", pos, lerpf(-22.0, -9.0, clampf(speed / 7.0, 0.0, 1.0)), 0.12, 30.0)


func _on_landed(fall_speed: float) -> void:
	landed = clampf((fall_speed - 3.0) / 10.0, 0.0, 1.0)
	if fall_speed > 6.0:
		Audio.play_at("land", global_position, -4.0)
		FX.dust(global_position, 1.0 + landed)
	if fall_speed > 17.0:
		var dmg := (fall_speed - 17.0) * 6.0
		receive_hit({"damage": dmg, "fall": true, "dir": Vector3.DOWN, "part": "pelvis", "point": global_position})
		knockdown(Vector3.DOWN * 3.0)


# ------------------------------------------------------------------ actions

func set_action(name: String, duration: float) -> void:
	if weapon and weapon.sweeping:
		weapon.end_sweep()
	action = name
	action_time = 0.0
	action_duration = duration


func end_action() -> void:
	if weapon and weapon.sweeping:
		weapon.end_sweep()
	var was := action
	action = ""
	action_time = 0.0
	attack = {}
	if was == "attack" and queued_attack != "":
		var q := queued_attack
		queued_attack = ""
		start_attack(q)


func can_act() -> bool:
	return not dead and action in ["", "block"]


func start_attack(name: String) -> bool:
	var a := AttackLibrary.get_attack(name)
	if a.is_empty() or dead or disarmed:
		return false
	if not weapon_drawn:
		draw_weapon(true)
	blocking = false
	attack = a
	set_action("attack", float(a.duration))
	_sweep_sound_done = false
	aim_attack_at(_attack_target())
	attack_started.emit(self, a)
	return true


## Magnetism: the lunge of the current attack covers the gap to `target`
## (Ghost of Tsushima style), so swings connect without pixel-perfect spacing.
func aim_attack_at(target: Character) -> void:
	attack_target = target
	attack_step = float(attack.get("step", 0.0))
	var sw: Array = attack.get("step_window", [0.0, 0.0])
	attack_step_window = Vector2(sw[0], sw[1])
	if target == null:
		return
	var to := target.global_position - global_position
	to.y = 0.0
	var ideal := strike_distance()
	attack_step = clampf(to.length() - ideal, 0.0, max_lunge())
	# the lunge must finish just before the blade crosses the front
	var act: Array = attack.get("active", [0.2, 0.3])
	var strike := float(attack.get("strike", lerpf(act[0], act[1], 0.45)))
	attack_step_window = Vector2(minf(sw[0], strike * 0.3), maxf(strike - 0.03, 0.05))
	if to.length() > 0.2:
		face_dir = to.normalized()


## Distance between the two characters at which the current move cuts best.
func strike_distance() -> float:
	return float(attack.get("ideal", AttackLibrary.WEAPONS.get(weapon_kind, {}).get("ideal", 1.0))) * scale_factor * 1.12


## Target the current attack homes in on (null = straight ahead).
func _attack_target() -> Character:
	return null


func max_lunge() -> float:
	return 1.2


func draw_weapon(instant := false) -> void:
	if weapon_drawn or disarmed:
		return
	weapon_drawn = true
	combat = true
	weapon.hold()
	Audio.play_at("sword_draw", global_position, -6.0)
	if not instant and action == "":
		set_action("draw", 0.46)


func sheathe_weapon(with_chiburi := true) -> void:
	if not weapon_drawn:
		return
	if with_chiburi and action == "" and weapon_kind == "katana":
		set_action("chiburi", 1.1)
	else:
		weapon_drawn = false
		combat = false
		weapon.sheathe()


func roll(dir: Vector3) -> bool:
	if dead or action in ["roll", "knockdown", "getup"]:
		return false
	var d := Vector3(dir.x, 0.0, dir.z)
	if d.length_squared() < 0.01:
		d = global_basis.z  # backwards
	roll_dir = d.normalized()
	blocking = false
	set_action("roll", ROLL_TIME)
	invulnerable = 0.42
	Audio.play_at("roll", global_position, -6.0)
	FX.dust(global_position, 0.8)
	return true


func knockdown(impulse: Vector3) -> void:
	if dead:
		return
	set_action("knockdown", 99.0)
	knock_timer = 1.25
	blocking = false
	body.strength = 0.0
	for p in body.parts:
		body.impulse(p, impulse * 0.25)
	body.impulse("chest", impulse)


## Posture (guard) shattered: the character reels and is open to a deathblow.
func break_posture(dir: Vector3) -> void:
	if dead:
		return
	guard = max_guard * 0.35
	posture_broken = 2.4
	stagger(dir, 1.4, 2.4)
	FX.shockwave(chest_position(), Color(1.0, 0.85, 0.5), 1.3)
	Audio.play_at("guard_break", chest_position(), 3.0)


func stagger(dir: Vector3, strength := 1.0, duration := 0.9) -> void:
	if dead:
		return
	hit_dir = dir.normalized()
	set_action("stagger", duration)
	blocking = false
	external_velocity += hit_dir * 3.5 * strength
	body.strength = 0.35
	body.weaken("chest", 0.2)


func _update_action(delta: float) -> void:
	if action == "":
		body.strength = move_toward(body.strength, 1.0, delta * 1.5)
		return
	action_time += delta
	match action:
		"attack":
			var act: Array = attack.get("active", [0.0, 0.0])
			if not _sweep_sound_done and action_time >= float(attack.get("swing_time", act[0])):
				_sweep_sound_done = true
				Audio.play_at("swing_heavy" if float(attack.get("power", 1.0)) > 1.4 else "swing", weapon.tip(), -2.0, 0.1)
			if action_time >= act[0] and action_time <= act[1] and not weapon.sweeping:
				weapon.begin_sweep(_trail_color())
			elif action_time > act[1] and weapon.sweeping:
				weapon.end_sweep()
				if attack.get("slam", false):
					_slam()
			if queued_attack != "" and action_time >= float(attack.get("cancel", 99.0)):
				var q := queued_attack
				queued_attack = ""
				start_attack(q)
				return
			if action_time >= action_duration:
				end_action()
		"knockdown":
			knock_timer -= delta
			var still: bool = (body.parts["pelvis"] as RigidBody3D).linear_velocity.length() < 1.0
			if knock_timer <= 0.0 and still and not crippled:
				set_action("getup", 0.9)
				animator.initialized = false
		"getup":
			body.strength = clampf(action_time / 0.7, 0.05, 1.0)
			if action_time >= action_duration:
				end_action()
		"stagger", "hit":
			body.strength = move_toward(body.strength, 1.0, delta * 1.2)
			if action_time >= action_duration:
				end_action()
		"chiburi":
			if action_time >= 0.36 and action_time - delta < 0.36:
				FX.blood_flick(weapon.tip(), -global_basis.z.rotated(Vector3.UP, -0.8), weapon.blood)
				weapon.set_blood(0.0)
				Audio.play_at("swing", weapon.tip(), -8.0, 0.2)
			if action_time >= 0.95 and weapon_drawn:
				weapon_drawn = false
				combat = false
				weapon.sheathe()
				Audio.play_at("sword_sheathe", global_position, -4.0)
			if action_time >= action_duration:
				end_action()
		"block":
			pass
		_:
			if action_time >= action_duration and action_duration < 90.0:
				end_action()


# ------------------------------------------------------------------ combat

func _on_weapon_struck(target: Node, part: String, point: Vector3, dir: Vector3) -> void:
	if not (target is Character):
		return
	var t := target as Character
	if t.dead or t.team == team:
		return
	var info := {
		"attacker": self, "part": part, "point": point, "dir": dir,
		"damage": float(attack.get("damage", 15.0)), "guard_damage": float(attack.get("guard_damage", 10.0)),
		"attack": attack.get("name", ""), "power": float(attack.get("power", 1.0)),
		"unblockable": attack.get("unblockable", false), "breaks_guard": attack.get("breaks_guard", false),
		"cut": attack.get("cut", "horizontal"), "hitstop": float(attack.get("hitstop", 0.06)),
		"blade": weapon.global_basis.y,
	}
	info.damage *= damage_multiplier()
	var result := t.receive_hit(info)
	hit_landed.emit(self, t, result, info)
	match result:
		"hit", "killed":
			weapon.add_blood(0.18 if result == "hit" else 0.35)
		"parried":
			weapon.end_sweep()
			weapon.glint(Color(1.0, 0.85, 0.5), 0.4)
			# a deflect shakes the attacker's posture; enough of them and it breaks
			guard -= 28.0
			if guard <= 0.0:
				break_posture(-(-global_basis.z))
			else:
				stagger(-(-global_basis.z), 1.2)
		"blocked":
			external_velocity += global_basis.z * 1.5


func damage_multiplier() -> float:
	return 1.0


func is_facing(point: Vector3, cos_limit := 0.3) -> bool:
	var to := point - global_position
	to.y = 0.0
	if to.length_squared() < 1e-4:
		return true
	return (-global_basis.z).dot(to.normalized()) > cos_limit


## Resolves an incoming hit. Returns "dodged", "parried", "blocked",
## "guard_broken", "hit" or "killed".
func receive_hit(info: Dictionary) -> String:
	if dead:
		return "dead"
	var attacker: Character = info.get("attacker", null)
	var point: Vector3 = info.get("point", global_position + Vector3(0, 1.2, 0))
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	if invulnerable > 0.0 and not info.get("fall", false):
		_on_dodged(info)
		return "dodged"
	var from_front := attacker != null and is_facing(attacker.global_position, 0.1)
	if action == "block" and attacker and from_front and not info.get("unblockable", false):
		if block_time <= PARRY_WINDOW:
			_on_parried(info)
			return "parried"
		guard -= float(info.get("guard_damage", 10.0))
		FX.sparks(point, -dir, 1.0)
		Audio.play_at("clash", point, 0.0, 0.1)
		Game.shake(0.25)
		Game.hitstop(0.05)
		if guard <= 0.0 or info.get("breaks_guard", false):
			break_posture(dir)
			return "guard_broken"
		external_velocity += Vector3(dir.x, 0.0, dir.z).normalized() * 1.8
		body.weaken("chest", 0.5)
		return "blocked"
	# the hit lands
	var dmg: float = info.get("damage", 10.0)
	# Sekiro deathblow: a broken posture makes the next cut fatal
	if posture_broken > 0.0 and attacker != null and attacker.team == Team.PLAYER and team == Team.ENEMY and not info.get("fall", false):
		var boss := style in ["brute", "leader"]
		dmg = max_health * (0.6 if boss else 2.0)
		info = info.duplicate()
		info.power = 3.0
		info.deathblow = true
		posture_broken = 0.0
		Game.flash(Color(0.9, 0.05, 0.03), 0.5)
		Game.slowmo(1.2, 0.14)
		Audio.play("deathblow", 0.0)
		FX.blood_burst(point, dir, 3.4)
	health -= dmg
	hit_dir = Vector3(dir.x, 0.0, dir.z).normalized()
	var part: String = info.get("part", "chest")
	var power: float = info.get("power", 1.0)
	damaged.emit(self, dmg, info)
	if not info.get("fall", false):
		FX.blood_hit(point, dir, power)
		body.add_blood(part, point, 0.07 + 0.03 * power, 0.12 * power)
		body.flash(part, 1.0)
		body.impulse(part, dir * 18.0 * power * scale_factor, point)
		body.weaken(part, 0.1)
		Audio.play_at("flesh_cut", point, 0.0, 0.1)
		Game.hitstop(float(info.get("hitstop", 0.06)))
		FX.shockwave(point, Color(1.0, 0.5, 0.3), 0.5 + 0.2 * power)
		_lens_hit(point)
	if health <= 0.0:
		die(info)
		return "killed"
	# strong blows can take a limb off even when the fight goes on
	if can_lose_limbs and not info.get("fall", false) and power >= 1.35 and Game.rng.randf() < 0.28 * (power - 0.9) \
			and bool(Settings.get_value("gore", true)):
		var lp := _limb_of(part)
		if lp != "" and _slice_part(lp, info, false):
			return "hit"
	if power >= 1.7 or info.get("breaks_guard", false):
		stagger(dir, power * 0.8)
	elif action != "attack" or power >= 1.2:
		set_action("hit", 0.35)
		body.strength = 0.4
	external_velocity += hit_dir * 1.6 * power
	return "hit"




func _lens_hit(point: Vector3) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(point) < 3.6:
		Game.lens_splash.emit(0.45, Color(0.5, 0.02, 0.02))


## Limb (or torso part) that a blow to `part` would remove.
func _limb_of(part: String) -> String:
	match part:
		"upper_arm_r", "forearm_r", "hand_r", "upper_arm_l", "forearm_l", "hand_l":
			return part.replace("hand", "forearm")
		"thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l":
			return part.replace("foot", "shin")
	return ""


func _cut_normal(info: Dictionary) -> Vector3:
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var blade: Vector3 = info.get("blade", Vector3.UP)
	var n := dir.cross(blade)
	if n.length() < 0.35:
		n = dir.cross(Vector3.UP)
	if n.length() < 0.35:
		n = Vector3.RIGHT
	return n.normalized()


## Cuts `part` clean through along the blade's plane. Returns true on success.
func _slice_part(part: String, info: Dictionary, lethal: bool) -> bool:
	var point: Vector3 = info.get("point", global_position + Vector3(0, 1.0, 0))
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	var rb: RigidBody3D = body.parts[part]
	# aim the cut through the body axis at the hit height
	var axis_pt: Vector3 = body.part_transform(part).origin.lerp(body.part_transform(part).origin + (global_basis * (Rig.end[part] - Rig.pivot[part]) * scale_factor), 0.5)
	var cut_pt := point if point.distance_to(axis_pt) < 0.3 else point.lerp(axis_pt, 0.6)
	var imp := (dir * 3.2 + Vector3.UP * 2.2) * float(rb.mass)
	var chunk := body.slice(part, cut_pt, _cut_normal(info), imp)
	return chunk != null


func _on_part_sliced(part: String, chunk: RigidBody3D, wpoint: Vector3, wnormal: Vector3) -> void:
	var rb: RigidBody3D = body.parts[part]
	FX.stump_fountain(rb, rb.global_transform.affine_inverse() * wpoint, rb.global_basis.inverse() * wnormal, 3.5)
	FX.stump_fountain(chunk, chunk.global_transform.affine_inverse() * wpoint, chunk.global_basis.inverse() * -wnormal, 2.4)
	FX.blood_burst(wpoint, wnormal, 2.0)
	FX.shockwave(wpoint, Color(1.0, 0.3, 0.2), 0.9)
	Audio.play_at("dismember", wpoint, 3.0)
	Audio.play_at("squish", wpoint, 0.0, 0.1)
	get_tree().create_timer(0.55).timeout.connect(func() -> void:
		if is_instance_valid(chunk):
			Audio.play_at("boing", chunk.global_position, -2.0, 0.15))
	Game.shake(0.5)
	Game.hitstop(0.1)
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(wpoint) < 4.5:
		Game.lens_splash.emit(0.9, Color(0.55, 0.02, 0.02))
	SaveGame.data.dismemberments = int(SaveGame.data.get("dismemberments", 0)) + 1
	if part in ["upper_arm_r", "forearm_r"]:
		if weapon and not weapon.dropped:
			weapon.drop(Vector3.UP * 2.0)
		disarmed = true
	if part in ["thigh_r", "shin_r", "thigh_l", "shin_l"] and not dead:
		crippled = true
		bleeding = maxf(bleeding, 12.0)
		knockdown((global_basis * Vector3(0, 1.5, 2.0)))
	if not dead and part in ["head", "chest", "belly"]:
		health = 0.0
		die({"attacker": null, "cause": "slice", "dir": wnormal, "power": 1.0})
	elif not dead:
		bleeding = maxf(bleeding, 5.0)
		Audio.play_at("scream", global_position + Vector3(0, 1.4, 0), 2.0, 0.1)


func _on_dodged(_info: Dictionary) -> void:
	pass


## The blade bites into the ground: dust, sparks, a ring and a shake (heavy strike).
func _slam() -> void:
	var tip := weapon.tip()
	var wd := WorldData.current
	if wd:
		tip.y = maxf(tip.y, wd.get_height(tip.x, tip.z))
	FX.dust(tip, 2.4)
	FX.sparks(tip, Vector3.UP, 1.2)
	FX.shockwave(tip + Vector3(0, 0.15, 0), Color(1.0, 0.85, 0.55), 1.5)
	Audio.play_at("land", tip, 4.0)
	Game.shake(0.4)


func _mood() -> String:
	if dead:
		return "dead"
	if action in ["hit", "stagger", "knockdown"]:
		return "hurt"
	if action in ["attack", "block", "parry"]:
		return "angry" if team == Team.ENEMY else "focus"
	if combat:
		return "focus"
	return "calm"


func _trail_color() -> Color:
	var n: String = attack.get("name", "")
	if n in ["heavy", "smash", "sweep"]:
		return Color(1.0, 0.75, 0.3, 1.0)
	if n in ["enemy_heavy"]:
		return Color(1.0, 0.25, 0.15, 1.0)
	if n == "counter":
		return Color(1.0, 0.5, 0.25, 1.0)
	if n in ["iai", "assassinate"]:
		return Color(1.0, 1.0, 1.0, 1.0)
	return Color(0.85, 0.93, 1.0, 0.95) if team == Team.PLAYER else Color(1.0, 0.85, 0.8, 0.8)


func _on_parried(info: Dictionary) -> void:
	var point: Vector3 = info.get("point", global_position)
	FX.sparks(point, -(info.get("dir", Vector3.FORWARD) as Vector3), 3.4)
	FX.shockwave(point, Color(1.0, 0.95, 0.75), 1.9)
	Game.flash(Color(1.0, 0.97, 0.9), 0.55)
	Audio.play_at("parry", point, 3.0)
	Game.hitstop(0.12)
	Game.shake(0.5)
	set_action("parry", 0.34)
	blocking = false


func die(info: Dictionary) -> void:
	if dead:
		return
	dead = true
	kill_info = info
	health = 0.0
	if weapon and weapon.sweeping:
		weapon.end_sweep()
	collision_layer = 0
	collision_mask = 1
	var gore: bool = Settings.get_value("gore", true)
	var severed := ""
	var sliced := false
	var dir: Vector3 = info.get("dir", Vector3.FORWARD)
	if gore and not info.get("fall", false) and info.has("attacker"):
		var sp := _choose_slice(info)
		if sp != "":
			body.dead = false          # the stump keeps flopping under its own drive
			sliced = _slice_part(sp, info, true)
		if not sliced:
			severed = _choose_dismemberment(info)
	body.die()
	if severed != "":
		var imp: Vector3 = (dir * 3.5 + Vector3.UP * (4.0 if severed == "head" else 1.5)) * float(body.parts[severed].mass)
		body.sever(severed, imp)
	for p in body.parts:
		body.impulse(p, dir * 2.0 * body.parts[p].mass * 0.3)
	body.impulse("chest", dir * 25.0 * float(info.get("power", 1.0)))
	if weapon and not weapon.dropped and weapon.in_hand:
		weapon.drop(dir * 2.0 + Vector3.UP * 2.0)
	Audio.play_at("death_grunt", global_position + Vector3(0, 1.5, 0), -2.0, 0.12)
	Audio.play_at("body_fall", global_position, -4.0)
	FX.blood_pool_later(self)
	died.emit(self, info)


## Part to slice through for a killing blow (or "" for a joint dismemberment).
func _choose_slice(info: Dictionary) -> String:
	var cut: String = info.get("cut", "horizontal")
	if cut in ["crush", "thrust"]:
		return ""
	var power: float = info.get("power", 1.0)
	var chance := 0.55 + 0.3 * clampf(power - 1.0, 0.0, 1.0)
	if power >= 1.8:
		chance = 1.0
	if Game.rng.randf() > chance:
		return ""
	var part: String = info.get("part", "chest")
	match part:
		"head":
			return "head" if Game.rng.randf() < 0.4 else ""
		"chest", "belly", "pelvis":
			return "chest" if part == "chest" else "belly"
		_:
			return _limb_of(part)
	return ""


func _choose_dismemberment(info: Dictionary) -> String:
	var part: String = info.get("part", "chest")
	var cut: String = info.get("cut", "horizontal")
	var power: float = info.get("power", 1.0)
	var chance := 0.5 + 0.35 * clampf(power - 1.0, 0.0, 1.0)
	if power >= 1.8:
		chance = 1.0
	if Game.rng.randf() > chance or cut == "crush":
		return ""
	if cut == "thrust":
		return ""
	match part:
		"head":
			return "head"
		"chest":
			if cut == "horizontal" and (info.get("point", Vector3.ZERO) as Vector3).y > global_position.y + 1.4 * scale_factor:
				return "head"
			return "chest" if power >= 1.3 else "head"
		"belly", "pelvis":
			return "chest" if power >= 1.3 else ""
		"upper_arm_r", "forearm_r", "hand_r", "upper_arm_l", "forearm_l", "hand_l":
			return part.replace("hand", "forearm")
		"thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l":
			return part.replace("foot", "shin")
	return "head"


func _on_part_severed(part: String, stump: String) -> void:
	var rb: RigidBody3D = body.parts[part]
	var dir: Vector3 = (Rig.end[part] - Rig.pivot[part]).normalized()
	FX.stump_fountain(body.parts[stump], body.parts[stump].global_transform.affine_inverse() * rb.global_position, body.parts[stump].global_basis.inverse() * (global_basis * dir), 2.8)
	FX.stump_fountain(rb, Vector3.ZERO, -(Rig.end[part] - Rig.pivot[part]).normalized(), 1.6)
	FX.blood_burst(rb.global_position, global_basis * dir, 2.2)
	FX.shockwave(rb.global_position, Color(1.0, 0.3, 0.2), 0.9)
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(rb.global_position) < 4.5:
		Game.lens_splash.emit(0.8, Color(0.55, 0.02, 0.02))
	if part == "head":
		# heads are bouncy: BOING
		var bouncy := PhysicsMaterial.new()
		bouncy.bounce = 0.55
		bouncy.friction = 0.6
		rb.physics_material_override = bouncy
		get_tree().create_timer(0.7).timeout.connect(func() -> void:
			if is_instance_valid(rb):
				Audio.play_at("boing", rb.global_position, -1.0, 0.15))
	Audio.play_at("dismember", rb.global_position, 3.0)
	Audio.play_at("squish", rb.global_position, 0.0, 0.1)
	Game.shake(0.45)
	SaveGame.data.dismemberments = int(SaveGame.data.get("dismemberments", 0)) + 1
	if part.begins_with("forearm_r") or part.begins_with("upper_arm_r") or part == "hand_r":
		if weapon and not weapon.dropped:
			weapon.drop(Vector3.UP * 2.0)
		disarmed = true


func heal(amount: float) -> void:
	health = minf(max_health, health + amount)


func is_alive() -> bool:
	return not dead


func chest_position() -> Vector3:
	return (body.parts["chest"] as RigidBody3D).global_position if body else global_position + Vector3(0, 1.3, 0)
