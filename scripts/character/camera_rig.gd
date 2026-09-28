class_name CameraRig
extends Node3D
## Third-person orbit camera: over-the-shoulder framing, collision against
## the world, lock-on framing, trauma-based shake, FOV kicks for game feel
## and short cinematic overrides (kill cams, standoffs, shrines).

var target: Character
var cam: Camera3D
var yaw := 0.0
var pitch := -0.18
var distance := 3.4
var base_fov := 72.0
var sensitivity := 0.0024
var pad_sensitivity := 2.6
var lock_target: Character = null
var shoulder := 0.42
var trauma := 0.0
var fov_kick := 0.0
var _pivot := Vector3.ZERO
var _dist_current := 3.4
var _noise := FastNoiseLite.new()
var _t := 0.0
var _cine: Dictionary = {}
var _cine_blend := 0.0
var _shape := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var enabled := true
var external_look := false


func _ready() -> void:
	top_level = true
	cam = Camera3D.new()
	cam.name = "Camera"
	cam.near = 0.08
	cam.far = 4500.0
	cam.fov = base_fov
	add_child(cam)
	cam.make_current()
	_noise.seed = 5
	_noise.frequency = 0.9
	_shape.radius = 0.22
	_query.shape = _shape
	_query.collision_mask = 1
	Game.shake_requested.connect(add_trauma)
	Game.camera_rig = self
	Settings.changed.connect(func(_k: String) -> void: base_fov = float(Settings.get_value("fov", 72.0)))
	base_fov = float(Settings.get_value("fov", 72.0))


func add_trauma(t: float) -> void:
	trauma = clampf(trauma + t, 0.0, 1.0)


func kick_fov(amount: float) -> void:
	fov_kick += amount


func yaw_basis() -> Basis:
	return Basis(Vector3.UP, yaw)


func forward_flat() -> Vector3:
	return -yaw_basis().z


func _unhandled_input(event: InputEvent) -> void:
	if not enabled or not Game.is_playing():
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var inv := -1.0 if Settings.get_value("invert_y", false) else 1.0
		var s := sensitivity * float(Settings.get_value("mouse_sensitivity", 1.0))
		yaw -= event.relative.x * s
		pitch = clampf(pitch - event.relative.y * s * inv, -1.25, 0.95)


## Plays a scripted camera shot for `duration` seconds (real time).
func cinematic(xf: Transform3D, duration: float, fov := 55.0, follow: Node3D = null) -> void:
	_cine = {"xf": xf, "time": duration, "fov": fov, "follow": follow, "offset": xf.origin - (follow.global_position if follow else Vector3.ZERO)}
	_cine_blend = 0.0


func end_cinematic() -> void:
	_cine = {}


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var real := delta / maxf(Engine.time_scale, 0.02)
	_t += real
	# gamepad look
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if enabled and look.length() > 0.0 and Game.is_playing():
		var inv := -1.0 if Settings.get_value("invert_y", false) else 1.0
		yaw -= look.x * pad_sensitivity * real
		pitch = clampf(pitch - look.y * pad_sensitivity * real * 0.7 * inv, -1.25, 0.95)
	# follow the (interpolated) body, not the capsule, so ragdoll motion reads
	var tp := target.get_global_transform_interpolated().origin
	var chest := tp + Vector3(0, 1.55 * target.scale_factor, 0)
	if target.action == "knockdown" or target.dead:
		chest = target.body.part_interp_transform("chest").origin + Vector3(0, 0.3, 0)
	_pivot = _pivot.lerp(chest, clampf(real * 12.0, 0.0, 1.0)) if _pivot != Vector3.ZERO else chest
	# lock-on framing
	if lock_target and is_instance_valid(lock_target) and not lock_target.dead:
		var to := lock_target.global_position - target.global_position
		to.y = 0.0
		if to.length() > 0.5:
			var want := atan2(-to.x, -to.z)
			yaw = lerp_angle(yaw, want, clampf(real * 5.0, 0.0, 1.0))
			pitch = lerpf(pitch, -0.22, clampf(real * 2.0, 0.0, 1.0))
	var want_dist := 3.3
	if target.combat:
		want_dist = 3.9
	if target.sprinting:
		want_dist = 3.7
	if target.crouching:
		want_dist = 2.9
	distance = lerpf(distance, want_dist * target.scale_factor, clampf(real * 3.0, 0.0, 1.0))
	var rot := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var offset := rot * Vector3(shoulder, 0.1, distance)
	var desired := _pivot + offset
	# collision: sphere-cast from the pivot towards the desired position
	var space := get_world_3d().direct_space_state
	_query.transform = Transform3D(Basis(), _pivot + rot * Vector3(shoulder * 0.5, 0, 0))
	_query.motion = desired - _query.transform.origin
	var excl: Array[RID] = [target.get_rid()]
	for rb in target.body.all_bodies():
		excl.append((rb as RigidBody3D).get_rid())
	_query.exclude = excl
	var frac := space.cast_motion(_query)
	var safe_d := offset.length() * (frac[0] if frac.size() > 0 else 1.0)
	_dist_current = minf(lerpf(_dist_current, safe_d, clampf(real * 6.0, 0.0, 1.0)), safe_d)
	var pos := _pivot + offset.normalized() * maxf(_dist_current, 0.5)
	# keep the camera above the terrain
	var wd := WorldData.current
	if wd:
		var gh := wd.get_height(pos.x, pos.z)
		pos.y = maxf(pos.y, gh + 0.35)
	var xf := Transform3D(rot, pos)
	var look_at_pt := _pivot + rot * Vector3(shoulder * 0.6, 0.0, 0.0)
	xf = xf.looking_at(look_at_pt + rot * Vector3(0, 0, -8.0), Vector3.UP)
	# shake
	trauma = maxf(0.0, trauma - real * 1.6)
	var sh := trauma * trauma
	if sh > 0.0:
		var nx := _noise.get_noise_2d(_t * 40.0, 0.0)
		var ny := _noise.get_noise_2d(0.0, _t * 40.0)
		var nr := _noise.get_noise_2d(_t * 40.0, 100.0)
		xf.origin += xf.basis * Vector3(nx, ny, 0.0) * 0.22 * sh
		xf.basis = xf.basis * Basis(Vector3.FORWARD, nr * 0.07 * sh)
	# cinematic override
	var fov := base_fov + fov_kick + (8.0 if target.sprinting else 0.0)
	fov_kick = lerpf(fov_kick, 0.0, clampf(real * 6.0, 0.0, 1.0))
	if not _cine.is_empty():
		_cine.time -= real
		_cine_blend = minf(1.0, _cine_blend + real * 5.0)
		var cxf: Transform3D = _cine.xf
		if _cine.follow and is_instance_valid(_cine.follow):
			cxf.origin = (_cine.follow as Node3D).global_position + _cine.offset
		xf = xf.interpolate_with(cxf, smoothstep(0.0, 1.0, _cine_blend))
		fov = lerpf(fov, float(_cine.fov), _cine_blend)
		if _cine.time <= 0.0:
			_cine = {}
	elif _cine_blend > 0.0:
		_cine_blend = maxf(0.0, _cine_blend - real * 3.0)
	global_transform = Transform3D.IDENTITY
	cam.global_transform = xf
	cam.fov = lerpf(cam.fov, fov, clampf(real * 10.0, 0.0, 1.0))
