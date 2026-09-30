extends Node3D
## Measures how reliably each move connects: an attacker swings at an idle
## dummy placed at several distances and angles; prints a hit matrix.
## godot --headless --path . res://tests/hit_test.tscn
## env TRACE=player/light_1 TRACE_DIST=1.5 prints the blade path frame by frame;
## env BLOCK=1 makes the dummy keep its guard up.

const CASES := [
	["player", "katana", ["light_1", "light_2", "light_3", "heavy", "counter"]],
	["ronin", "katana", ["light_1", "light_2", "light_3", "enemy_heavy"]],
	["leader", "nodachi", ["light_1", "light_2", "light_3", "enemy_heavy"]],
	["brute", "kanabo", ["smash", "sweep"]],
	["spearman", "yari", ["thrust", "spear_sweep"]],
]
const DISTS := [1.0, 1.5, 2.0, 2.5, 3.0, 3.5]

var _queue := []
var _cur := {}
var _results := {}
var _slot := 0


var trace := ""


func _ready() -> void:
	trace = OS.get_environment("TRACE")
	var ground := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2000, 1, 2000)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	ground.add_child(cs)
	add_child(ground)
	Game.set_state(Game.State.PLAYING)
	for c in CASES:
		for mv in c[2]:
			if trace != "":
				if "%s/%s" % [c[0], mv] == trace:
					_queue.append({"style": c[0], "move": mv, "dist": float(OS.get_environment("TRACE_DIST")) if OS.get_environment("TRACE_DIST") != "" else 1.5, "side": 0.0})
				continue
			for d in DISTS:
				for side in [0.0, 0.6]:
					_queue.append({"style": c[0], "move": mv, "dist": d, "side": side})
	_next()


func _next() -> void:
	if _cur.has("a"):
		_cur.a.queue_free()
		_cur.t.queue_free()
	if _queue.is_empty():
		_report()
		return
	var q: Dictionary = _queue.pop_front()
	_slot += 1
	var base := Vector3((_slot % 30) * 12.0, 0.0, (_slot / 30) * 12.0)
	var a: Character
	if q.style == "player":
		a = Player.new()
	else:
		a = Enemy.new()
		(a as Enemy).idle_mode = "guard"
	a.style = q.style
	a.seed = 5
	a.position = base + Vector3(0, 0.05, 0)
	add_child(a)
	var t: Character = Enemy.new() if q.style == "player" else Character.new()
	t.style = "ronin"
	t.seed = 9
	t.team = Character.Team.ENEMY if q.style == "player" else Character.Team.PLAYER
	var off := Vector3(sin(q.side), 0.0, -cos(q.side)) * float(q.dist)
	t.position = base + off + Vector3(0, 0.05, 0)
	t.rotation.y = atan2(off.x, off.z)
	add_child(t)
	if t is Enemy:
		(t as Enemy).process_mode = Node.PROCESS_MODE_INHERIT
	a.weapon_drawn = true
	a.combat = true
	a.weapon.hold()
	a.face_dir = off.normalized()
	a.rotation.y = atan2(-off.x, -off.z) * (0.0 if q.side > 0.0 else 1.0)
	_cur = {"a": a, "t": t, "q": q, "frame": 0, "hit": "", "started": false}
	a.hit_landed.connect(func(_c: Character, _t2: Character, r: String, info: Dictionary) -> void:
		if _cur.get("hit", "") == "":
			_cur.hit = "%s@%s" % [r.left(1), info.get("part", "?")])


func _physics_process(_delta: float) -> void:
	if _cur.is_empty() or not _cur.has("a"):
		return
	_cur.frame += 1
	var a: Character = _cur.a
	var t: Character = _cur.t
	if t is Enemy:
		(t as Enemy).state = Enemy.State.IDLE
		(t as Enemy).detection = 0.0
	if OS.get_environment("BLOCK") != "" and _cur.frame > 5 and t.action != "block":
		# the target keeps its guard up (a parry window has long passed)
		t.set_action("block", 60.0)
		t.block_time = 1.0
		t.guard = t.max_guard
	if _cur.frame == 20:
		# let the enemy attacker see the dummy as its target
		if a is Enemy:
			Game.player = null
		var ok := a.start_attack(_cur.q.move)
		if not ok:
			_cur.hit = "noattack"
		a.aim_attack_at(t)
	if trace != "" and _cur.frame >= 20 and a.action == "attack":
		var inv := a.global_transform.affine_inverse()
		var tipl: Vector3 = inv * a.weapon.tip()
		var gripl: Vector3 = inv * a.weapon.global_position
		var tg: Transform3D = a.body.targets.get("hand_r", Transform3D())
		var tgl: Vector3 = inv * tg.origin
		var hand: Vector3 = inv * (a.body.parts["hand_r"] as Node3D).global_position
		print("d=%.2f step=%.2f " % [Vector2(a.global_position.x - t.global_position.x, a.global_position.z - t.global_position.z).length(), a.attack_step], "t=%.2f sweep=%s grip=%s tip=%s hand=%s hand_tgt=%s str=%.2f" % [a.action_time, a.weapon.sweeping, _v(gripl), _v(tipl), _v(hand), _v(tgl), a.body.strength])
		if OS.get_environment("TRACE_BLADE") != "":
			var gw: Transform3D = a.animator.grip_world(Transform3D(a.global_basis.orthonormalized(), a.global_position))
			var bd_anim: Vector3 = a.global_basis.inverse() * gw.basis.y
			var bd_real: Vector3 = a.global_basis.inverse() * a.weapon.global_basis.y
			print("   blade real %s anim %s hand_k %.2f" % [_v(bd_real), _v(bd_anim), a.body.strength * float(a.body.part_strength.get("hand_r", 1.0))])
		if OS.get_environment("TRACE_ERR") != "":
			var errs := []
			for pn in ["pelvis", "belly", "chest", "upper_arm_r", "forearm_r", "hand_r", "upper_arm_l", "forearm_l", "hand_l"]:
				var pt: Transform3D = a.body.targets[pn] * Transform3D(Basis(), a.body.com[pn])
				var pc: Vector3 = (a.body.parts[pn] as Node3D).global_position
				errs.append("%s %.3f" % [pn, (pt.origin - pc).length()])
			print("   err ", ", ".join(errs))
			var rel := []
			for pair in [["upper_arm_r", "forearm_r"], ["forearm_r", "hand_r"], ["chest", "upper_arm_r"], ["upper_arm_l", "forearm_l"], ["forearm_l", "hand_l"], ["chest", "upper_arm_l"]]:
				var bt: Basis = (a.body.targets[pair[0]] as Transform3D).basis.orthonormalized().inverse() * (a.body.targets[pair[1]] as Transform3D).basis.orthonormalized()
				var bp: Basis = (a.body.parts[pair[0]] as Node3D).global_basis.orthonormalized().inverse() * (a.body.parts[pair[1]] as Node3D).global_basis.orthonormalized()
				var qt := bt.get_rotation_quaternion()
				var qp := bp.get_rotation_quaternion()
				rel.append("%s>%s tgt %.0f° (x %.0f) phys %.0f° (x %.0f)" % [pair[0], pair[1], rad_to_deg(qt.get_angle()), rad_to_deg(bt.get_euler().x), rad_to_deg(qp.get_angle()), rad_to_deg(bp.get_euler().x)])
			print("   rel ", " | ".join(rel))
	if _cur.frame > 20 + 90 or (_cur.hit != "" and _cur.frame > 30):
		var key := "%s/%s" % [_cur.q.style, _cur.q.move]
		if not _results.has(key):
			_results[key] = []
		_results[key].append("%.1f%s:%s" % [_cur.q.dist, "" if _cur.q.side == 0.0 else "s", _cur.hit if _cur.hit != "" else "-"])
		_next()


func _v(v: Vector3) -> String:
	return "(%.2f %.2f %.2f)" % [v.x, v.y, v.z]


func _report() -> void:
	for k in _results:
		print(k.rpad(22), "  ", "  ".join(_results[k]))
	get_tree().quit()
