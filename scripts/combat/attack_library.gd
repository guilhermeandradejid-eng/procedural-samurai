class_name AttackLibrary
extends RefCounted
## Weapon moves described as sword-grip keyframes in character space
## (x right, y up, -z forward). Each key: time, grip position, blade
## direction, edge direction, body twist/lean/crouch and the easing used to
## reach it. The animator interpolates them with Catmull-Rom splines and the
## arms follow with IK, so every move stays fluid and adapts to the body.

## Weapon-specific data: resting guard pose, reach and hand placement.
const WEAPONS := {
	"katana": {"left_hand": -0.16, "reach": 1.0, "blade_start": 0.05, "blade_end": 0.75, "guard": "guard_katana", "two_handed": true, "mass": 1.2},
	"nodachi": {"left_hand": -0.26, "reach": 1.4, "blade_start": 0.05, "blade_end": 1.12, "guard": "guard_katana", "two_handed": true, "mass": 2.4},
	"kanabo": {"left_hand": -0.2, "reach": 1.2, "blade_start": 0.2, "blade_end": 0.95, "guard": "guard_kanabo", "two_handed": true, "mass": 4.0},
	"yari": {"left_hand": 0.5, "reach": 2.2, "blade_start": 0.7, "blade_end": 1.02, "guard": "guard_yari", "two_handed": true, "mass": 2.0},
}

const SHEATH_GRIP := Vector3(-0.19, 0.99, -0.16)
const SHEATH_DIR := Vector3(0.12, -0.32, 0.94)

static var _cache := {}


static func key(t: float, pos: Vector3, dir: Vector3, edge: Vector3, twist := 0.0, lean := 0.0, crouch := 0.0, ease := "inout") -> Dictionary:
	var d := dir.normalized()
	var e := (edge - d * edge.dot(d)).normalized()
	return {"t": t, "pos": pos, "dir": d, "edge": e, "twist": twist, "lean": lean, "crouch": crouch, "ease": ease}


static func guard(weapon: String) -> Dictionary:
	match weapon:
		"kanabo":
			return key(0.0, Vector3(0.2, 1.1, -0.18), Vector3(0.1, 0.9, 0.25), Vector3(0, 0, -1))
		"yari":
			return key(0.0, Vector3(0.14, 1.02, 0.12), Vector3(-0.05, 0.28, -0.96), Vector3(0, 1, 0))
		_:
			return key(0.0, Vector3(0.08, 1.08, -0.3), Vector3(0.0, 0.55, -0.83), Vector3(0.0, -0.83, -0.55))


static func block_pose(weapon: String) -> Dictionary:
	match weapon:
		"yari":
			return key(0.0, Vector3(0.25, 1.3, -0.25), Vector3(-0.95, 0.25, -0.1), Vector3(0, 0.3, -1))
		_:
			return key(0.0, Vector3(0.16, 1.42, -0.32), Vector3(-0.92, 0.3, -0.22), Vector3(0.0, 0.25, -0.97))


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
	_cache["light_1"] = {
		"name": "light_1", "duration": 0.56, "active": [0.15, 0.3], "damage": 18.0, "guard_damage": 12.0,
		"step": 0.5, "step_window": [0.08, 0.26], "cancel": 0.36, "swing_time": 0.14, "hitstop": 0.055,
		"cut": "horizontal", "next": "light_2", "power": 1.0,
		"keys": [g,
			key(0.12, Vector3(0.36, 1.3, -0.1), Vector3(0.82, 0.24, 0.52), Vector3(0.2, -0.1, -0.97), 34.0, 0.0, 0.03, "out"),
			key(0.23, Vector3(0.02, 1.22, -0.54), Vector3(-0.15, 0.05, -1.0), Vector3(-1.0, 0.0, 0.12), 0.0, 4.0, 0.04, "in"),
			key(0.32, Vector3(-0.36, 1.12, -0.2), Vector3(-0.9, -0.12, 0.42), Vector3(0.25, 0.0, 1.0), -36.0, 6.0, 0.04, "out"),
			key(0.56, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["light_2"] = {
		"name": "light_2", "duration": 0.6, "active": [0.16, 0.32], "damage": 20.0, "guard_damage": 14.0,
		"step": 0.55, "step_window": [0.1, 0.28], "cancel": 0.38, "swing_time": 0.15, "hitstop": 0.06,
		"cut": "diagonal_down", "next": "light_3", "power": 1.05,
		"keys": [g,
			key(0.13, Vector3(-0.28, 1.54, -0.06), Vector3(-0.35, 0.8, 0.45), Vector3(0.3, 0.1, -0.95), -30.0, -4.0, 0.0, "out"),
			key(0.25, Vector3(0.02, 1.24, -0.52), Vector3(0.35, -0.05, -0.94), Vector3(0.4, -0.9, 0.0), 2.0, 6.0, 0.05, "in"),
			key(0.35, Vector3(0.32, 0.92, -0.22), Vector3(0.55, -0.7, 0.45), Vector3(0.1, -0.5, 0.85), 32.0, 10.0, 0.08, "out"),
			key(0.6, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["light_3"] = {
		"name": "light_3", "duration": 0.76, "active": [0.24, 0.4], "damage": 28.0, "guard_damage": 22.0,
		"step": 0.95, "step_window": [0.16, 0.36], "cancel": 0.55, "swing_time": 0.25, "hitstop": 0.085,
		"cut": "vertical", "next": "light_1", "power": 1.3,
		"keys": [g,
			key(0.19, Vector3(0.03, 1.7, 0.03), Vector3(0.0, 0.35, 0.94), Vector3(0.0, 0.94, -0.35), 6.0, -9.0, 0.0, "out"),
			key(0.31, Vector3(0.0, 1.3, -0.58), Vector3(0.0, 0.1, -1.0), Vector3(0.0, -1.0, 0.0), 0.0, 8.0, 0.06, "in"),
			key(0.42, Vector3(0.0, 0.86, -0.5), Vector3(0.0, -0.75, -0.65), Vector3(0.0, -0.65, 0.75), 0.0, 20.0, 0.16, "out"),
			key(0.76, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["heavy_charge"] = {
		"name": "heavy_charge", "duration": 0.3, "hold": true,
		"keys": [g, key(0.3, Vector3(0.14, 1.62, 0.1), Vector3(0.28, 0.4, 0.87), Vector3(0.0, 0.9, -0.42), 18.0, -6.0, 0.08, "out")],
	}
	var charged := key(0.0, Vector3(0.14, 1.62, 0.1), Vector3(0.28, 0.4, 0.87), Vector3(0.0, 0.9, -0.42), 18.0, -6.0, 0.08)
	_cache["heavy"] = {
		"name": "heavy", "duration": 0.66, "active": [0.05, 0.22], "damage": 38.0, "guard_damage": 70.0,
		"step": 1.3, "step_window": [0.0, 0.18], "cancel": 0.5, "swing_time": 0.04, "hitstop": 0.11,
		"cut": "diagonal_down", "unblockable": false, "breaks_guard": true, "power": 1.8,
		"keys": [charged,
			key(0.1, Vector3(0.0, 1.22, -0.62), Vector3(-0.35, 0.05, -0.93), Vector3(-0.6, -0.8, 0.0), -5.0, 10.0, 0.1, "in"),
			key(0.22, Vector3(-0.36, 0.84, -0.26), Vector3(-0.6, -0.6, 0.5), Vector3(0.0, -0.6, 0.8), -42.0, 18.0, 0.16, "out"),
			key(0.66, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["counter"] = {
		"name": "counter", "duration": 0.46, "active": [0.08, 0.22], "damage": 34.0, "guard_damage": 40.0,
		"step": 0.8, "step_window": [0.0, 0.16], "cancel": 0.34, "swing_time": 0.06, "hitstop": 0.09,
		"cut": "horizontal", "power": 1.6,
		"keys": [g,
			key(0.06, Vector3(0.36, 1.32, -0.12), Vector3(0.82, 0.24, 0.52), Vector3(0.2, -0.1, -0.97), 30.0, 0.0, 0.04, "out"),
			key(0.14, Vector3(0.02, 1.22, -0.56), Vector3(-0.15, 0.05, -1.0), Vector3(-1.0, 0.0, 0.12), 0.0, 6.0, 0.06, "in"),
			key(0.24, Vector3(-0.38, 1.1, -0.18), Vector3(-0.9, -0.12, 0.42), Vector3(0.25, 0.0, 1.0), -40.0, 8.0, 0.06, "out"),
			key(0.46, g.pos, g.dir, g.edge, 0.0, 0.0, 0.0, "inout")],
	}
	var hilt := hilt_pose()
	_cache["iai"] = {
		"name": "iai", "duration": 0.62, "active": [0.05, 0.2], "damage": 999.0, "guard_damage": 999.0,
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
		"name": "assassinate", "duration": 1.25, "active": [0.3, 0.45], "damage": 999.0, "guard_damage": 999.0,
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
		"name": "smash", "duration": 1.35, "active": [0.66, 0.84], "damage": 32.0, "guard_damage": 60.0,
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
		"name": "sweep", "duration": 1.1, "active": [0.48, 0.66], "damage": 24.0, "guard_damage": 40.0,
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
		"name": "thrust", "duration": 0.8, "active": [0.34, 0.5], "damage": 20.0, "guard_damage": 18.0,
		"step": 0.7, "step_window": [0.3, 0.48], "cancel": 0.62, "swing_time": 0.3, "hitstop": 0.07,
		"cut": "thrust", "power": 1.2,
		"keys": [yg,
			key(0.28, Vector3(0.2, 1.08, 0.32), Vector3(-0.05, 0.25, -0.97), Vector3(0, 1, 0), 18.0, -6.0, 0.04, "out"),
			key(0.42, Vector3(0.08, 1.16, -0.42), Vector3(-0.02, 0.12, -0.99), Vector3(0, 1, 0), -6.0, 10.0, 0.08, "in"),
			key(0.8, yg.pos, yg.dir, yg.edge, 0.0, 0.0, 0.0, "inout")],
	}
	_cache["spear_sweep"] = {
		"name": "spear_sweep", "duration": 1.0, "active": [0.42, 0.6], "damage": 18.0, "guard_damage": 20.0,
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


static func ease(u: float, mode: String) -> float:
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
	var u := ease((t - k1.t) / maxf(k2.t - k1.t, 0.0001), k2.ease)
	var pos: Vector3 = _cr(k0.pos, k1.pos, k2.pos, k3.pos, u)
	var dir: Vector3 = (_cr(k0.dir, k1.dir, k2.dir, k3.dir, u) as Vector3).normalized()
	if dir.length_squared() < 0.5:
		dir = k1.dir.slerp(k2.dir, u)
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
