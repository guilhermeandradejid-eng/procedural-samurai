extends Node3D
## Stills of the combat effects as the player sees them (third-person camera, post-processing
## on): wind slash, afterimages, air ribbon, zoom blur and the cut across the screen.
##   xvfb-run godot --path . --rendering-driver vulkan --resolution 960x540 res://tests/juice_shots.tscn -- <out_dir> [attack,attack]

var out_dir := "user://juice"
var attacks: PackedStringArray = ["light_1", "light_2", "light_3", "heavy", "counter"]
var player: Player
var foe: Enemy
var post: PostFX


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		attacks = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_environment()
	Game.set_state(Game.State.PLAYING)
	post = PostFX.new()
	add_child(post)
	_run()


func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.62, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.64)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.glow_enabled = true
	e.glow_intensity = 0.8
	e.glow_hdr_threshold = 1.0
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	mi.mesh = pm
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var c := ((x / 8) + (y / 8)) % 2 == 0
			img.set_pixel(x, y, Color(0.45, 0.5, 0.34) if c else Color(0.36, 0.42, 0.28))
	var gm := StandardMaterial3D.new()
	gm.albedo_texture = ImageTexture.create_from_image(img)
	gm.uv1_scale = Vector3(100, 100, 1)
	gm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)
	# posts behind the fight so the bending of the picture shows
	for i in 9:
		var post_mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 3.0, 0.25)
		post_mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.85, 0.2, 0.15) if i % 2 == 0 else Color(0.95, 0.95, 0.9)
		post_mi.material_override = m
		post_mi.position = Vector3(-6.0 + i * 1.5, 1.5, -5.5)
		add_child(post_mi)


func _spawn() -> void:
	if player:
		player.queue_free()
		foe.queue_free()
		player.cam_rig.queue_free()
		await get_tree().process_frame
	player = Player.new()
	player.name = "Player"
	player.position = Vector3(0, 0.05, 0)
	add_child(player)
	foe = Enemy.new()
	foe.style = "ronin"
	foe.seed = 9
	foe.idle_mode = "guard"
	foe.position = Vector3(0, 0.05, -1.7)
	foe.rotation.y = PI
	add_child(foe)
	await get_tree().physics_frame
	await get_tree().physics_frame
	player.cam_rig.yaw = 0.35
	player.draw_weapon(true)
	player.combat = true
	foe.process_mode = Node.PROCESS_MODE_INHERIT


func _shot(file: String) -> void:
	get_tree().paused = true
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, file])
	get_tree().paused = false


func _wait(seconds: float) -> void:
	var t := 0.0
	while t < seconds:
		await get_tree().physics_frame
		foe.state = Enemy.State.IDLE
		foe.detection = 0.0
		t += 1.0 / Engine.physics_ticks_per_second


## Holding the heavy attack: embers and glow build up on the blade, a ring snaps out at full charge,
## and an enemy's perilous wind-up glows red.
func _charge_shots() -> void:
	await _spawn()
	player.combat_timer = 30.0     # keep the sword out
	await _wait(0.4)
	Input.action_press("attack_heavy")
	var t := 0.0
	var k := 0
	for tt in [0.3, 0.6, 0.9, 1.02, 1.2]:
		await _wait(tt - t)
		t = tt
		await _shot("charge_%d" % k)
		k += 1
	Input.action_release("attack_heavy")
	await _wait(0.2)
	await _shot("charge_release")
	# the blood on the lens runs down and shrinks away
	for i in 3:
		await _wait(0.9)
		await _shot("lens_%d" % i)
	await _spawn()
	player.combat_timer = 30.0
	foe.draw_weapon(true)
	await _wait(0.4)
	k = 0
	for lvl in [0.35, 0.7, 1.0]:
		for i in 5:
			foe.weapon.charge(lvl, Enemy.PERIL_COLOR)
			await _wait(0.02)
		await _shot("peril_%d" % k)
		k += 1


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	if "charge" in attacks:
		await _charge_shots()
		attacks.remove_at(attacks.find("charge"))
	if "impact" in attacks:
		# the black, white and red frame of a deathblow, mid-swing
		await _spawn()
		player.combat_timer = 30.0
		await _wait(0.4)
		player.start_attack("heavy")
		player.aim_attack_at(foe)
		await _wait(0.2)
		Game.impact_frame.emit(3.0)
		await _shot("impact")
		attacks.remove_at(attacks.find("impact"))
	for name in attacks:
		await _spawn()
		for i in 25:
			await get_tree().physics_frame
			foe.state = Enemy.State.IDLE
			foe.detection = 0.0
		var a := AttackLibrary.get_attack(name)
		var act: Array = a.get("active", [0.15, 0.3])
		var strike := lerpf(float(act[0]), float(act[1]), 0.45)
		player.start_attack(name)
		player.aim_attack_at(foe)
		var shots := [strike - 0.06, strike + 0.0, strike + 0.05, strike + 0.11, strike + 0.2, strike + 0.35]
		var t := 0.0
		var k := 0
		for tt in shots:
			while t < tt:
				await get_tree().physics_frame
				foe.state = Enemy.State.IDLE
				foe.detection = 0.0
				t += 1.0 / Engine.physics_ticks_per_second
			get_tree().paused = true
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%d.png" % [out_dir, name, k])
			get_tree().paused = false
			k += 1
	print("juice shots done")
	get_tree().quit()
