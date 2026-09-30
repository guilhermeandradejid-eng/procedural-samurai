extends Node3D
## Measures the cost of ProceduralAnimator.update() (clip sampling, blending, FK, IK, feet)
## for many characters. Run: godot --headless --path . res://tests/anim_bench.tscn

const N := 30


func _ready() -> void:
	Game.set_state(Game.State.PLAYING)
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	var chars: Array[Character] = []
	for i in N:
		var c := Character.new()
		c.style = "ronin"
		c.position = Vector3(float(i % 6) * 3.0, 0.05, float(i / 6) * 3.0)
		add_child(c)
		chars.append(c)
	await get_tree().physics_frame
	await get_tree().physics_frame
	for c in chars:
		c.draw_weapon(true)
	var modes := {"idle": 0.0, "walk": 1.4, "run": 3.9, "sprint": 5.7}
	for mode in modes:
		for c in chars:
			c.move_dir = Vector3(0, 0, -1)
			c.move_speed = modes[mode]
		for i in 20:
			await get_tree().physics_frame
		var t0 := Time.get_ticks_usec()
		var frames := 60
		for i in frames:
			for c in chars:
				c.animator.update(1.0 / 60.0, c.anim_state())
		var us := float(Time.get_ticks_usec() - t0) / float(frames * N)
		print("%-8s %.0f us per character update" % [mode, us])
	for a in ["light_1", "light_2", "heavy"]:
		for c in chars:
			c.end_action()
			c.start_attack(a)
		for i in 6:
			await get_tree().physics_frame
		var t0 := Time.get_ticks_usec()
		for i in 30:
			for c in chars:
				c.animator.update(1.0 / 60.0, c.anim_state())
		print("%-8s %.0f us per character update" % [a, float(Time.get_ticks_usec() - t0) / float(30 * N)])
	get_tree().quit()
