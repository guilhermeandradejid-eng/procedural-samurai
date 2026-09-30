extends Node3D
## Renders every action of a character from two angles at several moments
## and writes PNGs (assemble them with tests/make_sheet.py).
##   xvfb-run godot --path . --rendering-driver vulkan res://tests/pose_gallery.tscn -- <out_dir> [pose,pose]

var out_dir := "user://poses"
var ch: Character
var cam: Camera3D
var only: PackedStringArray = []

## name -> {setup: Callable, times: [seconds after setup]}
var poses := {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	if args.size() > 1:
		only = args[1].split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_environment()
	Game.set_state(Game.State.PLAYING)
	ch = Character.new()
	ch.style = "player"
	ch.team = Character.Team.PLAYER
	ch.position = Vector3(0, 0.05, 0)
	add_child(ch)
	cam = Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.make_current()
	_define()
	_run()


func _environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.68, 0.76)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.58, 0.64)
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
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
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.42, 0.47, 0.32)
	mi.material_override = gm
	ground.add_child(mi)
	add_child(ground)


func _define() -> void:
	var fwd := Vector3(0, 0, -1)
	poses["idle"] = {"setup": func() -> void: ch.weapon_drawn = false, "times": [0.5, 1.5]}
	poses["idle_combat"] = {"setup": func() -> void: _draw(), "times": [0.6, 1.6]}
	poses["walk"] = {"setup": func() -> void: _move(2.1), "times": [1.0, 1.25, 1.5, 1.75]}
	poses["run"] = {"setup": func() -> void: _move(5.2), "times": [1.0, 1.15, 1.3, 1.45]}
	poses["run_sword"] = {"setup": func() -> void:
		_draw()
		_move(5.2), "times": [1.0, 1.15, 1.3, 1.45]}
	poses["sprint"] = {"setup": func() -> void:
		_draw()
		ch.sprinting = true
		_move(7.8), "times": [1.0, 1.1, 1.2, 1.3]}
	poses["crouch"] = {"setup": func() -> void:
		ch.crouching = true
		_move(1.9), "times": [1.0, 1.3]}
	for a in ["light_1", "light_2", "light_3", "heavy", "counter", "iai", "assassinate"]:
		poses[a] = {"setup": func() -> void:
			_draw()
			ch.start_attack(a), "times": _attack_times(a)}
	poses["block"] = {"setup": func() -> void:
		_draw()
		ch.blocking = true
		ch.set_action("block", 999.0), "times": [0.5, 1.0]}
	poses["parry"] = {"setup": func() -> void:
		_draw()
		ch.set_action("parry", 0.34), "times": [0.05, 0.15, 0.28]}
	poses["roll"] = {"setup": func() -> void:
		_draw()
		ch.roll(fwd), "times": [0.1, 0.22, 0.34, 0.46, 0.58]}
	poses["hit"] = {"setup": func() -> void:
		_draw()
		ch.hit_dir = Vector3(0, 0, 1)
		ch.set_action("hit", 0.35)
		ch.body.strength = 0.4, "times": [0.05, 0.15, 0.3]}
	poses["stagger"] = {"setup": func() -> void:
		_draw()
		ch.stagger(Vector3(0, 0, 1), 1.2), "times": [0.1, 0.3, 0.6]}
	poses["knockdown"] = {"setup": func() -> void:
		_draw()
		ch.knockdown(Vector3(0, 2, 6)), "times": [0.2, 0.6, 1.0, 1.6, 2.2, 2.8]}
	poses["sit"] = {"setup": func() -> void: ch.set_action("sit", 999.0), "times": [0.8, 1.6]}
	poses["kneel"] = {"setup": func() -> void: ch.set_action("kneel", 999.0), "times": [0.8, 1.6]}
	poses["pray"] = {"setup": func() -> void: ch.set_action("pray", 999.0), "times": [0.8, 1.6]}
	poses["heal"] = {"setup": func() -> void:
		_draw()
		ch.set_action("heal", 999.0), "times": [0.5, 1.0]}
	poses["chiburi"] = {"setup": func() -> void:
		_draw()
		ch.sheathe_weapon(true), "times": [0.2, 0.5, 0.8, 1.05]}
	poses["draw"] = {"setup": func() -> void:
		ch.draw_weapon(false), "times": [0.1, 0.25, 0.4]}
	poses["standoff"] = {"setup": func() -> void: ch.set_action("standoff", 999.0), "times": [0.6, 1.4]}
	poses["die_head"] = {"setup": func() -> void:
		_draw()
		_kill("head"), "times": [0.3, 0.8, 1.6, 3.0]}
	poses["die_arm"] = {"setup": func() -> void:
		_draw()
		_kill("forearm_r"), "times": [0.15, 0.5, 1.2, 2.5]}
	poses["die_leg"] = {"setup": func() -> void:
		_draw()
		_kill("thigh_l"), "times": [0.15, 0.5, 1.2, 2.5]}
	poses["die_chest"] = {"setup": func() -> void:
		_draw()
		_kill("chest"), "times": [0.3, 0.8, 1.6, 3.0]}


func _attack_times(a: String) -> Array:
	var d: float = AttackLibrary.get_attack(a).get("duration", 0.6)
	return [d * 0.15, d * 0.3, d * 0.45, d * 0.6, d * 0.85]


func _draw() -> void:
	if not ch.weapon_drawn:
		ch.draw_weapon(true)
	ch.combat = true


func _move(speed: float) -> void:
	ch.move_dir = Vector3(0, 0, -1)
	ch.move_speed = speed
	ch.face_dir = Vector3(0, 0, -1)


func _kill(part: String) -> void:
	var info := {"attacker": ch, "part": part, "point": ch.chest_position() + Vector3(0, 0.25 if part == "head" else -0.1, 0),
		"dir": Vector3(-0.6, 0.1, 0.8).normalized(), "damage": 999.0, "power": 2.0, "cut": "horizontal", "blade": Vector3(0.3, 0.2, -0.9)}
	ch.receive_hit(info)


func _reset() -> void:
	ch.queue_free()
	await get_tree().process_frame
	ch = Character.new()
	ch.style = "player"
	ch.team = Character.Team.PLAYER
	ch.position = Vector3(0, 0.05, 0)
	add_child(ch)
	await get_tree().physics_frame
	await get_tree().physics_frame


func _run() -> void:
	await get_tree().create_timer(0.4).timeout
	for name in poses:
		if not only.is_empty() and not (name in only):
			continue
		await _reset()
		for i in 20:
			await get_tree().physics_frame
		var p: Dictionary = poses[name]
		(p.setup as Callable).call()
		var t0 := 0.0
		var view := 0
		for tt in p.times:
			while t0 < float(tt):
				await get_tree().physics_frame
				t0 += 1.0 / Engine.physics_ticks_per_second
			# two cameras: 3/4 front-right and side
			for v in 2:
				var c := ch.global_position
				if ch.body and ch.body.parts.has("pelvis"):
					c = ch.body.parts["pelvis"].global_position
					c.y = clampf(c.y, 0.2, 2.0)
				var focus := Vector3(c.x, clampf(c.y, 0.45, 0.8), c.z)
				var ang := deg_to_rad(-30.0 if v == 0 else 90.0)
				var dist := 3.3
				cam.global_position = focus + Vector3(sin(ang), 0.16, -cos(ang)) * dist
				cam.look_at(focus + Vector3(0, 0.2, 0))
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				img.save_png("%s/%s_%d_%d.png" % [out_dir, name, view, v])
			view += 1
	print("pose gallery done")
	get_tree().quit()
