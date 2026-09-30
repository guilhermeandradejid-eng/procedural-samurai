extends Node3D
## Isolated physics check: how fast does the physical knee follow a knee target that
## snaps from bent to straight? (The animator is switched off; targets are set by hand.)
##   godot --headless --path . res://tests/knee_test.tscn

var ch: Character
var frame := 0
var base := {}


func _ready() -> void:
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


func _set_knee(deg: float, hip_deg: float) -> void:
	var s := ch.scale_factor
	var t_thigh: Transform3D = base["thigh_l"]
	var thigh_b := t_thigh.basis * Basis(Vector3.RIGHT, deg_to_rad(hip_deg))
	var hip_pos := t_thigh.origin
	var d1: Vector3 = (Rig.pivot["shin_l"] as Vector3) - (Rig.pivot["thigh_l"] as Vector3)
	var knee_pos: Vector3 = hip_pos + thigh_b * (d1 * s)
	var shin_b := thigh_b * Basis(Vector3.RIGHT, deg_to_rad(-deg))
	var d2: Vector3 = (Rig.pivot["foot_l"] as Vector3) - (Rig.pivot["shin_l"] as Vector3)
	var ank_pos: Vector3 = knee_pos + shin_b * (d2 * s)
	ch.body.targets["thigh_l"] = Transform3D(thigh_b, hip_pos)
	ch.body.targets["shin_l"] = Transform3D(shin_b, knee_pos)
	ch.body.targets["foot_l"] = Transform3D(shin_b, ank_pos)


func _knee_angle() -> float:
	var bp: Basis = (ch.body.parts["thigh_l"] as Node3D).global_basis.orthonormalized().inverse() * (ch.body.parts["shin_l"] as Node3D).global_basis.orthonormalized()
	return rad_to_deg(bp.get_euler().x)


func _physics_process(delta: float) -> void:
	frame += 1
	if frame == 40:
		ch.set_physics_process(false)
		for p in ["thigh_l", "shin_l", "foot_l"]:
			base[p] = ch.body.targets[p]
	if frame > 40:
		var f := frame - 40
		var knee := 80.0 if f < 40 else 0.0
		var hip := 30.0
		_set_knee(knee, hip)
		ch.body.drive(delta)
		if f >= 36 and f < 70:
			print("f%d tgt knee %.0f phys knee %.1f  shin w %.1f" % [f, -knee, _knee_angle(), (ch.body.parts["shin_l"] as RigidBody3D).angular_velocity.x])
	if frame > 120:
		get_tree().quit()
