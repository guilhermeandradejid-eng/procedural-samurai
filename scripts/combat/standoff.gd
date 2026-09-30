class_name Standoff
extends Node
## The Ghost of Tsushima standoff: the samurai challenges a group, one
## champion steps forward, and the player holds the strike button until the
## enemy commits. Releasing in the 0.4 s window after the real lunge kills
## with a single iai draw; releasing on a feint, or too late, costs a wound.
## Each success can chain into the next foe rushing in.

signal finished(success: bool, kills: int)

enum Phase { APPROACH, WAIT, LUNGE, RESOLVE, DONE }

const WINDOW := 0.42
const DIST := 5.2

var player: Player
var foes: Array[Enemy] = []
var current: Enemy
var phase := Phase.APPROACH
var kills := 0
var max_chain := 3
var _t := 0.0
var _wait := 2.0
var _feints := 0
var _held := false
var _cam_set := false
var _ui: UIRoot


func start(p: Player, candidates: Array[Enemy], ui: UIRoot) -> void:
	player = p
	foes = candidates
	_ui = ui
	player.input_enabled = false
	player.sheathe_weapon(false)
	player.set_action("standoff", 999.0)
	player.move_speed = 0.0
	if player.lock_target:
		player.lock_target = null
	Audio.play_at("alert_shout", foes[0].global_position + Vector3(0, 1.6, 0), 0.0, 0.1, 60.0)
	# the whole group knows, but holds back to watch
	for e in foes:
		if e.encounter:
			(e.encounter as Encounter).max_tokens = 0
		e.become_aware(false)
		e.standoff_mode = true
		e.move_speed = 0.0
	_next_foe()
	if _ui:
		_ui.post.set_letterbox(true)
		Game.show_banner("CONFRONTO", "Segure o botão de golpe... solte quando o inimigo atacar", "info")
	Audio.music_duck = 0.25
	Game.show_toast("Segure o golpe e solte no ataque")


func _next_foe() -> void:
	current = null
	for e in foes:
		# the terrified and the far away do not answer the challenge
		if is_instance_valid(e) and not e.dead and not e.disarmed and e.terrified <= 0.0 \
				and e.global_position.distance_to(player.global_position) < 26.0:
			current = e
			break
	if current == null or kills >= max_chain:
		_end(true)
		return
	phase = Phase.APPROACH
	_t = 0.0
	_wait = randf_range(1.6, 4.2) if kills == 0 else randf_range(0.5, 1.2)
	_feints = 1 if randf() < 0.4 else 0
	current.set_action("", 0.0)


func _physics_process(delta: float) -> void:
	if phase == Phase.DONE:
		return
	if player == null or player.dead:
		_end(false)
		return
	var real := delta / maxf(Engine.time_scale, 0.02)
	_t += real
	var held := Input.is_action_pressed("attack_light") or Input.is_action_pressed("attack_heavy")
	var released := _held and not held
	_held = held
	_frame_camera()
	if current == null or not is_instance_valid(current) or current.dead:
		_next_foe()
		return
	var to := current.global_position - player.global_position
	to.y = 0.0
	var d := to.length()
	player.face_dir = to.normalized()
	current.face_dir = -to.normalized()
	current.look_target = player.chest_position()
	if phase == Phase.APPROACH and _t > 7.0:
		_end(kills > 0)   # nobody came forward
		return
	match phase:
		Phase.APPROACH:
			# the champion walks up to the duelling distance, weapon drawn
			if not current.weapon_drawn:
				current.draw_weapon(true)
			if d > DIST:
				current.move_dir = -to.normalized()
				current.move_speed = 1.6 if kills == 0 else 5.5
			else:
				current.move_speed = 0.0
				current.set_action("standoff", 999.0)
				phase = Phase.WAIT
				_t = 0.0
			# other foes keep their distance
			for e in foes:
				if e != current and is_instance_valid(e) and not e.dead:
					var o := e.global_position - player.global_position
					o.y = 0.0
					e.face_dir = -o.normalized()
					e.move_speed = 1.2 if o.length() < 9.0 else 0.0
					e.move_dir = o.normalized()
			if released and phase == Phase.APPROACH and kills == 0:
				pass   # too early is harmless while they walk in
		Phase.WAIT:
			if released:
				_fail("cedo demais")
				return
			if _feints > 0 and _t > _wait * 0.55:
				_feints -= 1
				# a twitch of the shoulders and a shout: do not flinch!
				current.external_velocity += to.normalized() * -1.8
				current.body.impulse("chest", -to.normalized() * 30.0)
				Audio.play_at("huh", current.global_position + Vector3(0, 1.6, 0), 2.0, 0.2, 40.0)
				_wait += 1.2
			if _t >= _wait:
				phase = Phase.LUNGE
				_t = 0.0
				current.end_action()
				current.start_attack("enemy_heavy" if current.weapon_kind == "katana" else AttackLibrary.moves_for(current.weapon_kind)[0])
				current.action_speed = 0.7
				current.weapon.glint(Color(1.0, 0.9, 0.7), 0.8)
				Audio.play_at("alert_shout", current.global_position + Vector3(0, 1.6, 0), 3.0, 0.1, 60.0)
				player.invulnerable = WINDOW + 0.3   # the outcome is decided by timing, not by the blade
		Phase.LUNGE:
			if released and _t <= WINDOW:
				_strike()
			elif _t > WINDOW:
				_fail("tarde demais")
		Phase.RESOLVE:
			if _t > 1.3:
				_next_foe()


func _strike() -> void:
	phase = Phase.RESOLVE
	_t = 0.0
	var target := current
	player.set_action("", 0.0)
	player.start_attack("iai")
	player.aim_attack_at(target)
	target.end_action()
	target.set_action("hit", 1.0)
	Game.slowmo(1.8, 0.15)
	Game.kill_cam_requested.emit(target, 1.5)
	Audio.play("perfect", -2.0)
	# the draw is faster than the eye: guarantee the cut
	get_tree().create_timer(0.1).timeout.connect(func() -> void:
		if is_instance_valid(target) and not target.dead:
			var dir := (target.global_position - player.global_position).normalized()
			var info := {"attacker": player, "part": "chest" if randf() < 0.6 else "head", "point": target.chest_position(),
				"dir": dir, "damage": 999.0, "power": 3.0, "attack": "iai", "unblockable": true, "cut": "horizontal"}
			target.receive_hit(info)
			player.hit_landed.emit(player, target, "killed", info))
	kills += 1
	SaveGame.data["standoff_kills"] = int(SaveGame.data.get("standoff_kills", 0)) + 1
	player.add_resolve_charge(0.5)
	if kills == 1:
		Game.show_toast("Confronto vencido")
	else:
		Game.show_toast("Confronto em cadeia x%d" % kills)


func _fail(why: String) -> void:
	Game.show_toast("Confronto perdido (%s)" % why)
	var info := {"attacker": current, "part": "chest", "point": player.chest_position(),
		"dir": (player.global_position - current.global_position).normalized(), "damage": player.max_health * 0.4,
		"power": 1.8, "attack": "enemy_heavy", "unblockable": true}
	player.set_action("", 0.0)
	player.invulnerable = 0.0
	player.receive_hit(info)
	_end(false)


func _end(success: bool) -> void:
	if phase == Phase.DONE:
		return
	phase = Phase.DONE
	for e in foes:
		if is_instance_valid(e) and not e.dead:
			e.standoff_mode = false
			if e.encounter:
				(e.encounter as Encounter).max_tokens = 2
			e.state = Enemy.State.COMBAT
			if success and kills >= 2 and randf() < 0.5:
				e.terrify(randf_range(3.0, 6.0))
	if player and not player.dead:
		player.input_enabled = true
		if player.action == "standoff":
			player.end_action()
		player.combat_timer = 7.0
	if _ui:
		_ui.post.set_letterbox(false)
	Audio.music_duck = 1.0
	if player and player.cam_rig:
		player.cam_rig.end_cinematic()
	finished.emit(success, kills)
	queue_free()


func _frame_camera() -> void:
	if player.cam_rig == null or current == null or not is_instance_valid(current):
		return
	if phase == Phase.RESOLVE:
		return
	var a := player.global_position
	var b := current.global_position
	var mid := (a + b) * 0.5 + Vector3(0, 1.3, 0)
	var line := b - a
	line.y = 0.0
	if line.length() < 0.1:
		return
	var side := line.normalized().cross(Vector3.UP)
	var pos := mid + side * 4.2 - line.normalized() * 1.2 + Vector3(0, 0.2, 0)
	var wd := WorldData.current
	if wd:
		pos.y = maxf(pos.y, wd.get_height(pos.x, pos.z) + 0.5)
	var xf := Transform3D(Basis(), pos).looking_at(mid, Vector3.UP)
	player.cam_rig.cinematic(xf, 0.5, 42.0)
