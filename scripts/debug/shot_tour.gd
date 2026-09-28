extends Node
## Debug helper: flies a camera through a list of viewpoints, saves a PNG for
## each one and quits. Used for automated visual checks:
##   godot --path . -- --tour /tmp/shots [--views spawn,aerial]

var out_dir := "user://shots"
var only: PackedStringArray = []
var settle_frames := 14
var views: Array = []
var cam: Camera3D
var _i := -1
var _wait := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out_dir)
	cam = Camera3D.new()
	cam.fov = 70.0
	cam.far = 4000.0
	add_child(cam)
	await get_tree().process_frame
	_build_views()
	_next()


func _build_views() -> void:
	var d := WorldData.current
	if d == null:
		return
	var s := d.spawn
	var vol := d.volcano
	var to_vol := (vol - s)
	to_vol.y = 0.0
	to_vol = to_vol.normalized()
	_add("spawn", s + Vector3(0, 2.2, 0) - to_vol * 6.0, s + to_vol * 60.0 + Vector3(0, 12, 0))
	_add("spawn_low", s + Vector3(0, 1.1, 0) - to_vol * 3.0 + Vector3(2, 0, 0), s + to_vol * 30.0 + Vector3(0, 1.5, 0))
	_add("aerial", s + Vector3(0, 260, 520), s + Vector3(0, 0, -150))
	_add("volcano", vol + Vector3(-300, 0, 900) + Vector3(0, 60, 0), vol + Vector3(0, 150, 0))
	for p in d.pois:
		if p.type in ["camp", "village", "temple", "shrine", "onsen", "landmark"] and not _has_type(p.type):
			var c := d.poi_position(p)
			_add(p.type, c + Vector3(18, 9, 22), c + Vector3(0, 2, 0))
	for lk in d.lakes:
		var c := Vector3(lk.x, float(lk.level), lk.z)
		_add("lake", c + Vector3(float(lk.radius) * 1.3, 8.0, 40.0), c)
	_add("coast", Vector3(60, 12, 760), Vector3(60, 0, 1000))
	if not only.is_empty():
		views = views.filter(func(v): return v.name in only)


func _has_type(t: String) -> bool:
	for v in views:
		if v.name == t:
			return true
	return false


func _add(n: String, pos: Vector3, target: Vector3) -> void:
	var d := WorldData.current
	var ground := d.get_height(pos.x, pos.z)
	pos.y = maxf(pos.y, ground + 1.5)
	views.append({"name": n, "pos": pos, "target": target})


func _next() -> void:
	_i += 1
	if _i >= views.size():
		print("TOUR DONE")
		get_tree().quit()
		return
	var v: Dictionary = views[_i]
	cam.global_position = v.pos
	cam.look_at(v.target, Vector3.UP)
	cam.make_current()
	_wait = settle_frames
	if get_tree().root.has_signal("tour_view"):
		pass


func _process(_d: float) -> void:
	if _i < 0 or _i >= views.size():
		return
	_wait -= 1
	if _wait > 0:
		return
	var img := get_viewport().get_texture().get_image()
	var path: String = out_dir.path_join("%02d_%s.png" % [_i, views[_i].name])
	img.save_png(path)
	print("shot ", path, "  fps=", Engine.get_frames_per_second())
	_next()
