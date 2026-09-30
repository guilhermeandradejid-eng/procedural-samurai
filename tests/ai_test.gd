extends Node3D
## Enemy AI check: an encounter of four enemies standing guard notices the
## player, closes in, circles and attacks with tokens. A tiny bot drives the
## player (blocks when an enemy winds up, strikes back otherwise).
## Headless:  godot --headless --path . res://tests/ai_test.tscn -- <out_dir>
## Rendered:  xvfb-run godot --path . res://tests/ai_test.tscn -- <out_dir> shots
## env AI_TRACE=<frame> logs the blade tip against the nearest foe for every attack frame after it.

var out_dir := "user://aitest"
var shots_on := false
var player: Player
var enc: Encounter
var frame := 0
var cam: Camera3D
var log_lines: PackedStringArray = []
var stats := {"enemy_attacks": 0, "player_hits_taken": 0, "blocked": 0, "parried": 0, "enemy_kills": 0,
	"player_attacks": 0, "first_combat_frame": -1, "tokens_max": 0}
var _states := {}
var _bot_timer := 0.0
var _block_hold := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	shots_on = args.size() > 1 and args[1] == "shots"
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.66, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.63, 0.7)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(300, 1, 300)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(300, 300)
	mi.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.4, 0.45, 0.3)
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)
	Game.set_state(Game.State.PLAYING)
	player = Player.new()
	player.name = "Player"
	player.position = Vector3(0, 0.05, 0)
	add_child(player)
	enc = Encounter.new()
	enc.id = "test_camp"
	enc.kind = "camp"
	enc.position = Vector3(0, 0, -16)
	add_child(enc)
	var styles := ["ronin", "spearman", "brute", "leader"]
	for i in styles.size():
		var en := Enemy.new()
		en.style = styles[i]
		en.seed = 100 + i
		en.name = "E_%s" % styles[i]
		en.idle_mode = "guard" if i != 1 else "sit"
		var ang := TAU * float(i) / styles.size()
		en.position = Vector3(cos(ang), 0.0, sin(ang)) * 3.0 + Vector3(0, 0.05, 0)   # local to the encounter
		# first one faces the player so detection starts from sight
		en.rotation.y = 0.0 if i != 0 else PI
		enc.add_child(en)
		enc.add_enemy(en)
		en.attack_started.connect(func(c: Character, a: Dictionary) -> void:
			stats.enemy_attacks += 1
			_log("%s attacks %s dist %.2f" % [c.name, a.get("name", "?"), c.global_position.distance_to(player.global_position)]))
		en.hit_landed.connect(func(c: Character, t: Character, r: String, _i: Dictionary) -> void:
			_log("%s hit %s -> %s" % [c.name, t.name, r]))
		en.died.connect(func(c: Character, _i: Dictionary) -> void:
			stats.enemy_kills += 1
			_log("KILLED %s severed=%s" % [c.name, c.body.severed.keys()]))
	player.hit_landed.connect(func(_c: Character, t: Character, r: String, _i: Dictionary) -> void:
		_log("player hit %s -> %s" % [t.name, r]))
	player.damaged.connect(func(_c: Character, amount: float, _i: Dictionary) -> void:
		stats.player_hits_taken += 1
		_log("player damaged %.1f hp=%.1f" % [amount, player.health]))
	enc.cleared.connect(func(_e: Encounter) -> void: _log("ENCOUNTER CLEARED"))
	cam = Camera3D.new()
	cam.fov = 60
	add_child(cam)
	cam.make_current()


func _log(s: String) -> void:
	var line := "[%4d] %s" % [frame, s]
	print(line)
	log_lines.append(line)


func _physics_process(delta: float) -> void:
	frame += 1
	# state transitions
	var tok := 0
	for en in enc.enemies:
		if not is_instance_valid(en):
			continue
		var s: String = Enemy.State.keys()[en.state]
		if _states.get(en.name, "") != s:
			_states[en.name] = s
			_log("%s -> %s (det %.2f, action=%s)" % [en.name, s, en.detection, en.action])
			if s == "COMBAT" and stats.first_combat_frame < 0:
				stats.first_combat_frame = frame
		if en.has_token and not en.dead:
			tok += 1
	stats.tokens_max = maxi(stats.tokens_max, tok)
	for en3 in enc.alive():
		if en3.velocity.length() > 8.0 and _states.get("fast_" + en3.name, 0) < 12:
			_states["fast_" + en3.name] = _states.get("fast_" + en3.name, 0) + 1
			_log("FAST %s vel %s ext %s act %s t %.2f floor %s pos %s pelvis %s" % [en3.name, en3.velocity, en3.external_velocity, en3.action, en3.action_time, en3.is_on_floor(), en3.global_position, en3.body.parts["pelvis"].global_position])
	if frame > 300 and frame % 60 == 0:
		_log("PLAYER action=%s t=%.2f drawn=%s block=%s combat=%s" % [player.action, player.action_time, player.weapon_drawn, player.blocking, player.combat])
		for en2 in enc.alive():
			_log("   %s st=%s act=%s t=%.2f tok=%s cd=%.2f pend=%s d=%.2f spd=%.1f" % [en2.name, en2.state, en2.action, en2.action_time, en2.has_token, en2.attack_cooldown, en2._pending_attack, en2.global_position.distance_to(player.global_position), en2.move_speed])
	if frame < 260 and frame % 20 == 0:
		var r0: Enemy = enc.enemies[0]
		_log("ronin det %.2f state %s yaw %.2f pos %s pp %s" % [r0.detection, r0.state, r0.rotation.y, r0.global_position, player.global_position])
	# phase 1 (0-120): stand still, visible, at 16 m; phase 2: walk closer
	if frame == 60:
		Input.action_press("move_forward")
	if frame == 100:
		Input.action_release("move_forward")
	if frame > 150 and not player.dead:
		_bot(delta)
	if OS.get_environment("AI_TRACE") != "" and frame > int(OS.get_environment("AI_TRACE")) and player.action == "attack":
		var near: Enemy = null
		var nd2 := INF
		for en4 in enc.alive():
			var d4 := en4.global_position.distance_to(player.global_position)
			if d4 < nd2:
				nd2 = d4
				near = en4
		if near:
			var pv := player.global_transform.affine_inverse()
			_log("  atk %s t=%.2f sweep=%s tip=%s foe_chest=%s foe_act=%s d=%.2f step=%.2f tgt=%s" % [player.attack.get("name", "?"), player.action_time, player.weapon.sweeping,
				_v(pv * player.weapon.tip()), _v(pv * near.chest_position()), near.action, nd2, player.attack_step, player.attack_target.name if player.attack_target else "-"])
	if shots_on and frame in [40, 200, 320, 480, 640, 800]:
		_shot()
	if frame == 1400 or (enc.alive().is_empty() and frame > 200 and _states.get("done", "") == ""):
		_states["done"] = "1"
		get_tree().create_timer(1.8).timeout.connect(_finish)


func _bot(delta: float) -> void:
	_bot_timer -= delta
	# nearest threat
	var best: Enemy = null
	var bd := INF
	for en in enc.alive():
		var d := en.global_position.distance_to(player.global_position)
		if d < bd:
			bd = d
			best = en
	if best == null:
		return
	var winding := false
	for en in enc.alive():
		if (en._pending_attack != "" or (en.action == "attack" and en.action_time < float(en.attack.get("active", [0.3])[0]))) \
				and en.global_position.distance_to(player.global_position) < 4.0:
			winding = true
	if _block_hold > 0.0:
		_block_hold -= delta
		if _block_hold <= 0.0:
			Input.action_release("block")
		return
	if winding and randf() < 0.9:
		Input.action_press("block")
		_block_hold = 0.5
		return
	if bd < 2.6 and _bot_timer <= 0.0 and player.action == "":
		_bot_timer = 0.45
		Input.action_press("attack_light")
		stats.player_attacks += 1
		_log("player attacks, nearest %s at %.2f" % [best.name, bd])
		get_tree().create_timer(0.05).timeout.connect(func() -> void: Input.action_release("attack_light"))
	elif bd > 3.0:
		# step towards the nearest enemy
		var to := best.global_position - player.global_position
		if player.cam_rig:
			player.cam_rig.yaw = atan2(-to.x, -to.z)
		Input.action_press("move_forward")
		get_tree().create_timer(0.1).timeout.connect(func() -> void: Input.action_release("move_forward"))


func _v(v: Vector3) -> String:
	return "(%.2f %.2f %.2f)" % [v.x, v.y, v.z]


func _shot() -> void:
	var c := player.global_position
	var focus := enc.global_position
	if not enc.alive().is_empty():
		focus = enc.alive()[0].global_position
	var mid := (c + focus) * 0.5
	cam.global_position = mid + Vector3(6.0, 3.5, 6.0)
	cam.look_at(mid + Vector3(0, 0.8, 0))
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/ai_%04d.png" % [out_dir, frame])


func _finish() -> void:
	_log("STATS %s" % [stats])
	_log("player hp %.1f dead=%s" % [player.health, player.dead])
	var f := FileAccess.open(out_dir + "/ai_log.txt", FileAccess.WRITE)
	if f:
		f.store_string("\n".join(log_lines))
	get_tree().quit()
