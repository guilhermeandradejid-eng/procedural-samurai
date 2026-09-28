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
	var at := c + Vector3(road.x, 0, road.y) * (float(camp.get("radius", 20.0)) + 40.0)
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


func _tap(action: String) -> void:
	Input.action_press(action)
	get_tree().create_timer(0.06, true, false, true).timeout.connect(func() -> void: Input.action_release(action))


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
