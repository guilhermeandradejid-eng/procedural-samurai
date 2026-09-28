class_name Enemy
extends Character
## Enemy samurai/bandit AI.
##  IDLE        camp life: sitting by the fire, standing guard, patrolling
##  SUSPICIOUS  detection meter filling: turns and walks towards the stimulus
##  COMBAT      circles the player, waits for an attack token from the
##              encounter, then closes in and attacks with telegraphed moves
##  FLEE        terrified or disarmed: backs away and runs
## Detection uses a vision cone + line of sight, modulated by distance,
## light, crouching and tall grass; noise (sprinting, fighting) alerts too.

signal alerted(enemy: Enemy)

enum State { IDLE, SUSPICIOUS, COMBAT, FLEE }

var state := State.IDLE
var aware := false
var detection := 0.0
var encounter: Node = null
var home := Vector3.ZERO
var home_yaw := 0.0
var idle_mode := "guard"          # guard, sit, fire, patrol
var patrol_points: Array[Vector3] = []
var patrol_index := 0
var has_token := false
var token_wait := 0.0
var circle_side := 1.0
var attack_cooldown := 1.5
var block_chance := 0.3
var aggression := 1.0
var action_speed := 1.0
var _think_timer := 0.0
var _last_seen := Vector3.ZERO
var _suspicion_point := Vector3.ZERO
var _combo_left := 0
var _tell_left := 0.0
var _pending_attack := ""
var _feint := false
var _stuck_timer := 0.0
var _last_pos := Vector3.ZERO
var _rng := RandomNumberGenerator.new()
var _ray := PhysicsRayQueryParameters3D.new()
var standoff_mode := false


func _init() -> void:
	team = Team.ENEMY


func _ready() -> void:
	_rng.seed = seed if seed != 0 else randi()
	match style:
		"brute":
			scale_factor = 1.22
			block_chance = 0.15
			aggression = 0.8
		"leader":
			scale_factor = 1.08
			block_chance = 0.55
			aggression = 1.2
		"spearman":
			block_chance = 0.25
		_:
			block_chance = 0.3
	super._ready()
	add_to_group("enemies")
	home = global_position
	home_yaw = rotation.y
	circle_side = 1.0 if _rng.randf() < 0.5 else -1.0
	max_guard = 60.0 if style != "brute" else 120.0
	guard = max_guard
	_ray.collision_mask = 1
	if idle_mode == "sit":
		set_action("sit", 99999.0)
	elif idle_mode == "fire":
		set_action("kneel", 99999.0)


# ------------------------------------------------------------------ AI

func _think(delta: float) -> void:
	var player := Game.player as Player
	if player == null or not is_instance_valid(player):
		return
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = 0.2 + _rng.randf() * 0.1
		_perceive(player, 0.25)
	attack_cooldown = maxf(0.0, attack_cooldown - delta)
	if terrified > 0.0 or disarmed:
		state = State.FLEE
	match state:
		State.IDLE:
			_idle(delta)
		State.SUSPICIOUS:
			_suspicious(delta, player)
		State.COMBAT:
			_combat(delta, player)
		State.FLEE:
			_flee(delta, player)


func _perceive(player: Player, dt: float) -> void:
	if player.dead:
		if state == State.COMBAT:
			state = State.IDLE
			aware = false
		return
	var to := player.chest_position() - (global_position + Vector3(0, 1.6 * scale_factor, 0))
	var d := to.length()
	var seen := 0.0
	var tod: TimeOfDay = Game.world.time_of_day if Game.world else null
	var view := 32.0 * (0.55 if tod and tod.is_night() else 1.0)
	if d < view:
		var fwd := -global_basis.z
		var flat := Vector3(to.x, 0.0, to.z).normalized()
		var cos_a := fwd.dot(flat)
		var in_cone := cos_a > 0.35 or d < 3.0
		if in_cone and _line_of_sight(player):
			seen = clampf(1.0 - d / view, 0.0, 1.0) * 1.6 + (0.6 if d < 6.0 else 0.0)
			if player.crouching:
				seen *= 0.35
			var wd := WorldData.current
			if wd and player.crouching:
				var sp := wd.sample_splat(player.global_position.x, player.global_position.z)
				seen *= 1.0 - sp.g * 0.8   # hiding in the golden pampas
			if state == State.COMBAT:
				seen = 3.0
	# noise: sprinting or fighting nearby
	var noise := 0.0
	if d < 12.0 and (player.sprinting or player.action == "attack"):
		noise = 0.8 if player.action == "attack" else 0.35
	if d < 4.0 and not player.crouching:
		noise = maxf(noise, 0.6)
	var gain := (seen + noise) * dt * (1.4 if state == State.SUSPICIOUS else 1.0)
	if gain > 0.0:
		detection = minf(1.0, detection + gain)
		_last_seen = player.global_position
		if state == State.IDLE and detection > 0.15:
			_become_suspicious(player.global_position)
	else:
		detection = maxf(0.0, detection - dt * (0.1 if state == State.SUSPICIOUS else 0.25))
		if state == State.SUSPICIOUS and detection <= 0.0:
			state = State.IDLE
	if detection >= 1.0 and state != State.COMBAT and state != State.FLEE:
		become_aware(true)
	Game.detection_changed.emit(self, detection if state != State.COMBAT else 1.0)


func _line_of_sight(player: Player) -> bool:
	var space := get_world_3d().direct_space_state
	_ray.from = global_position + Vector3(0, 1.62 * scale_factor, 0)
	_ray.to = player.chest_position()
	_ray.exclude = _exclude
	var hit := space.intersect_ray(_ray)
	return hit.is_empty()


func _become_suspicious(point: Vector3) -> void:
	if state == State.IDLE:
		state = State.SUSPICIOUS
		_suspicion_point = point
		if action in ["sit", "kneel"]:
			set_action("getup", 0.9)
		Audio.play_at("huh", global_position + Vector3(0, 1.6, 0), -6.0, 0.15, 40.0)


## Switches to combat. `shout` alerts the rest of the encounter.
func become_aware(shout := true) -> void:
	if dead or state == State.COMBAT:
		return
	aware = true
	detection = 1.0
	state = State.COMBAT
	if action in ["sit", "kneel"]:
		set_action("getup", 0.9)
	if not weapon_drawn and not disarmed:
		weapon_drawn = true
		combat = true
		weapon.hold()
	if shout:
		Audio.play_at("alert_shout", global_position + Vector3(0, 1.6, 0), 0.0, 0.1, 60.0)
		alerted.emit(self)
	attack_cooldown = 0.8 + _rng.randf() * 1.2


func _idle(delta: float) -> void:
	look_target = null
	match idle_mode:
		"patrol":
			if patrol_points.is_empty():
				move_speed = 0.0
				return
			var tgt := patrol_points[patrol_index]
			var to := tgt - global_position
			to.y = 0.0
			if to.length() < 1.2:
				patrol_index = (patrol_index + 1) % patrol_points.size()
			_steer(to.normalized(), 1.5)
		_:
			var to := home - global_position
			to.y = 0.0
			if to.length() > 1.5 and not action in ["sit", "kneel"]:
				_steer(to.normalized(), 1.6)
			else:
				move_speed = 0.0
				face_dir = Vector3(-sin(home_yaw), 0, -cos(home_yaw))
				if idle_mode == "sit" and action == "":
					set_action("sit", 99999.0)
				elif idle_mode == "fire" and action == "":
					set_action("kneel", 99999.0)


func _suspicious(_delta: float, player: Player) -> void:
	look_target = _suspicion_point + Vector3(0, 1.4, 0)
	var to := _suspicion_point - global_position
	to.y = 0.0
	if action in ["getup"]:
		move_speed = 0.0
		return
	if to.length() > 2.0:
		_steer(to.normalized(), 1.4)
	else:
		move_speed = 0.0
	face_dir = to.normalized() if to.length() > 0.1 else face_dir


func _combat(delta: float, player: Player) -> void:
	if player.dead:
		move_speed = 0.0
		return
	var to := player.global_position - global_position
	to.y = 0.0
	var d := to.length()
	var dir := to / maxf(d, 0.001)
	look_target = player.chest_position()
	face_dir = dir
	if action in ["attack", "hit", "stagger", "knockdown", "getup", "roll", "parry"]:
		move_speed = 0.0
		return
	# telegraph before an attack (weapon raised, optional red glint)
	if _pending_attack != "":
		_tell_left -= delta
		move_dir = dir
		move_speed = 1.2 if d > _attack_range() else 0.0
		if _tell_left <= 0.0:
			var name := _pending_attack
			_pending_attack = ""
			if _feint:
				_feint = false
				attack_cooldown = 0.4
			else:
				_do_attack(name)
		return
	var reach := _attack_range()
	var want := 3.2 + (1.0 if style == "spearman" else 0.0)
	if has_token and attack_cooldown <= 0.0:
		want = reach * 0.85
	var radial := clampf((d - want) * 1.2, -1.0, 1.0)
	var tangent := Vector3(-dir.z, 0.0, dir.x) * circle_side
	var mv := dir * radial + tangent * (0.55 if not has_token else 0.15)
	_steer(mv.normalized() if mv.length() > 0.05 else Vector3.ZERO, 2.4 if absf(radial) > 0.5 else 1.8)
	if _rng.randf() < delta * 0.25:
		circle_side = -circle_side
	# block incoming player attacks sometimes
	if player.action == "attack" and d < 3.0 and action == "" and _rng.randf() < block_chance * delta * 6.0:
		var a_t: float = player.action_time
		if a_t < float(player.attack.get("active", [0.2])[0]):
			blocking = true
			block_time = 0.25
			set_action("block", 0.6)
	if has_token and attack_cooldown <= 0.0 and d < reach + 0.6 and action == "":
		_plan_attack()


func _attack_range() -> float:
	return float(AttackLibrary.WEAPONS.get(weapon_kind, {}).get("reach", 1.0)) * scale_factor + 0.9


func _plan_attack() -> void:
	var moves := AttackLibrary.moves_for(weapon_kind)
	var name: String = moves[_rng.randi() % moves.size()]
	var a := AttackLibrary.get_attack(name)
	_pending_attack = name
	_feint = _rng.randf() < 0.12
	var tell := _rng.randf_range(0.18, 0.42)
	if a.get("unblockable", false) or name == "enemy_heavy":
		tell = 0.55
		weapon.glint(Color(1.0, 0.12, 0.05), 1.0)
		Audio.play_at("glint", weapon.tip(), 0.0, 0.05, 50.0)
	_tell_left = tell
	_combo_left = 1 if (_rng.randf() < 0.35 * aggression and name.begins_with("light")) else 0


func _do_attack(name: String) -> void:
	if not start_attack(name):
		return
	if name == "enemy_heavy":
		attack = attack.duplicate()
		attack.unblockable = true
	attack_cooldown = _rng.randf_range(1.2, 2.6) / aggression
	if _combo_left > 0:
		_combo_left -= 1
		var nxt: String = attack.get("next", "")
		if nxt != "":
			queued_attack = nxt
	if encounter and encounter.has_method("on_attack"):
		encounter.on_attack(self)


func _flee(_delta: float, player: Player) -> void:
	var away := global_position - player.global_position
	away.y = 0.0
	look_target = player.chest_position()
	if action != "":
		move_speed = 0.0
		return
	_steer(away.normalized(), 4.6 if disarmed else 3.2)
	face_dir = away.normalized() if terrified <= 0.0 else -away.normalized()
	if terrified <= 0.0 and not disarmed:
		state = State.COMBAT


func _steer(dir: Vector3, speed: float) -> void:
	if dir == Vector3.ZERO:
		move_speed = 0.0
		return
	# obstacle whiskers against the world + separation from allies
	var space := get_world_3d().direct_space_state
	var origin := global_position + Vector3(0, 0.7, 0)
	_ray.exclude = _exclude
	var avoid := Vector3.ZERO
	for ang in [-0.6, 0.0, 0.6]:
		var d2 := dir.rotated(Vector3.UP, ang)
		_ray.from = origin
		_ray.to = origin + d2 * 2.2
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			n.y = 0.0
			avoid += n.normalized() * (1.0 if ang == 0.0 else 0.6)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e == self or (e as Enemy).dead:
			continue
		var off: Vector3 = global_position - (e as Node3D).global_position
		off.y = 0.0
		var l := off.length()
		if l < 1.6 and l > 0.01:
			avoid += off / l * (1.6 - l)
	var final := (dir + avoid * 0.8)
	final.y = 0.0
	move_dir = final.normalized() if final.length() > 0.01 else dir
	move_speed = speed
	if state != State.COMBAT:
		face_dir = move_dir


# ------------------------------------------------------------------ hooks

func _update_action(delta: float) -> void:
	# enemies swing a little slower than the player so moves stay readable
	if action == "attack":
		super._update_action(delta * action_speed)
	else:
		super._update_action(delta)


func start_attack(name: String) -> bool:
	var ok := super.start_attack(name)
	if ok:
		action_speed = _rng.randf_range(0.78, 0.9) if style != "brute" else 0.85
	return ok


func receive_hit(info: Dictionary) -> String:
	if state != State.COMBAT and not dead and info.has("attacker") and state != State.FLEE:
		# unaware target hit from behind: much more damage (stealth)
		if not aware and info.get("attacker") is Player:
			info = info.duplicate()
			info.damage = float(info.get("damage", 10.0)) * 3.0
	# chance to raise the guard reactively
	if action == "" and state == State.COMBAT and _rng.randf() < block_chance * 0.5 and not info.get("unblockable", false):
		set_action("block", 0.5)
		block_time = 0.3
	var r := super.receive_hit(info)
	if r != "killed" and not dead:
		become_aware(true)
	if r == "hit" and _pending_attack != "":
		_pending_attack = ""
	return r


func _on_part_severed(part: String, stump: String) -> void:
	super._on_part_severed(part, stump)
	if not dead and disarmed:
		bleeding = 6.0
		terrified = 999.0
		state = State.FLEE
		Audio.play_at("scream", global_position + Vector3(0, 1.6, 0), 2.0, 0.1)


func terrify(duration: float) -> void:
	if dead or style == "leader":
		return
	terrified = duration
	state = State.FLEE
	Audio.play_at("scream", global_position + Vector3(0, 1.6, 0), -2.0, 0.15)
