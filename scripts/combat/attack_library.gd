class_name AttackLibrary
extends RefCounted
## Weapon moves described as sword-grip keyframes in character space
## (x right, y up, -z forward). Each key: time, grip position, blade
## direction, edge direction, body twist/lean/crouch and the easing used to
## reach it. The animator interpolates them with Catmull-Rom splines and the
## arms follow with IK, so every move stays fluid and adapts to the body.

## Weapon-specific data: resting guard pose, reach and hand placement.
const WEAPONS := {
	"katana": {"left_hand": -0.11, "reach": 1.0, "ideal": 1.05, "blade_start": 0.05, "blade_end": 0.75, "guard": "guard_katana", "two_handed": true, "mass": 1.2},
	"nodachi": {"left_hand": -0.26, "reach": 1.4, "ideal": 1.35, "blade_start": 0.05, "blade_end": 1.12, "guard": "guard_katana", "two_handed": true, "mass": 2.4},
	"kanabo": {"left_hand": -0.12, "reach": 1.2, "ideal": 1.2, "blade_start": 0.2, "blade_end": 0.95, "guard": "guard_kanabo", "two_handed": true, "mass": 4.0},
	"yari": {"left_hand": 0.2, "reach": 2.2, "ideal": 1.9, "blade_start": 1.25, "blade_end": 1.64, "guard": "guard_yari", "two_handed": true, "mass": 2.0},
}

## Hip of the chibi body (torso is 1.32x wider than the human reference the
## keyframes were authored for; the animator adds the vertical shift to all keys).
const SHEATH_GRIP := Vector3(-0.12, 1.08, -0.26)
const SHEATH_DIR := Vector3(-0.25, -0.3, 0.92)

static var _cache := {}

## Weapons are drawn bigger than life: the chibi bodies look silly and the
## blades read better at HFF proportions.
const WEAPON_SCALE := 1.2


## Where the sheathed hilt sits in root space for a body of scale s.
static func sheath_grip() -> Vector3:
	return SHEATH_GRIP + Vector3(0.0, Rig.upper_shift(), 0.0)


static func key(t: float, pos: Vector3, dir: Vector3, edge: Vector3, twist := 0.0, lean := 0.0, crouch := 0.0, ease := "inout") -> Dictionary:
	var d := dir.normalized()
	var e := (edge - d * edge.dot(d)).normalized()
	return {"t": t, "pos": pos, "dir": d, "edge": e, "twist": twist, "lean": lean, "crouch": crouch, "ease": ease}


static func guard(weapon: String) -> Dictionary:
	match weapon:
		"kanabo":
			return key(0.0, Vector3(0.04, 1.37, -0.18), Vector3(0.1, 0.92, 0.3), Vector3(0, 0, -1))
		"yari":
			return key(0.0, Vector3(0.05, 1.17, -0.02), Vector3(-0.05, 0.25, -0.96), Vector3(0, 1, 0))
		_:
			return key(0.0, Vector3(0.02, 1.2727, -0.24), Vector3(0.0, 0.5, -0.86), Vector3(0.0, -0.86, -0.5))


static func block_pose(weapon: String) -> Dictionary:
	match weapon:
		"yari":
			return key(0.0, Vector3(0.25, 1.3, -0.25), Vector3(-0.95, 0.25, -0.1), Vector3(0, 0.3, -1))
		_:
			return key(0.0, Vector3(0.05, 1.4327, -0.22), Vector3(-0.6, 0.75, -0.28), Vector3(0.0, 0.3, -0.95))


## Sheathed position of the grip (hand on the hilt at the left hip).
static func hilt_pose() -> Dictionary:
	# same place and orientation as the sheathed sword (blade pointing back, edge up)
	return key(0.0, SHEATH_GRIP, SHEATH_DIR, Vector3(0.0, 1.0, 0.0))


static func get_attack(name: String) -> Dictionary:
	if _cache.is_empty():
		_build()
	return _cache.get(name, {})


static func _build() -> void:
	var g := guard("katana")
	# ------------------------------------------------------------ katana
	# Katana combo, choreographed like the sword games it borrows from: every move
	# coils (anticipation), whips through the cut with the hips leading, overshoots,
	# holds a beat and settles back into the guard. Times are seconds; the key
	# "ease" describes how the motion arrives at that key.
	_cache["light_1"] = {   # yoko-giri: quick horizontal slash, right to left
		"name": "light_1", "clip": "katana_light_1", "duration": 0.62, "active": [0.17, 0.31], "damage": 18.0, "guard_damage": 12.0,
		"step": 0.55, "step_window": [0.06, 0.24], "cancel": 0.38, "swing_time": 0.15, "hitstop": 0.06,
		"cut": "horizontal", "next": "light_2", "power": 1.0,
		"keys": [g,
			key(0.09, Vector3(0.44, 1.1, 0.04), Vector3(0.75, 0.12, 0.65), Vector3(0.2, -0.1, -0.97), 46.0, -4.0, 0.06, "out"),
			key(0.15, Vector3(0.34, 1.22, -0.22), Vector3(0.68, 0.1, -0.72), Vector3(0.2, -0.1, -0.97), 30.0, 0.0, 0.07, "in"),
			key(0.21, Vector3(0.02, 1.25, -0.6), Vector3(-0.1, 0.02, -1.0), Vector3(-1.0, 0.0, 0.12), 0.0, 7.0, 0.08, "linear"),
			key(0.27, Vector3(-0.42, 1.16, -0.36), Vector3(-0.92, -0.06, -0.4), Vector3(0.25, 0.0, 1.0), -40.0, 9.0, 0.08, "out"),
			key(0.34, Vector3(-0.52, 1.12, -0.12), Vector3(-0.96, -0.08, 0.15), Vector3(0.25, 0.0, 1.0), -50.0, 9.0, 0.08, "out"),
			key(0.44, Vector3(-0.5, 1.1, -0.12), Vector3(-0.95, -0.08, 0.2), Vector3(0.25, 0.0, 1.0), -48.0, 8.0, 0.07, "inout"),
			key(0.62, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["light_2"] = {   # kesa-giri: rises high on the left, diagonal cut down to the right
		"name": "light_2", "clip": "katana_light_2", "duration": 0.68, "active": [0.18, 0.34], "damage": 20.0, "guard_damage": 14.0,
		"step": 0.6, "step_window": [0.08, 0.27], "cancel": 0.4, "swing_time": 0.16, "hitstop": 0.065,
		"cut": "diagonal_down", "next": "light_3", "power": 1.05,
		"keys": [g,
			key(0.1, Vector3(-0.3, 1.62, 0.02), Vector3(-0.3, 0.85, 0.4), Vector3(0.3, 0.1, -0.95), -34.0, -6.0, 0.0, "out"),
			key(0.16, Vector3(-0.1, 1.5, -0.25), Vector3(-0.1, 0.5, -0.85), Vector3(0.3, 0.1, -0.95), -20.0, -2.0, 0.03, "in"),
			key(0.23, Vector3(0.06, 1.22, -0.55), Vector3(0.3, -0.1, -0.95), Vector3(0.4, -0.9, 0.0), 6.0, 8.0, 0.08, "linear"),
			key(0.3, Vector3(0.34, 0.9, -0.3), Vector3(0.55, -0.72, -0.4), Vector3(0.1, -0.5, 0.85), 34.0, 13.0, 0.13, "out"),
			key(0.38, Vector3(0.44, 0.78, -0.15), Vector3(0.6, -0.75, 0.1), Vector3(0.1, -0.5, 0.85), 40.0, 15.0, 0.15, "out"),
			key(0.5, Vector3(0.42, 0.8, -0.16), Vector3(0.6, -0.72, 0.12), Vector3(0.1, -0.5, 0.85), 38.0, 14.0, 0.14, "inout"),
			key(0.68, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["light_3"] = {   # kaiten-zan: a low coil then a spinning slash all the way round (Onimusha flourish)
		"name": "light_3", "clip": "katana_light_3", "duration": 0.86, "active": [0.2, 0.46], "damage": 26.0, "guard_damage": 24.0,
		"step": 0.75, "step_window": [0.1, 0.34], "cancel": 0.6, "swing_time": 0.2, "hitstop": 0.085,
		"cut": "horizontal", "next": "light_1", "power": 1.35, "spin": [0.16, 0.46, 330.0], "wide": true,
		"keys": [g,
			key(0.12, Vector3(-0.36, 0.95, 0.15), Vector3(-0.8, -0.3, 0.5), Vector3(0.3, 0.0, -0.95), -50.0, -2.0, 0.17, "out"),
			key(0.2, Vector3(0.46, 1.16, -0.12), Vector3(0.95, 0.05, -0.3), Vector3(0.0, -1.0, 0.0), 30.0, 4.0, 0.12, "in"),
			key(0.33, Vector3(0.5, 1.17, -0.22), Vector3(0.92, 0.04, -0.4), Vector3(0.0, -1.0, 0.0), 10.0, 5.0, 0.1, "linear"),
			key(0.46, Vector3(0.42, 1.16, -0.3), Vector3(0.85, 0.05, -0.52), Vector3(0.0, -1.0, 0.0), 0.0, 4.0, 0.09, "out"),
			key(0.58, Vector3(0.12, 1.16, -0.52), Vector3(0.12, 0.12, -0.99), Vector3(-1.0, 0.0, 0.1), 0.0, 3.0, 0.08, "out"),
			key(0.86, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["heavy_charge"] = {
		"name": "heavy_charge", "clip": "katana_heavy_charge", "duration": 0.3, "hold": true,
		"keys": [g, key(0.3, Vector3(0.14, 1.62, 0.1), Vector3(0.28, 0.4, 0.87), Vector3(0.0, 0.9, -0.42), 18.0, -6.0, 0.08, "out")],
	}
	var charged := key(0.0, Vector3(0.14, 1.66, 0.12), Vector3(0.28, 0.4, 0.87), Vector3(0.0, 0.9, -0.42), 18.0, -8.0, 0.1)
	_cache["heavy"] = {   # ichimonji: the sword crashes down from above the head, sticking in the ground
		"name": "heavy", "clip": "katana_heavy", "duration": 0.78, "active": [0.07, 0.24], "damage": 38.0, "guard_damage": 70.0,
		"step": 1.4, "step_window": [0.0, 0.2], "cancel": 0.58, "swing_time": 0.05, "hitstop": 0.13,
		"cut": "diagonal_down", "unblockable": false, "breaks_guard": true, "power": 1.9, "slam": true,
		"keys": [charged,
			key(0.05, Vector3(0.02, 1.52, 0.02), Vector3(0.1, 0.9, 0.42), Vector3(0.0, 0.94, -0.35), 4.0, -10.0, 0.0, "linear"),
			key(0.12, Vector3(0.0, 1.22, -0.62), Vector3(-0.2, 0.05, -0.97), Vector3(-0.6, -0.8, 0.0), -5.0, 10.0, 0.1, "in"),
			key(0.22, Vector3(-0.2, 0.7, -0.44), Vector3(-0.3, -0.9, -0.35), Vector3(0.0, -0.6, 0.8), -22.0, 24.0, 0.2, "out"),
			key(0.3, Vector3(-0.2, 0.58, -0.4), Vector3(-0.3, -0.94, -0.2), Vector3(0.0, -0.6, 0.8), -22.0, 26.0, 0.22, "out"),
			key(0.5, Vector3(-0.2, 0.62, -0.4), Vector3(-0.3, -0.92, -0.22), Vector3(0.0, -0.6, 0.8), -18.0, 20.0, 0.18, "inout"),
			key(0.78, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["counter"] = {   # answer after a deflect: a fast rising diagonal
		"name": "counter", "clip": "katana_counter", "duration": 0.5, "active": [0.08, 0.23], "damage": 34.0, "guard_damage": 40.0,
		"step": 0.85, "step_window": [0.0, 0.16], "cancel": 0.34, "swing_time": 0.06, "hitstop": 0.1,
		"cut": "diagonal_up", "power": 1.65,
		"keys": [g,
			key(0.05, Vector3(0.26, 0.86, -0.1), Vector3(0.6, -0.6, -0.5), Vector3(0.2, -0.1, -0.97), 26.0, 4.0, 0.12, "out"),
			key(0.14, Vector3(0.05, 1.2, -0.56), Vector3(0.1, 0.35, -0.93), Vector3(-1.0, 0.0, 0.12), 0.0, 8.0, 0.08, "in"),
			key(0.24, Vector3(-0.36, 1.5, -0.24), Vector3(-0.6, 0.7, -0.4), Vector3(0.25, 0.0, 1.0), -36.0, 5.0, 0.05, "out"),
			key(0.34, Vector3(-0.4, 1.52, -0.18), Vector3(-0.65, 0.68, -0.3), Vector3(0.25, 0.0, 1.0), -40.0, 4.0, 0.04, "out"),
			key(0.5, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	var hilt := hilt_pose()
	_cache["iai"] = {
		"name": "iai", "clip": "katana_iai", "duration": 0.62, "active": [0.05, 0.2], "damage": 999.0, "guard_damage": 999.0,
		"step": 3.2, "step_window": [0.0, 0.16], "cancel": 0.6, "swing_time": 0.03, "hitstop": 0.14,
		"cut": "horizontal", "unblockable": true, "power": 3.0,
		"keys": [hilt,
			key(0.05, Vector3(-0.1, 1.08, -0.4), Vector3(-0.87, 0.0, 0.5), Vector3(-0.5, 0.0, -0.87), -25.0, 8.0, 0.1, "in"),
			key(0.1, Vector3(0.02, 1.15, -0.55), Vector3(-0.5, 0.02, -0.87), Vector3(0.87, 0.0, -0.5), -10.0, 12.0, 0.12, "linear"),
			key(0.16, Vector3(0.25, 1.18, -0.45), Vector3(0.707, 0.04, -0.707), Vector3(0.707, 0.0, 0.707), 18.0, 14.0, 0.14, "linear"),
			key(0.24, Vector3(0.45, 1.2, -0.25), Vector3(0.94, 0.08, 0.34), Vector3(-0.34, 0.0, 0.94), 36.0, 14.0, 0.14, "out"),
			key(0.62, Vector3(0.5, 1.18, -0.12), Vector3(0.9, 0.22, 0.36), Vector3(-0.36, 0.1, 0.93), 30.0, 10.0, 0.12, "inout")],
	}
	_cache["assassinate"] = {
		"name": "assassinate", "clip": "katana_assassinate", "duration": 1.25, "active": [0.3, 0.45], "damage": 999.0, "guard_damage": 999.0,
		"step": 0.35, "step_window": [0.1, 0.3], "cancel": 1.2, "swing_time": 0.25, "hitstop": 0.12,
		"cut": "thrust", "unblockable": true, "power": 2.0,
		"keys": [g,
			key(0.22, Vector3(0.1, 1.28, 0.12), Vector3(0.0, 0.05, -1.0), Vector3(0.0, -1.0, 0.0), 10.0, -4.0, 0.04, "out"),
			key(0.36, Vector3(0.04, 1.24, -0.66), Vector3(0.0, -0.05, -1.0), Vector3(0.0, -1.0, 0.0), 0.0, 10.0, 0.08, "in"),
			key(0.9, Vector3(0.04, 1.2, -0.64), Vector3(0.0, -0.1, -1.0), Vector3(0.0, -1.0, 0.0), 0.0, 12.0, 0.1, "linear"),
			key(1.25, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["parry"] = {
		"name": "parry", "duration": 0.34, "cancel": 0.2,
		"keys": [block_pose("katana"),
			key(0.1, Vector3(-0.06, 1.52, -0.42), Vector3(-0.5, 0.84, -0.2), Vector3(-0.3, 0.0, -0.95), -18.0, -4.0, 0.03, "out"),
			key(0.34, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["chiburi"] = {
		"name": "chiburi", "duration": 1.1,
		"keys": [g,
			key(0.22, Vector3(0.28, 1.46, -0.2), Vector3(0.3, 0.7, -0.64), Vector3(0.5, -0.6, 0.6), 12.0, 0.0, 0.0, "out"),
			key(0.34, Vector3(0.42, 1.0, -0.3), Vector3(0.5, -0.6, -0.62), Vector3(0.6, 0.5, -0.6), 16.0, 4.0, 0.04, "in"),
			key(0.55, Vector3(0.1, 1.08, -0.42), Vector3(-0.2, 0.0, -0.98), Vector3(0.0, 1.0, 0.0), 0.0, 0.0, 0.0, "inout"),
			key(0.74, Vector3(-0.08, 1.05, -0.38), Vector3(-0.95, -0.05, 0.1), Vector3(0.0, 1.0, 0.0), -8.0, 0.0, 0.0, "inout"),
			key(0.92, hilt.pos, hilt.dir, hilt.edge, -6.0, 0.0, 0.0, "inout"),
			key(1.1, hilt.pos, hilt.dir, hilt.edge, 0.0, 0.0, 0.0, "linear")],
	}
	_cache["draw"] = {
		"name": "draw", "duration": 0.46,
		"keys": [hilt,
			key(0.08, Vector3(-0.08, 1.08, -0.38), Vector3(-0.87, 0.1, 0.5), Vector3(-0.5, 0.0, -0.87), -10.0, 0.0, 0.0, "in"),
			key(0.18, Vector3(0.06, 1.15, -0.48), Vector3(-0.3, 0.35, -0.88), Vector3(0.6, -0.6, -0.3), 4.0, 0.0, 0.0, "linear"),
			key(0.46, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "out")],
	}
	# ------------------------------------------------------ enemy variants
	var e_heavy: Dictionary = _cache["heavy"].duplicate(true)
	e_heavy.name = "enemy_heavy"
	e_heavy.windup = 0.55
	_cache["enemy_heavy"] = e_heavy
	# ------------------------------------------------------------ kanabo
	var kg := guard("kanabo")
	_cache["smash"] = {
		"name": "smash", "clip": "kanabo_smash", "duration": 1.35, "active": [0.66, 0.84], "damage": 32.0, "guard_damage": 60.0,
		"step": 0.8, "step_window": [0.55, 0.8], "cancel": 1.2, "swing_time": 0.62, "hitstop": 0.12,
		"cut": "crush", "breaks_guard": true, "unblockable": true, "power": 2.2,
		"keys": [kg,
			key(0.5, Vector3(0.05, 1.85, 0.2), Vector3(0.0, 0.3, 0.95), Vector3(0, 1, 0), 10.0, -12.0, 0.0, "out"),
			key(0.62, Vector3(0.05, 1.9, 0.26), Vector3(0.0, 0.2, 0.98), Vector3(0, 1, 0), 10.0, -14.0, 0.0, "linear"),
			key(0.8, Vector3(0.0, 1.05, -0.55), Vector3(0.0, -0.4, -0.92), Vector3(0, -1, 0), 0.0, 22.0, 0.18, "in"),
			key(1.0, Vector3(0.0, 0.7, -0.55), Vector3(0.0, -0.8, -0.6), Vector3(0, -1, 0), 0.0, 26.0, 0.22, "out"),
			key(1.35, kg.pos, kg.dir, kg.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["sweep"] = {
		"name": "sweep", "clip": "kanabo_sweep", "duration": 1.1, "active": [0.48, 0.66], "damage": 24.0, "guard_damage": 40.0,
		"step": 0.5, "step_window": [0.4, 0.6], "cancel": 0.95, "swing_time": 0.45, "hitstop": 0.1,
		"cut": "crush", "power": 1.8,
		"keys": [kg,
			key(0.4, Vector3(0.45, 1.3, 0.1), Vector3(0.85, 0.2, 0.45), Vector3(0, 0, -1), 45.0, -4.0, 0.05, "out"),
			key(0.58, Vector3(0.0, 1.2, -0.6), Vector3(-0.2, 0.0, -0.98), Vector3(-1, 0, 0), 0.0, 6.0, 0.08, "in"),
			key(0.72, Vector3(-0.45, 1.1, -0.1), Vector3(-0.9, -0.1, 0.4), Vector3(0, 0, 1), -50.0, 8.0, 0.08, "out"),
			key(1.1, kg.pos, kg.dir, kg.edge, 0.0, 0.0, 0.0, "inout")],
	}
	# -------------------------------------------------------------- yari
	var yg := guard("yari")
	_cache["thrust"] = {
		"name": "thrust", "clip": "yari_thrust", "duration": 0.8, "active": [0.34, 0.5], "damage": 20.0, "guard_damage": 18.0,
		"step": 0.7, "step_window": [0.3, 0.48], "cancel": 0.62, "swing_time": 0.3, "hitstop": 0.07,
		"cut": "thrust", "power": 1.2,
		"keys": [yg,
			key(0.28, Vector3(0.2, 1.08, 0.32), Vector3(-0.05, 0.25, -0.97), Vector3(0, 1, 0), 18.0, -6.0, 0.04, "out"),
			key(0.42, Vector3(0.08, 1.16, -0.42), Vector3(-0.02, 0.12, -0.99), Vector3(0, 1, 0), -6.0, 10.0, 0.08, "in"),
			key(0.8, yg.pos, yg.dir, yg.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["spear_sweep"] = {
		"name": "spear_sweep", "clip": "yari_sweep", "duration": 1.0, "active": [0.42, 0.6], "damage": 18.0, "guard_damage": 20.0, "ideal": 1.45,
		"step": 0.3, "step_window": [0.4, 0.55], "cancel": 0.85, "swing_time": 0.4, "hitstop": 0.07,
		"cut": "crush", "power": 1.3,
		"keys": [yg,
			key(0.36, Vector3(0.4, 1.3, 0.05), Vector3(0.8, 0.3, -0.5), Vector3(0, 1, 0), 40.0, 0.0, 0.03, "out"),
			key(0.52, Vector3(0.0, 1.25, -0.3), Vector3(-0.5, 0.15, -0.85), Vector3(0, 1, 0), -10.0, 6.0, 0.06, "in"),
			key(0.66, Vector3(-0.35, 1.2, -0.1), Vector3(-0.95, 0.1, -0.1), Vector3(0, 1, 0), -45.0, 6.0, 0.06, "out"),
			key(1.0, yg.pos, yg.dir, yg.edge, 0.0, 0.0, 0.0, "inout")],
	}


## Attack list per weapon for AI and combos.
static func moves_for(weapon: String) -> Array[String]:
	match weapon:
		"kanabo":
			return ["smash", "sweep"]
		"yari":
			return ["thrust", "thrust", "spear_sweep"]
		_:
			return ["light_1", "light_2", "light_3", "enemy_heavy"]


static func ease_curve(u: float, mode: String) -> float:
	u = clampf(u, 0.0, 1.0)
	match mode:
		"in":
			return u * u * u
		"out":
			return 1.0 - pow(1.0 - u, 3.0)
		"linear":
			return u
		_:
			return u * u * (3.0 - 2.0 * u)


static func _cr(p0: Variant, p1: Variant, p2: Variant, p3: Variant, t: float) -> Variant:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## Samples a key list at time t. Returns a key-like dictionary.
static func sample(keys: Array, t: float) -> Dictionary:
	var n := keys.size()
	if n == 0:
		return {}
	if t <= keys[0].t:
		return keys[0]
	if t >= keys[n - 1].t:
		return keys[n - 1]
	var i := 0
	while i < n - 1 and keys[i + 1].t < t:
		i += 1
	var k1: Dictionary = keys[i]
	var k2: Dictionary = keys[i + 1]
	var k0: Dictionary = keys[max(i - 1, 0)]
	var k3: Dictionary = keys[min(i + 2, n - 1)]
	var u := ease_curve((t - k1.t) / maxf(k2.t - k1.t, 0.0001), k2.ease)
	var pos: Vector3 = _cr(k0.pos, k1.pos, k2.pos, k3.pos, u)
	var dir: Vector3 = (_cr(k0.dir, k1.dir, k2.dir, k3.dir, u) as Vector3).normalized()
	if dir.length_squared() < 0.5:
		dir = k1.dir if u < 0.5 else k2.dir
	var edge: Vector3 = _cr(k0.edge, k1.edge, k2.edge, k3.edge, u)
	edge = (edge - dir * edge.dot(dir)).normalized()
	return {
		"pos": pos, "dir": dir, "edge": edge,
		"twist": lerpf(k1.twist, k2.twist, u), "lean": lerpf(k1.lean, k2.lean, u),
		"crouch": lerpf(k1.crouch, k2.crouch, u),
	}


## Builds the weapon (grip) basis from blade and edge directions.
static func grip_basis(dir: Vector3, edge: Vector3) -> Basis:
	var y := dir.normalized()
	var z := -(edge - y * edge.dot(y)).normalized()
	var x := y.cross(z).normalized()
	z = x.cross(y).normalized()
	return Basis(x, y, z)
