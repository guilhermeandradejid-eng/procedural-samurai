extends Node3D
## Compares the animated arm joint angles with what the physical ragdoll reaches.
## godot --headless --path . res://tests/arm_test.tscn -- [action]

var ch: Character
var frame := 0
var mode := "guard"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	Game.set_state(Game.State.PLAYING)
	ch = Character.new()
	ch.style = "player"
	ch.team = Character.Team.PLAYER
	ch.position = Vector3(0, 0.05, 0)
	add_child(ch)


func _physics_process(_delta: float) -> void:
	frame += 1
	if frame == 10 and mode != "unarmed":
		ch.draw_weapon(true)
	if mode == "run" and frame == 30:
		ch.move_dir = Vector3(0, 0, -1)
		ch.move_speed = 3.9
	if frame % 30 == 0 and frame >= 60:
		var out := []
		for pair in [["upper_arm_r", "forearm_r"], ["upper_arm_l", "forearm_l"], ["forearm_r", "hand_r"], ["forearm_l", "hand_l"], ["thigh_r", "shin_r"], ["thigh_l", "shin_l"], ["chest", "upper_arm_r"], ["chest", "upper_arm_l"]]:
			var bt: Basis = (ch.body.targets[pair[0]] as Transform3D).basis.orthonormalized().inverse() * (ch.body.targets[pair[1]] as Transform3D).basis.orthonormalized()
			var bp: Basis = (ch.body.parts[pair[0]] as Node3D).global_basis.orthonormalized().inverse() * (ch.body.parts[pair[1]] as Node3D).global_basis.orthonormalized()
			out.append("%s>%s tgt %.0f° (eulerx %.0f) phys %.0f° (eulerx %.0f)" % [pair[0], pair[1], rad_to_deg(bt.get_rotation_quaternion().get_angle()), rad_to_deg(bt.get_euler().x), rad_to_deg(bp.get_rotation_quaternion().get_angle()), rad_to_deg(bp.get_euler().x)])
		var herr := []
		for pn in ["forearm_r", "hand_r", "forearm_l", "hand_l"]:
			var pt: Transform3D = ch.body.targets[pn] * Transform3D(Basis(), ch.body.com[pn])
			herr.append("%s %.3f" % [pn, (pt.origin - (ch.body.parts[pn] as Node3D).global_position).length()])
		print("f%d " % frame, " | ".join(out))
		var perr := []
		for pn in ["pelvis", "thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l", "upper_arm_r", "forearm_r", "hand_r"]:
			var pt2: Transform3D = ch.body.targets[pn] * Transform3D(Basis(), ch.body.com[pn])
			perr.append("%s %.3f" % [pn, (pt2.origin - (ch.body.parts[pn] as Node3D).global_position).length()])
		print("     perr ", ", ".join(perr), " strength %.2f kin %s" % [ch.body.strength, ch.body.kinematic])
		print("     err ", ", ".join(herr))
	if frame >= 240:
		get_tree().quit()
