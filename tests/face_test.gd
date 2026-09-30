extends Node3D
## Close-ups of every face: calm, focused, angry, hurt, startled, dead, plus
## the enemy archetypes. godot --path . res://tests/face_test.tscn -- <dir>

var out_dir := "user://faces"
var cam: Camera3D
var chars: Array[Character] = []


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.62, 0.7)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(100, 1, 100)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	Game.set_state(Game.State.PLAYING)
	var styles := ["player", "ronin", "leader", "brute", "spearman"]
	for i in styles.size():
		var c := Character.new()
		c.style = styles[i]
		c.team = Character.Team.PLAYER if i == 0 else Character.Team.ENEMY
		c.seed = 40 + i
		c.position = Vector3(i * 1.4 - 2.8, 0.05, 0)
		c.rotation.y = PI
		add_child(c)
		chars.append(c)
	cam = Camera3D.new()
	cam.fov = 32
	add_child(cam)
	cam.make_current()
	_run()


func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	var moods := {
		"calm": func(c: Character) -> void: c.combat = false,
		"angry": func(c: Character) -> void: c.set_action("attack", 99.0),
		"hurt": func(c: Character) -> void: c.set_action("hit", 99.0),
		"dead": func(c: Character) -> void: c.dead = true,
	}
	for m in moods:
		for c in chars:
			c.action = ""
			c.dead = false
			(moods[m] as Callable).call(c)
			c.look_target = cam.global_position + Vector3(0.4, 0.0, 0)
		await get_tree().create_timer(0.55 if m != "hurt" else 0.12).timeout
		for i in chars.size():
			var c := chars[i]
			var head: Vector3 = c.body.part_transform("head").origin
			cam.global_position = head + Vector3(0.0, 0.05, 1.35)
			cam.look_at(head + Vector3(0, 0.0, 0))
			c.look_target = cam.global_position + Vector3(0.35, 0.05, 0.0)
			await get_tree().create_timer(0.1).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/face_%s_%d.png" % [out_dir, m, i])
	print("faces done")
	get_tree().quit()
