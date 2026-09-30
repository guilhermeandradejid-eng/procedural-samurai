class_name Face
extends RefCounted
## Living face for the chibi characters: the eyeballs turn towards whatever
## the character looks at (with small idle saccades), the eyelids blink,
## narrow when angry or focused, snap wide when startled and squeeze shut
## when hurt; dead eyes roll up. Everything works on the gear meshes
## "head__eye_*" and "head__lid_*" whose origins sit on the eyeball centres.

var eyes := {}       # side -> MeshInstance3D
var lids := {}
var _eye_scale := {}
var _lid_scale := {}
var _look := Vector2.ZERO
var _sacc := Vector2.ZERO
var _sacc_t := 1.0
var _blink_t := 2.5
var _blink := 0.0
var _lid := 2.8
var _bulge := 1.0
var _hurt := 0.0
var _tilt := 0.0
var _mood_prev := "calm"
var _rng := RandomNumberGenerator.new()

const LID_OPEN := 2.8      # ~160 deg: the lid sits folded back inside the head
const LID_FOCUS := 1.95
const LID_ANGRY := 1.72
const LID_CLOSED := 0.05


func setup(body: RagdollBody) -> void:
	_rng.randomize()
	for side in ["r", "l"]:
		var e: MeshInstance3D = body.gear.get("head__eye_" + side)
		var l: MeshInstance3D = body.gear.get("head__lid_" + side)
		if e:
			eyes[side] = e
			_eye_scale[side] = e.transform.basis.get_scale().x
		if l:
			lids[side] = l
			_lid_scale[side] = l.transform.basis.get_scale().x
	_blink_t = _rng.randf_range(1.0, 4.0)


func has_eyes() -> bool:
	return not eyes.is_empty()


## look_world: point to look at (or null); mood: calm, focus, angry, hurt,
## startled, dead.
func update(delta: float, head_xf: Transform3D, look_world: Variant, mood: String) -> void:
	if eyes.is_empty():
		return
	if mood == "hurt" and _mood_prev != "hurt":
		_hurt = 0.55
	if mood == "startled" and _mood_prev != "startled":
		_bulge = 1.45
	_mood_prev = mood
	_hurt = maxf(0.0, _hurt - delta)
	# --- where to look
	var yaw := 0.0
	var pitch := 0.0
	if look_world is Vector3 and mood != "dead":
		var center := head_xf * ((eyes.values()[0] as MeshInstance3D).transform.origin * Vector3(0.0, 1.0, 1.0))
		var d := head_xf.basis.inverse() * ((look_world as Vector3) - center)
		if d.length() > 0.05:
			d = d.normalized()
			yaw = clampf(atan2(-d.x, -d.z), -0.55, 0.55)
			pitch = clampf(asin(clampf(d.y, -1.0, 1.0)), -0.4, 0.45)
	_sacc_t -= delta
	if _sacc_t <= 0.0:
		_sacc_t = _rng.randf_range(0.6, 2.4)
		_sacc = Vector2(_rng.randf_range(-0.12, 0.12), _rng.randf_range(-0.08, 0.08))
	if mood == "dead":
		pitch = 0.55
		yaw = 0.0
		_sacc = Vector2.ZERO
	_look = _look.lerp(Vector2(yaw, pitch) + _sacc, clampf(delta * (18.0 if mood == "hurt" else 11.0), 0.0, 1.0))
	# --- eyelids
	var open := LID_OPEN
	match mood:
		"angry":
			open = LID_ANGRY
		"focus":
			open = LID_FOCUS
		"dead":
			open = 1.9
		"startled":
			open = 3.05
	if _hurt > 0.0:
		open = lerpf(open, LID_CLOSED + 0.25, smoothstep(0.55, 0.42, _hurt))
	_blink_t -= delta
	if _blink_t <= 0.0 and mood != "dead":
		_blink = 0.13
		_blink_t = _rng.randf_range(2.0, 5.5)
	var target := open
	if _blink > 0.0:
		_blink -= delta
		target = lerpf(LID_CLOSED, open, absf(_blink / 0.13 * 2.0 - 1.0))
	_lid = lerpf(_lid, target, clampf(delta * 30.0, 0.0, 1.0))
	var tilt_target := 0.36 if mood == "angry" else (0.12 if mood == "focus" else (-0.18 if mood == "hurt" else 0.0))
	_tilt = lerpf(_tilt, tilt_target, clampf(delta * 12.0, 0.0, 1.0))
	_bulge = lerpf(_bulge, 1.0 + (0.28 if _hurt > 0.4 else 0.0), clampf(delta * 9.0, 0.0, 1.0))
	for side in eyes:
		var e: MeshInstance3D = eyes[side]
		var rot := Basis.from_euler(Vector3(_look.y, _look.x + (0.06 if side == "r" else -0.06) * (1.0 if mood != "dead" else 0.0), 0.0))
		e.transform.basis = rot * Basis.from_scale(Vector3.ONE * float(_eye_scale[side]) * _bulge)
	for side in lids:
		var l: MeshInstance3D = lids[side]
		# the inner corner drops when angry (roll about the view axis)
		var roll := Basis(Vector3.BACK, _tilt * (1.0 if side == "r" else -1.0))
		l.transform.basis = roll * Basis(Vector3.RIGHT, _lid) * Basis.from_scale(Vector3.ONE * float(_lid_scale[side]) * maxf(_bulge, 1.0))
