class_name MotionPose
extends RefCounted
## One sampled frame of a skeletal animation for the 16 rig parts: the pelvis
## position, a local rotation per part (parent space, rest-aligned, see
## tools/motion/mo_rig.py), foot contact flags and the weapon grip expressed
## in the chest frame. Poses blend by slerp/lerp and take additive offsets
## (inertialisation) from previous poses.

const N := 16

var pelvis := Vector3.ZERO
var rot: Array[Quaternion] = []
var contact := Vector2.ZERO         # x = right foot, y = left foot (0..1)
var grip_w := 0.0                   # how much the hands hold the weapon (0 = free)
var grip_left := 1.0                # weight of the left hand on the hilt
var grip_pos := Vector3.ZERO        # hilt position in the chest frame (rig units)
var grip_blade := Vector3.UP        # blade direction, chest frame
var grip_edge := Vector3.FORWARD    # edge direction, chest frame


func _init() -> void:
	rot.resize(N)
	for i in N:
		rot[i] = Quaternion.IDENTITY


func copy_from(o: MotionPose) -> void:
	pelvis = o.pelvis
	for i in N:
		rot[i] = o.rot[i]
	contact = o.contact
	grip_w = o.grip_w
	grip_left = o.grip_left
	grip_pos = o.grip_pos
	grip_blade = o.grip_blade
	grip_edge = o.grip_edge


## this = lerp(this, o, w)
func blend(o: MotionPose, w: float) -> void:
	if w <= 0.0:
		return
	if w >= 1.0:
		copy_from(o)
		return
	pelvis = pelvis.lerp(o.pelvis, w)
	for i in N:
		rot[i] = rot[i].slerp(o.rot[i], w)
	contact = contact.lerp(o.contact, w)
	# grips only mix when both sides actually hold something
	if grip_w > 0.001 and o.grip_w > 0.001:
		grip_pos = grip_pos.lerp(o.grip_pos, w)
		grip_blade = grip_blade.lerp(o.grip_blade, w).normalized()
		grip_edge = grip_edge.lerp(o.grip_edge, w).normalized()
	elif o.grip_w > 0.001:
		grip_pos = o.grip_pos
		grip_blade = o.grip_blade
		grip_edge = o.grip_edge
	grip_w = lerpf(grip_w, o.grip_w, w)
	grip_left = lerpf(grip_left, o.grip_left, w)
