extends Node3D
## How well does the physical ragdoll follow the animation? For every action it
## runs the animator for a while and prints the largest and the mean distance (cm)
## between each body group and where the clip wants it.
##   godot --headless --path . res://tests/track_test.tscn [-- action,action]

const GROUPS := {
	"torso": ["pelvis", "belly", "chest", "head"],
	"arm_r": ["upper_arm_r", "forearm_r", "hand_r"],
	"arm_l": ["upper_arm_l", "forearm_l", "hand_l"],
	"leg_r": ["thigh_r", "shin_r", "foot_r"],
	"leg_l": ["thigh_l", "shin_l", "foot_l"],
}

var ch: Character
var cases := {}
var only: PackedStringArray = []
var verbose := OS.get_environment("TRACK_VERBOSE")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0].split(",")
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400, 1, 400)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	Game.set_state(Game.State.PLAYING)
	_define()
	_run()


func _define() -> void:
	var fwd := Vector3(0, 0, -1)
	cases["idle"] = {"setup": func() -> void: ch.weapon_drawn = false, "t": 1.5}
	cases["guard"] = {"setup": func() -> void: _draw(), "t": 1.5}
	cases["walk"] = {"setup": func() -> void: _move(1.4), "t": 3.0}
	cases["run"] = {"setup": func() -> void: _move(3.9), "t": 3.0}
	cases["run_sword"] = {"setup": func() -> void:
		_draw()
		_move(3.9), "t": 3.0}
	cases["sprint"] = {"setup": func() -> void:
		_draw()
		ch.sprinting = true
		_move(5.7), "t": 3.0}
	cases["crouch"] = {"setup": func() -> void:
		ch.crouching = true
		_move(1.2), "t": 3.0}
	for a in ["light_1", "light_2", "light_3", "heavy", "counter", "iai", "assassinate"]:
		cases[a] = {"setup": func() -> void:
			_draw()
			ch.start_attack(a), "t": float(AttackLibrary.get_attack(a).get("duration", 0.6)) + 0.2}
	cases["block"] = {"setup": func() -> void:
		_draw()
		ch.blocking = true
		ch.set_action("block", 999.0), "t": 1.5}
	cases["parry"] = {"setup": func() -> void:
		_draw()
		ch.set_action("parry", 0.34), "t": 0.4}
	cases["roll"] = {"setup": func() -> void:
		_draw()
		ch.roll(fwd), "t": 0.8}
	cases["stagger"] = {"setup": func() -> void:
		_draw()
		ch.stagger(Vector3(0, 0, 1), 1.2), "t": 1.2}
	cases["sit"] = {"setup": func() -> void: ch.set_action("sit", 999.0), "t": 2.0}
	cases["kneel"] = {"setup": func() -> void: ch.set_action("kneel", 999.0), "t": 2.0}
	cases["pray"] = {"setup": func() -> void: ch.set_action("pray", 999.0), "t": 2.0}
	cases["heal"] = {"setup": func() -> void:
		_draw()
		ch.set_action("heal", 999.0), "t": 1.5}
	cases["chiburi"] = {"setup": func() -> void:
		_draw()
		ch.sheathe_weapon(true), "t": 1.2}
	cases["draw"] = {"setup": func() -> void: ch.draw_weapon(false), "t": 0.6}
	cases["standoff"] = {"setup": func() -> void: ch.set_action("standoff", 999.0), "t": 1.5}


func _v(v: Vector3) -> String:
	return "(%.3f %.3f %.3f)" % [v.x, v.y, v.z]


func _draw() -> void:
	if not ch.weapon_drawn:
		ch.draw_weapon(true)
	ch.combat = true


func _move(speed: float) -> void:
	ch.move_dir = Vector3(0, 0, -1)
	ch.move_speed = speed
	ch.face_dir = Vector3(0, 0, -1)


func _reset() -> void:
	if ch:
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
	print("%-12s %s" % ["action", "   ".join(GROUPS.keys().map(func(k: String) -> String: return "%s max/mean" % k))])
	for name in cases:
		if not only.is_empty() and not (name in only):
			continue
		await _reset()
		for i in 20:
			await get_tree().physics_frame
		var c: Dictionary = cases[name]
		(c.setup as Callable).call()
		var frames := int(float(c.t) * float(Engine.physics_ticks_per_second))
		var mx := {}
		var sm := {}
		for g in GROUPS:
			mx[g] = 0.0
			sm[g] = 0.0
		for f in frames:
			if OS.get_environment("TRACK_KNEE") != "" and f < 80:
				var bt: Basis = (ch.body.targets["thigh_l"] as Transform3D).basis.orthonormalized().inverse() * (ch.body.targets["shin_l"] as Transform3D).basis.orthonormalized()
				var bp: Basis = (ch.body.parts["thigh_l"] as Node3D).global_basis.orthonormalized().inverse() * (ch.body.parts["shin_l"] as Node3D).global_basis.orthonormalized()
				var ht: Basis = (ch.body.targets["pelvis"] as Transform3D).basis.orthonormalized().inverse() * (ch.body.targets["thigh_l"] as Transform3D).basis.orthonormalized()
				var hp: Basis = (ch.body.parts["pelvis"] as Node3D).global_basis.orthonormalized().inverse() * (ch.body.parts["thigh_l"] as Node3D).global_basis.orthonormalized()
				print("knee f%d tgt %.0f phys %.0f | hip(x) tgt %.0f phys %.0f | shin w %.1f thigh w %.1f" % [f, rad_to_deg(bt.get_euler().x), rad_to_deg(bp.get_euler().x), rad_to_deg(ht.get_euler().x), rad_to_deg(hp.get_euler().x),
					((ch.body.parts["shin_l"] as RigidBody3D).angular_velocity).x, ((ch.body.parts["thigh_l"] as RigidBody3D).angular_velocity).x])
			if OS.get_environment("TRACK_FREE") != "":
				for fp2 in OS.get_environment("TRACK_FREE").split(","):
					ch.body.part_strength[fp2] = 0.0
			await get_tree().physics_frame
			if OS.get_environment("TRACK_FOOT") != "" and f >= 4 and f < 24:
				var fp: String = OS.get_environment("TRACK_FOOT")
				var tf: Transform3D = ch.body.targets[fp] * Transform3D(Basis(), ch.body.com[fp])
				var pf: Vector3 = (ch.body.parts[fp] as Node3D).global_position
				var vel: Vector3 = (ch.body.parts[fp] as RigidBody3D).linear_velocity
				print("   %s f%d tgt %s phys %s vel %s root %s" % [fp, f, _v(tf.origin), _v(pf), _v(vel), _v(ch.global_position)])
				var rels := []
				for pair in [["pelvis", "thigh_l"], ["thigh_l", "shin_l"], ["shin_l", "foot_l"]]:
					var bt: Basis = (ch.body.targets[pair[0]] as Transform3D).basis.orthonormalized().inverse() * (ch.body.targets[pair[1]] as Transform3D).basis.orthonormalized()
					var bp: Basis = (ch.body.parts[pair[0]] as Node3D).global_basis.orthonormalized().inverse() * (ch.body.parts[pair[1]] as Node3D).global_basis.orthonormalized()
					rels.append("%s>%s tgt %.0f° phys %.0f°" % [pair[0], pair[1], rad_to_deg(bt.get_rotation_quaternion().get_angle()), rad_to_deg(bp.get_rotation_quaternion().get_angle())])
				print("        ", " | ".join(rels))
				var av := []
				for pn4 in ["thigh_l", "shin_l", "foot_l"]:
					var rb4 := ch.body.parts[pn4] as RigidBody3D
					var qc := rb4.global_basis.orthonormalized().get_rotation_quaternion()
					var qt := (ch.body.targets[pn4] as Transform3D).basis.orthonormalized().get_rotation_quaternion()
					var dq := qt * qc.inverse()
					if dq.w < 0.0:
						dq = -dq
					av.append("%s w=%s err %.0f° k=%.2f" % [pn4, _v(rb4.angular_velocity), rad_to_deg(2.0 * acos(clampf(dq.w, -1.0, 1.0))), clampf(ch.body.strength * ch.body.part_strength[pn4] * Rig.STIFFNESS[pn4], 0.0, 1.0)])
				print("        ", " | ".join(av))
				var dirs := []
				for pn3 in ["thigh_l", "shin_l", "foot_l"]:
					var b: Basis = (ch.body.targets[pn3] as Transform3D).basis
					var bpz: Basis = (ch.body.parts[pn3] as Node3D).global_basis
					dirs.append("%s tgt down-axis %s phys %s" % [pn3, _v(b * Vector3(0, -1, 0)), _v(bpz * Vector3(0, -1, 0))])
				print("        ", " | ".join(dirs))
			for g in GROUPS:
				var e := 0.0
				for pn in GROUPS[g]:
					if not ch.body.targets.has(pn) or ch.body.severed.has(pn):
						continue
					var tgt: Transform3D = ch.body.targets[pn] * Transform3D(Basis(), ch.body.com[pn])
					e = maxf(e, (tgt.origin - (ch.body.parts[pn] as Node3D).global_position).length())
				mx[g] = maxf(mx[g], e)
				sm[g] += e
				if verbose != "" and e > 0.06 and g.begins_with(verbose):
					var worst := ""
					var we := 0.0
					for pn2 in GROUPS[g]:
						var t2: Transform3D = ch.body.targets[pn2] * Transform3D(Basis(), ch.body.com[pn2])
						var e2 := (t2.origin - (ch.body.parts[pn2] as Node3D).global_position).length()
						if e2 > we:
							we = e2
							worst = pn2
					print("   %s f%d %s err %.1f cm (%s) action=%s at=%.3f spd=%.2f" % [name, f, g, e * 100.0, worst, ch.action, ch.action_time, ch.velocity.length()])
		var cols := []
		for g in GROUPS:
			cols.append("%5.1f/%-5.1f" % [mx[g] * 100.0, sm[g] / float(frames) * 100.0])
		print("%-12s %s" % [name, "   ".join(cols)])
	get_tree().quit()
