class_name Player
extends Character
## The ronin controlled by the player: camera-relative movement, buffered
## combat input (combos, charged heavy, block/parry, dodge), soft targeting
## and lock-on, Resolve-based healing, perfect-dodge/parry slow motion.

signal resolve_changed(value: int, charge: float)
signal perfect_move(kind: String)

const WALK := 2.1
const RUN := 5.2
const SPRINT := 7.8
const CROUCH := 1.9
const COMBAT_SPEED := 3.6
const JUMP := 6.0
const BUFFER := 0.3

var cam_rig: CameraRig
var lock_target: Character = null
var soft_target: Character = null
var resolve := 2
var max_resolve := 3
var resolve_charge := 0.0
var counter_window := 0.0
var heavy_hold := 0.0
var charging := false
var combat_timer := 0.0
var _buf_light := 0.0
var _buf_heavy_release := false
var _heal_left := 0.0
var _dodge_tap := 0.0
var input_enabled := true


func _init() -> void:
	style = "player"
	team = Team.PLAYER
	scale_factor = 1.0


func _ready() -> void:
	super._ready()
	add_to_group("player")
	Game.player = self
	max_health += float(SaveGame.data.get("max_health_bonus", 0))
	health = max_health
	max_resolve += int(SaveGame.data.get("resolve_bonus", 0))
	cam_rig = CameraRig.new()
	cam_rig.name = "CameraRig"
	cam_rig.target = self
	cam_rig.yaw = rotation.y
	get_parent().add_child.call_deferred(cam_rig)
	died.connect(func(_c: Character, _i: Dictionary) -> void:
		Game.slowmo(2.5, 0.25)
		get_tree().create_timer(1.2).timeout.connect(func() -> void: Game.set_state(Game.State.DEAD)))


func _unhandled_input(event: InputEvent) -> void:
	if not Game.is_playing() or dead or not input_enabled:
		return
	if event.is_action_pressed("lock_on"):
		if lock_target:
			lock_target = null
		else:
			lock_target = _find_target(18.0, 0.0)
		cam_rig.lock_target = lock_target


func _think(delta: float) -> void:
	if not Game.is_playing() or not input_enabled:
		move_dir = Vector3.ZERO
		move_speed = 0.0
		return
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := cam_rig.yaw_basis() * Vector3(inp.x, 0.0, inp.y) if cam_rig else Vector3(inp.x, 0.0, inp.y)
	var mag := minf(inp.length(), 1.0)
	if Input.is_action_just_pressed("crouch"):
		crouching = not crouching
	sprinting = Input.is_action_pressed("sprint") and mag > 0.3 and action == "" and not crouching
	if sprinting:
		crouching = false
	var speed := RUN if mag > 0.55 else WALK
	if sprinting:
		speed = SPRINT
	elif crouching:
		speed = CROUCH
	elif combat and _nearby_enemy(9.0) != null:
		speed = COMBAT_SPEED
	move_dir = dir.normalized() if mag > 0.05 else Vector3.ZERO
	move_speed = speed * mag
	# targets
	if lock_target and (not is_instance_valid(lock_target) or lock_target.dead or lock_target.global_position.distance_to(global_position) > 25.0):
		lock_target = null
		cam_rig.lock_target = null
	soft_target = lock_target if lock_target else _find_target(7.0, 0.2, move_dir)
	var focus: Character = soft_target
	if focus and (combat or action == "attack"):
		var to := focus.global_position - global_position
		to.y = 0.0
		if action == "attack" or lock_target or move_dir == Vector3.ZERO or not sprinting:
			face_dir = to.normalized() if to.length() > 0.1 else face_dir
		else:
			face_dir = move_dir
		look_target = focus.chest_position()
	else:
		if move_dir != Vector3.ZERO:
			face_dir = move_dir
		look_target = global_position + Vector3(0, 1.6, 0) + cam_rig.forward_flat() * 10.0 if cam_rig else null
	# combat stance management
	var threat := _nearby_enemy(22.0, true)
	if threat:
		combat_timer = 7.0
		if not weapon_drawn and action == "" and not disarmed:
			draw_weapon()
	else:
		combat_timer -= delta
		if combat_timer <= 0.0 and weapon_drawn and action == "":
			sheathe_weapon(true)
	combat = weapon_drawn and combat_timer > 0.0
	counter_window = maxf(0.0, counter_window - delta)
	_handle_combat_input(delta, dir, mag)
	# healing over time
	if action == "heal":
		var h := 45.0 * delta
		heal(h)
	# grass trampling
	RenderingServer.global_shader_parameter_set("trample_0", Vector4(global_position.x, global_position.y, global_position.z, 0.9))


func _handle_combat_input(delta: float, dir: Vector3, mag: float) -> void:
	_buf_light = maxf(0.0, _buf_light - delta)
	if Input.is_action_just_pressed("attack_light"):
		_buf_light = BUFFER
	# light attacks / combos / counters
	if _buf_light > 0.0 and not charging:
		if action == "attack":
			var nxt: String = attack.get("next", "")
			if nxt != "" and queued_attack == "":
				queued_attack = nxt
				_buf_light = 0.0
		elif action in ["", "block"] or (action == "roll" and action_time > ROLL_TIME * 0.6):
			var name := "counter" if counter_window > 0.0 else "light_1"
			counter_window = 0.0
			if start_attack(name):
				_buf_light = 0.0
	# charged heavy: hold to charge, release to strike
	if Input.is_action_just_pressed("attack_heavy") and action in ["", "block"] and not disarmed:
		charging = true
		heavy_hold = 0.0
		if not weapon_drawn:
			draw_weapon(true)
		attack = AttackLibrary.get_attack("heavy_charge")
		set_action("attack", 999.0)
		Audio.play_at("charge", global_position, -8.0)
	if charging:
		heavy_hold += delta
		if heavy_hold > 0.35:
			weapon.glint(Color(1.0, 0.8, 0.45), clampf(heavy_hold / 1.1, 0.0, 1.0))
		if not Input.is_action_pressed("attack_heavy") or heavy_hold > 1.6:
			charging = false
			var power := clampf(heavy_hold / 1.0, 0.35, 1.0)
			start_attack("heavy")
			attack = attack.duplicate()
			attack.damage = float(attack.damage) * lerpf(0.7, 1.25, power)
			attack.breaks_guard = power > 0.8
			attack.power = lerpf(1.3, 2.0, power)
			cam_rig.kick_fov(6.0 * power)
	# block / parry
	if Input.is_action_just_pressed("block") and action in ["", "attack"] and not charging and not disarmed:
		if action == "attack" and action_time < float(attack.get("active", [0.0])[0]):
			end_action()
		if action == "":
			if not weapon_drawn:
				draw_weapon(true)
			blocking = true
			block_time = 0.0
			set_action("block", 999.0)
	if action == "block" and not Input.is_action_pressed("block"):
		blocking = false
		end_action()
	# dodge
	if Input.is_action_just_pressed("dodge") and not charging:
		if action in ["", "block", "hit"] or (action == "attack" and action_time > float(attack.get("cancel", 0.4)) * 0.8):
			if action == "attack":
				end_action()
			roll(dir if mag > 0.1 else -global_basis.z * -1.0)
	# jump
	if Input.is_action_just_pressed("jump") and is_on_floor() and action in ["", "block"]:
		velocity.y = JUMP
		Audio.play_at("jump", global_position, -8.0)
	# heal with Resolve
	if Input.is_action_just_pressed("heal") and action == "" and resolve > 0 and health < max_health:
		resolve -= 1
		set_action("heal", 1.0)
		Audio.play("heal", -2.0)
		resolve_changed.emit(resolve, resolve_charge)


func _find_target(max_dist: float, min_dot: float, prefer_dir := Vector3.ZERO) -> Character:
	var best: Character = null
	var best_score := INF
	var fwd := prefer_dir if prefer_dir.length_squared() > 0.01 else (cam_rig.forward_flat() if cam_rig else -global_basis.z)
	for e in get_tree().get_nodes_in_group("enemies"):
		var c := e as Character
		if c == null or c.dead:
			continue
		var to := c.global_position - global_position
		var d := to.length()
		if d > max_dist:
			continue
		to.y = 0.0
		var dot := fwd.dot(to.normalized()) if to.length() > 0.01 else 1.0
		if dot < min_dot and d > 2.5:
			continue
		var score := d * (1.6 - dot)
		if score < best_score:
			best_score = score
			best = c
	return best


func _nearby_enemy(radius: float, aware_only := false) -> Character:
	for e in get_tree().get_nodes_in_group("enemies"):
		var c := e as Character
		if c == null or c.dead:
			continue
		if aware_only and not c.get("aware"):
			continue
		if c.global_position.distance_to(global_position) < radius:
			return c
	return null


func _on_dodged(info: Dictionary) -> void:
	if action == "roll" and action_time < 0.22:
		perfect_move.emit("dodge")
		Game.slowmo(0.9, 0.3)
		counter_window = 1.0
		add_resolve_charge(0.2)
		Audio.play("perfect", -4.0)


func _on_parried(info: Dictionary) -> void:
	super._on_parried(info)
	perfect_move.emit("parry")
	Game.slowmo(0.7, 0.28)
	counter_window = 1.1
	add_resolve_charge(0.25)
	cam_rig.kick_fov(-6.0)


func add_resolve_charge(v: float) -> void:
	resolve_charge += v
	while resolve_charge >= 1.0:
		resolve_charge -= 1.0
		if resolve < max_resolve:
			resolve += 1
			Audio.play("resolve", -6.0)
	resolve_changed.emit(resolve, resolve_charge)


func receive_hit(info: Dictionary) -> String:
	var r := super.receive_hit(info)
	if r == "hit" or r == "killed":
		Game.player_damaged.emit(float(info.get("damage", 0.0)), info.get("dir", Vector3.FORWARD))
		Game.shake(0.5)
		cam_rig.kick_fov(-5.0)
		charging = false
	elif r == "blocked":
		Game.shake(0.2)
	return r


func _attack_target() -> Character:
	var t: Character = lock_target if lock_target else soft_target
	if t == null or t.dead:
		t = _find_target(4.5, 0.1, -global_basis.z)
	if t and t.global_position.distance_to(global_position) < 5.0:
		return t
	return null


func max_lunge() -> float:
	return 2.6


func damage_multiplier() -> float:
	return 1.0


## Respawn (after death) at a position.
func respawn(at: Vector3) -> void:
	dead = false
	disarmed = false
	health = max_health
	guard = max_guard
	bleeding = 0.0
	action = ""
	collision_layer = 1 << 1
	collision_mask = 1 | (1 << 1)
	global_position = at
	velocity = Vector3.ZERO
	# rebuild the body (limbs may have been severed)
	if body:
		body.queue_free()
	if weapon and is_instance_valid(weapon):
		var wp := weapon.get_parent()
		weapon.queue_free()
		if wp is RigidBody3D and wp.get_parent() == get_tree().current_scene:
			wp.queue_free()
	body = RagdollBody.new()
	body.name = "Body"
	add_child(body)
	body.top_level = true
	body.global_transform = Transform3D.IDENTITY
	body.build(self, style, scale_factor, seed)
	animator = ProceduralAnimator.new()
	animator.setup(self, body, scale_factor)
	_exclude.clear()
	for rb in body.all_bodies():
		_exclude.append((rb as RigidBody3D).get_rid())
	_exclude.append(get_rid())
	weapon = Weapon.new()
	weapon.name = "Weapon"
	weapon.setup(self, body, animator, weapon_kind)
	weapon.struck.connect(_on_weapon_struck)
	weapon_drawn = false
	weapon.sheathe()
	body.part_severed.connect(_on_part_severed)
	animator.update(1.0 / 60.0, anim_state())
	body.snap_to_targets()
