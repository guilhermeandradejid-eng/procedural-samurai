class_name MotionClip
extends RefCounted
## A baked skeletal animation produced by tools/motion (retargeted motion
## capture, authored key poses or text-to-motion output). Stored as JSON in
## assets/motion; see tools/motion/clipio.py for the format.

const DIR := "res://assets/motion/"

var clip_name := ""
var fps := 30.0
var frames := 0
var loop := false
var duration := 0.0
var speed := 0.0                    # native ground speed (rig units / s), 0 = in place
var events := {}
var meta := {}
var pelvis := PackedFloat32Array()
var rot := PackedFloat32Array()
var contact := PackedByteArray()
var grip := PackedFloat32Array()
var has_grip := false

static var _cache := {}


## Loads (and caches) a clip; null when the file does not exist.
static func get_clip(n: String) -> MotionClip:
	if _cache.has(n):
		return _cache[n]
	var path := DIR + n + ".json"
	var clip: MotionClip = null
	if FileAccess.file_exists(path):
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if data is Dictionary:
			clip = MotionClip.new()
			clip._parse(data)
	_cache[n] = clip
	return clip


func _parse(d: Dictionary) -> void:
	clip_name = d.name
	fps = float(d.fps)
	frames = int(d.frames)
	loop = bool(d.loop)
	duration = float(d.duration)
	speed = float(d.get("speed", 0.0))
	events = d.get("events", {})
	meta = d.get("meta", {})
	pelvis = PackedFloat32Array(d.pelvis)
	rot = PackedFloat32Array(d.rot)
	contact = PackedByteArray()
	contact.resize(d.contact.size())
	for i in d.contact.size():
		contact[i] = int(d.contact[i])
	if d.has("grip"):
		grip = PackedFloat32Array(d.grip)
		has_grip = true


## Writes the pose at time `t` (seconds) into `out`.
func sample(t: float, out: MotionPose) -> void:
	var f := t * fps
	var i0: int
	var i1: int
	var u: float
	if loop:
		f = fposmod(f, float(frames))
		i0 = int(floorf(f))
		u = f - float(i0)
		i0 = i0 % frames
		i1 = (i0 + 1) % frames
	else:
		f = clampf(f, 0.0, float(frames - 1))
		i0 = int(floorf(f))
		u = f - float(i0)
		i1 = mini(i0 + 1, frames - 1)
	var p0 := i0 * 3
	var p1 := i1 * 3
	out.pelvis = Vector3(pelvis[p0], pelvis[p0 + 1], pelvis[p0 + 2]).lerp(Vector3(pelvis[p1], pelvis[p1 + 1], pelvis[p1 + 2]), u)
	var r0 := i0 * MotionPose.N * 4
	var r1 := i1 * MotionPose.N * 4
	for i in MotionPose.N:
		var a := Quaternion(rot[r0 + i * 4], rot[r0 + i * 4 + 1], rot[r0 + i * 4 + 2], rot[r0 + i * 4 + 3])
		var b := Quaternion(rot[r1 + i * 4], rot[r1 + i * 4 + 1], rot[r1 + i * 4 + 2], rot[r1 + i * 4 + 3])
		out.rot[i] = a.slerp(b, u) if u > 0.0001 else a
	# contact flags switch at the nearest frame
	var cf := i0 if u < 0.5 else i1
	out.contact = Vector2(contact[cf * 2], contact[cf * 2 + 1])
	if has_grip:
		var g0 := i0 * 12
		var g1 := i1 * 12
		var w0 := grip[g0 + 9]
		var w1 := grip[g1 + 9]
		out.grip_w = lerpf(w0, w1, u)
		out.grip_left = lerpf(grip[g0 + 10], grip[g1 + 10], u)
		var pa := Vector3(grip[g0], grip[g0 + 1], grip[g0 + 2])
		var pb := Vector3(grip[g1], grip[g1 + 1], grip[g1 + 2])
		out.grip_pos = pa.lerp(pb, u)
		var ba := Vector3(grip[g0 + 3], grip[g0 + 4], grip[g0 + 5])
		var bb := Vector3(grip[g1 + 3], grip[g1 + 4], grip[g1 + 5])
		out.grip_blade = ba.lerp(bb, u).normalized()
		var ea := Vector3(grip[g0 + 6], grip[g0 + 7], grip[g0 + 8])
		var eb := Vector3(grip[g1 + 6], grip[g1 + 7], grip[g1 + 8])
		out.grip_edge = ea.lerp(eb, u).normalized()
	else:
		out.grip_w = 0.0
