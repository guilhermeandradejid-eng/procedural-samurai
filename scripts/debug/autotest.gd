extends Node
## Automated play-test (godot --path . -- --play --autotest [out_dir] [shots]):
## drops the player 50 m from the nearest camp, walks in and fights with a
## simple bot (blocks wind-ups, strikes back, heals), logging what happens.
## With "shots" it also saves screenshots (use a rendering driver).

var out_dir := "user://autotest"
var shots := false
var frame := 0
var player: Player
var camp := {}
var log_lines: PackedStringArray = []
var stats := {"kills": 0, "damage_taken": 0.0, "hits": 0, "blocked": 0, "parried": 0, "severed": 0}
var _bot_t := 0.0
var _block_hold := 0.0
var _shot_every := 180
var _approach := 40.0
var _done := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	var i := args.find("--autotest")
	if i + 1 < args.size() and not args[i + 1].begins_with("--"):
		out_dir = args[i + 1]
	shots = args.has("shots")
	DirAccess.make_dir_recursive_absolute(out_dir)
	if shots:
		Settings.values.quality = 0
		var w := Game.world as World
		w.apply_quality()
		if args.has("lowgfx"):
			# software-rendered captures: drop the most expensive effects
			w.env.volumetric_fog_enabled = false
			w.env.ssao_enabled = false
			w.env.glow_enabled = false
			w.grass.visible = false
			w.sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			w.sun.directional_shadow_max_distance = 60.0
	_shot_every = int(OS.get_environment("AUTOTEST_SHOT_EVERY")) if OS.get_environment("AUTOTEST_SHOT_EVERY") != "" else 180
	_approach = float(OS.get_environment("AUTOTEST_APPROACH")) if OS.get_environment("AUTOTEST_APPROACH") != "" else 40.0
	Game.enemy_killed.connect(func(e: Node, _i: Dictionary) -> void:
		stats.kills += 1
		_log("killed %s" % e.name))
	Game.player_damaged.connect(func(a: float, _d: Vector3) -> void:
		stats.damage_taken += a
		_log("player hit -%.0f hp %.0f" % [a, player.health if player else 0.0]))
	Game.camp_cleared.connect(func(id: String) -> void: _log("CAMP CLEARED " + id))
	Game.banner.connect(func(t: String, s: String, _st: String) -> void: _log("banner: %s / %s" % [t, s.replace("\n", " ")]))


func _log(s: String) -> void:
	var line := "[%5d] %s" % [frame, s]
	print(line)
	log_lines.append(line)


func _physics_process(delta: float) -> void:
	frame += 1
	if player == null:
		player = Game.get_player()
		return
	if frame == 30:
		_place_near_camp()
	if frame < 40 or _done:
		return
	if frame % 120 == 0:
		var enemies := get_tree().get_nodes_in_group("enemies")
		var states := {}
		for e in enemies:
			var en := e as Enemy
			if en and not en.dead:
				var k: String = Enemy.State.keys()[en.state]
				states[k] = int(states.get(k, 0)) + 1
		var cc := Vector3(float(camp.x), 0, float(camp.z))
		var coll := []
		for k in player.get_slide_collision_count():
			var col := player.get_slide_collision(k)
			var o := col.get_collider()
			coll.append("%s@%s" % [o.name if o is Node else str(o), col.get_normal().snapped(Vector3.ONE * 0.01)])
		var ne := INF
		for e in enemies:
			var en := e as Enemy
			if en and not en.dead:
				ne = minf(ne, en.global_position.distance_to(player.global_position))
		_log("player hp %.0f action=%s pos %s camp_d %.1f nearest_enemy %.1f | enemies %s | coll %s vel %s" % [player.health, player.action, player.global_position.snapped(Vector3.ONE * 0.1),
			Vector2(cc.x - player.global_position.x, cc.z - player.global_position.z).length(), ne, states, coll, player.velocity.snapped(Vector3.ONE * 0.01)])
	if shots and frame % _shot_every == 0:
		_shot()
	if player.dead:
		_log("PLAYER DIED")
		_finish()
		return
	var mode := OS.get_environment("AUTOTEST_MODE")
	if mode == "standoff":
		_standoff_bot()
		return
	if mode == "assassinate":
		_assassin_bot()
		return
	_bot(delta)
	if frame > int(OS.get_environment("AUTOTEST_FRAMES")) if OS.get_environment("AUTOTEST_FRAMES") != "" else frame > 60 * 150:
		_finish()


func _place_near_camp() -> void:
	var d := WorldData.current
	var best := {}
	var bd := INF
	for p in d.pois:
		if p.type != "camp":
			continue
		var dist := Vector2(float(p.x) - player.global_position.x, float(p.z) - player.global_position.z).length()
		if dist < bd:
			bd = dist
			best = p
	camp = best
	var c := Vector3(float(camp.x), 0, float(camp.z))
	var road := (Game.world as World).settlements._entrance_dir(camp)
	var at := c + Vector3(road.x, 0, road.y) * (float(camp.get("radius", 20.0)) + _approach)
	at.y = d.get_height(at.x, at.z)
	player.respawn(at + Vector3(0, 0.05, 0))
	_log("placed near camp %s (%s) at %s" % [camp.id, camp.get("name", ""), at.snapped(Vector3.ONE)])


func _bot(delta: float) -> void:
	_bot_t -= delta
	var c := Vector3(float(camp.x), player.global_position.y, float(camp.z))
	var nearest: Enemy = null
	var nd := INF
	var winding := false
	for e in get_tree().get_nodes_in_group("enemies"):
		var en := e as Enemy
		if en == null or en.dead:
			continue
		var d := en.global_position.distance_to(player.global_position)
		if en.state == Enemy.State.COMBAT or d < 12.0:
			if d < nd:
				nd = d
				nearest = en
		if (en._pending_attack != "" or (en.action == "attack" and en.action_time < float(en.attack.get("active", [0.3])[0]))) and d < 4.5:
			winding = true
	if _block_hold > 0.0:
		_block_hold -= delta
		if _block_hold <= 0.0:
			Input.action_release("block")
		return
	if player.health < player.max_health * 0.45 and player.resolve > 0 and player.action == "" and _bot_t <= 0.0:
		_tap("heal")
		_bot_t = 1.2
		return
	var target := c
	if nearest:
		target = nearest.global_position
	var to := target - player.global_position
	to.y = 0.0
	if player.cam_rig:
		player.cam_rig.yaw = lerp_angle(player.cam_rig.yaw, atan2(-to.x, -to.z), 0.2)
	if nearest == null:
		# walk (crouched once close) towards the camp
		Input.action_press("move_forward")
		if to.length() < 30.0 and not player.crouching and frame % 200 == 0:
			pass
		return
	if winding and randf() < 0.85:
		Input.action_release("move_forward")
		Input.action_press("block")
		_block_hold = 0.45
		return
	if nd < 3.2:
		Input.action_release("move_forward")
		if _bot_t <= 0.0 and player.action in ["", "block"]:
			_tap("attack_light")
			_bot_t = 0.32
	else:
		Input.action_press("move_forward")


var _so_phase := -1


func _standoff_bot() -> void:
	var main := get_parent()
	if frame == 100:
		Input.action_press("attack_light")
		main._try_standoff()
		_log("standoff requested, candidates %d" % player.standoff_candidates().size())
	var so: Standoff = main._standoff if is_instance_valid(main._standoff) else null
	if so == null:
		if frame > 110 and _so_phase != 99:
			_so_phase = 99
			Input.action_release("attack_light")
			_log("standoff over")
		if frame > 110:
			_bot(get_physics_process_delta_time())
		return
	if int(so.phase) != _so_phase:
		_so_phase = int(so.phase)
		_log("standoff phase %s kills %d" % [Standoff.Phase.keys()[_so_phase], so.kills])
	if frame % 60 == 0 and so.current:
		var c := so.current
		_log("  current %s d %.1f spd %.1f dir %s action %s state %s terrified %.1f vel %s" % [c.name, c.global_position.distance_to(player.global_position), c.move_speed, c.move_dir, c.action, c.state, c.terrified, c.velocity])
	if so.phase == Standoff.Phase.LUNGE and so._t > 0.15:
		Input.action_release("attack_light")
	elif so.phase in [Standoff.Phase.APPROACH, Standoff.Phase.WAIT] and not Input.is_action_pressed("attack_light"):
		Input.action_press("attack_light")


func _assassin_bot() -> void:
	if frame == 80:
		for e in get_tree().get_nodes_in_group("enemies"):
			var en := e as Enemy
			if en and not en.dead and en.state == Enemy.State.IDLE:
				var back := en.global_basis.z
				var at := en.global_position + back * 1.4
				at.y = WorldData.current.get_height(at.x, at.z)
				player.global_position = at + Vector3(0, 0.05, 0)
				player.crouching = true
				_log("teleported behind %s (idle_mode %s)" % [en.name, en.idle_mode])
				break
	if frame == 95:
		var t := player.assassination_target()
		_log("assassination target: %s" % [t.name if t else "none"])
		_tap("interact")
	if frame > 200:
		_bot(get_physics_process_delta_time())


func _tap(action: String) -> void:
	# a real input event, so _unhandled_input handlers see it too
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	get_tree().create_timer(0.06, true, false, true).timeout.connect(func() -> void:
		var up := InputEventAction.new()
		up.action = action
		up.pressed = false
		Input.parse_input_event(up))


func _shot() -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/game_%05d.png" % [out_dir, frame])


func _finish() -> void:
	if _done:
		return
	_done = true
	_log("STATS %s" % [stats])
	var f := FileAccess.open(out_dir + "/autotest_log.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
	get_tree().quit()
