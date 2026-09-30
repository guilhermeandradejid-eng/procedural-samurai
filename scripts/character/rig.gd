class_name Rig
extends RefCounted
## Static description of the ragdoll skeleton, shared by every character.
## Loaded from assets/models/characters/rig.json (written by the Blender
## character builder so meshes and physics always agree).

const PATH := "res://assets/models/characters/rig.json"

## Parts in parent-before-child order.
const ORDER: Array[String] = [
	"pelvis", "belly", "chest", "head",
	"upper_arm_r", "forearm_r", "hand_r", "upper_arm_l", "forearm_l", "hand_l",
	"thigh_r", "shin_r", "foot_r", "thigh_l", "shin_l", "foot_l",
]

## Per part muscle stiffness (active ragdoll tracking strength).
const STIFFNESS := {
	"pelvis": 1.0, "belly": 0.96, "chest": 0.94, "head": 0.8,
	"upper_arm_r": 0.9, "forearm_r": 0.88, "hand_r": 0.86,
	"upper_arm_l": 0.84, "forearm_l": 0.8, "hand_l": 0.78,
	"thigh_r": 0.96, "shin_r": 0.95, "foot_r": 0.92,
	"thigh_l": 0.96, "shin_l": 0.95, "foot_l": 0.92,
}

static var _loaded := false
static var parent := {}
static var pivot := {}       # rest pivot (character space)
static var end := {}         # rest end point (character space)
static var shapes := {}
static var children := {}
static var meta := {}        # numbers from the model builder (see characters.py)


static func ensure_loaded() -> void:
	if _loaded:
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for k in data.parts:
		var p: Dictionary = data.parts[k]
		parent[k] = p.parent
		pivot[k] = _v(p.pivot)
		end[k] = _v(p.end)
		children[k] = []
	for k in parent:
		if parent[k] != "":
			children[parent[k]].append(k)
	for k in data.shapes:
		var s: Dictionary = data.shapes[k].duplicate()
		for key in ["center", "a", "b", "size"]:
			if s.has(key):
				s[key] = _v(s[key])
		shapes[k] = s
	meta = data.get("meta", {})
	_loaded = true


## How far the upper body sits below where the human-scale animation
## constants expect it (the legs of the chibi body are shorter).
static func upper_shift() -> float:
	ensure_loaded()
	return float(meta.get("upper_shift", 0.0))


static func ankle_height() -> float:
	ensure_loaded()
	return float(meta.get("ankle_height", 0.095))


## Ratio of this body's hip height to the human reference (0.87 m).
static func leg_ratio() -> float:
	ensure_loaded()
	return float(meta.get("hip_height", 0.87)) / 0.87


static func height() -> float:
	ensure_loaded()
	return float(meta.get("height", 1.83))


static func _v(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func bone_length(part: String) -> float:
	return (end[part] - pivot[part]).length()


## Centre of mass offset of a part relative to its pivot (rest orientation).
static func com_offset(part: String) -> Vector3:
	var s: Dictionary = shapes[part]
	match s.type:
		"capsule":
			return (s.a + s.b) * 0.5 - pivot[part]
		_:
			return s.center - pivot[part]


## All descendants of a part (including itself).
static func subtree(part: String) -> Array[String]:
	var out: Array[String] = [part]
	var i := 0
	while i < out.size():
		for c in children[out[i]]:
			out.append(c)
		i += 1
	return out


static func side_of(part: String) -> int:
	if part.ends_with("_r"):
		return 1
	if part.ends_with("_l"):
		return -1
	return 0
