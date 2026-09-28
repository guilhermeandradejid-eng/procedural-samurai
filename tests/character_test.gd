extends Node3D
## Scripted check of the active ragdoll characters: idle, walk, run, combo,
## kill with dismemberment. Saves screenshots at key moments.
## godot --path . --rendering-driver vulkan --script res://tests/character_test.gd -- <out_dir>

var out_dir := "user://chartest"
var root3d: Node3D
var player: Player
var enemies: Array[Character] = []
var frame := 0
var shots := {}
var cam: Camera3D
var script_steps := []
var _t_last := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	root3d = self
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.66, 0.74)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.63, 0.7)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.environment = e
	root3d.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	root3d.add_child(sun)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	mi.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.4, 0.45, 0.3)
	mi.material_override = gm
	ground.add_child(mi)
	root3d.add_child(ground)
	Game.set_state(Game.State.PLAYING)
	player = Player.new()
	player.name = "Player"
	player.position = Vector3(0, 0.05, 0)
	root3d.add_child(player)
	for i in 2:
		var en := Character.new()
		en.style = ["ronin", "leader"][i]
		en.seed = 11 + i
		en.name = "Enemy%d" % i
		en.team = Character.Team.ENEMY
		en.weapon_drawn = true
		en.combat = true
		en.rotation.y = PI
		en.position = Vector3(-0.6 + i * 1.6, 0.05, -6.0 - i * 1.5)
		root3d.add_child(en)
		en.face_dir = Vector3(0, 0, 1)
		en.add_to_group("enemies")
		enemies.append(en)
	cam = Camera3D.new()
	cam.fov = 60
	root3d.add_child(cam)
	# timeline: [frame, callable]
	script_steps = [
		[30, func() -> void: _shot("idle", Vector3(2.2, 1.6, 3.0), player.global_position + Vector3(0, 1.0, 0))],
		[40, func() -> void: Input.action_press("move_forward")],
		[75, func() -> void: _shot("walk", Vector3(3.0, 1.5, player.global_position.z + 0.5), player.global_position + Vector3(0, 1.0, 0))],
		[90, func() -> void: Input.action_press("sprint")],
		[115, func() -> void: _shot("run", Vector3(3.5, 1.4, player.global_position.z + 1.0), player.global_position + Vector3(0, 1.0, 0))],
		[118, func() -> void:
			Input.action_release("sprint")
			Input.action_release("move_forward")],
		[150, func() -> void: _shot("combat_idle", Vector3(2.4, 1.7, player.global_position.z + 2.0), player.global_position + Vector3(0, 1.1, -1.0))],
		[152, func() -> void: _face_enemy()],
		[160, func() -> void: Input.action_press("attack_light")],
		[162, func() -> void: Input.action_release("attack_light")],
		[168, func() -> void: _shot("attack_windup", Vector3(2.4, 1.6, player.global_position.z + 1.5), player.global_position + Vector3(0, 1.1, -0.5))],
		[174, func() -> void: _shot("attack_strike", Vector3(2.4, 1.6, player.global_position.z + 1.5), player.global_position + Vector3(0, 1.1, -0.5))],
		[180, func() -> void: _kill_enemy(0, "head")],
		[196, func() -> void: _shot("decapitation", enemies[0].global_position + Vector3(2.5, 1.6, 2.0), enemies[0].global_position + Vector3(0, 0.8, 0))],
		[240, func() -> void: _shot("decap_after", enemies[0].global_position + Vector3(2.2, 1.4, 1.6), enemies[0].global_position + Vector3(0, 0.3, 0))],
		[250, func() -> void: _kill_enemy(1, "chest")],
		[300, func() -> void: _shot("bisect", enemies[1].global_position + Vector3(2.2, 1.6, 2.2), enemies[1].global_position + Vector3(0, 0.4, 0))],
		[310, func() -> void: Input.action_press("dodge")],
		[312, func() -> void: Input.action_release("dodge")],
		[322, func() -> void: _shot("roll", player.global_position + Vector3(3.0, 1.2, 1.0), player.global_position + Vector3(0, 0.6, 0))],
		[380, func() -> void: _finish()],
	]


func _face_enemy() -> void:
	player.face_dir = (enemies[0].global_position - player.global_position).normalized()


func _kill_enemy(i: int, part: String) -> void:
	var en := enemies[i]
	var info := {"attacker": player, "part": part, "point": en.chest_position() + Vector3(0, 0.25 if part == "head" else -0.1, 0),
		"dir": Vector3(-1, 0, 0.3).normalized(), "damage": 999.0, "power": 2.0, "cut": "horizontal"}
	var r := en.receive_hit(info)
	print("kill result ", r, " severed=", en.body.severed.keys())


func _shot(n: String, pos: Vector3, target: Vector3) -> void:
	cam.global_position = pos
	cam.look_at(target)
	cam.make_current()
	shots[frame + 2] = n


func _finish() -> void:
	print("pelvis y ", player.body.parts["pelvis"].global_position.y, "  health ", player.health)
	get_tree().quit()


func _process(_d: float) -> void:
	frame += 1
	if frame % 20 == 0 or frame < 12:
		var now := Time.get_ticks_msec()
		print("frame ", frame, "  ms/frame ", (now - _t_last) / 20.0, "  pelvis ", player.body.parts["pelvis"].global_position, " root ", player.global_position, " act ", player.action, " t ", snappedf(player.action_time, 0.01), " drawn ", player.weapon_drawn, " combat_t ", snappedf(player.combat_timer, 0.1))
		_t_last = now
	for s in script_steps:
		if s[0] == frame:
			(s[1] as Callable).call()
	if shots.has(frame):
		var img := get_viewport().get_texture().get_image()
		img.save_png(out_dir.path_join("%03d_%s.png" % [frame, shots[frame]]))
		print("shot ", shots[frame])
