class_name Forest
extends Node3D
## Trees and rocks from assets/world/scatter.bin (tools/worldgen/scatter.py).
## Drawn as chunked MultiMeshes straight on the RenderingServer, one
## instance per (chunk, model, LOD) with a per-instance LOD band so every
## tree picks its own level and cross-fades; far chunks are culled by
## visibility range. Trunk and rock collision is streamed around the player.

const LOD0_CHUNK := 64.0
const FAR_CHUNK := 128.0
const PHYS_CHUNK := 32.0
const PHYS_RADIUS := 72.0
const TRUNK_HEIGHT := 4.2
const FIELDS := 6

var data: WorldData
var kinds: Array = []
var category := {}
var tree_info := {}
var meshes := {}           # kind -> Array[Mesh] (lod0, lod1, lod2) or [mesh]
var convex := {}           # rock kind -> PackedVector3Array (unit scale)
var records := PackedFloat32Array()
var count := 0
var _instances: Array = []  # {rid, mm, level}
var _phys_cells := {}       # Vector2i -> PackedInt32Array
var _phys_bodies := {}      # Vector2i -> RID
var _shapes := {}           # key -> RID
var _last_center := Vector2(INF, INF)
var _half := 1023.0


func build(world_data: WorldData) -> void:
	data = world_data
	_half = data.half_extent
	var jf := FileAccess.open("res://assets/world/scatter.json", FileAccess.READ)
	if jf == null:
		push_warning("Forest: scatter.json missing - run tools/worldgen/scatter.py")
		return
	var info: Dictionary = JSON.parse_string(jf.get_as_text())
	kinds = info.kinds
	category = info.category
	var tf := FileAccess.open("res://assets/models/trees/trees.json", FileAccess.READ)
	if tf:
		tree_info = JSON.parse_string(tf.get_as_text())
	records = FileAccess.get_file_as_bytes("res://assets/world/scatter.bin").to_float32_array()
	count = records.size() / FIELDS
	_load_models()
	_build_render()
	_bucket_physics()
	Settings.changed.connect(func(key: String) -> void:
		if key == "quality":
			_apply_bands())


func _load_models() -> void:
	for k in kinds:
		var is_tree: bool = category.get(k, "tree") == "tree"
		var path := "res://assets/models/%s/%s.glb" % ["trees" if is_tree else "rocks", k]
		if not ResourceLoader.exists(path):
			push_warning("Forest: missing model " + path)
			continue
		var root: Node = (load(path) as PackedScene).instantiate()
		var list: Array[Mesh] = []
		if is_tree:
			for lod in ["lod0", "lod1", "lod2"]:
				var mi := root.get_node_or_null(lod) as MeshInstance3D
				if mi:
					list.append(MaterialLibrary.baked_mesh(mi.mesh))
		else:
			for c in root.get_children():
				if c is MeshInstance3D:
					var m: Mesh = (c as MeshInstance3D).mesh
					list.append(MaterialLibrary.baked_mesh(m))
					var shape := m.create_convex_shape(true, true) as ConvexPolygonShape3D
					if shape:
						convex[k] = shape.points
					break
		meshes[k] = list
		root.free()


# ------------------------------------------------------------------ render

func _chunk_of(x: float, z: float, size: float) -> Vector2i:
	return Vector2i(int(floor((x + _half) / size)), int(floor((z + _half) / size)))


func _build_render() -> void:
	var near := {}   # Vector3i(cx, cz, kind) -> PackedInt32Array (64 m chunks, LOD0)
	var far := {}    # 128 m chunks (LOD1, LOD2, rocks)
	for i in count:
		var k := int(records[i * FIELDS])
		var x := records[i * FIELDS + 1]
		var z := records[i * FIELDS + 3]
		var cf := _chunk_of(x, z, FAR_CHUNK)
		var kf := Vector3i(cf.x, cf.y, k)
		if not far.has(kf):
			far[kf] = PackedInt32Array()
		far[kf].append(i)
		if category.get(kinds[k], "tree") == "tree":
			var cn := _chunk_of(x, z, LOD0_CHUNK)
			var kn := Vector3i(cn.x, cn.y, k)
			if not near.has(kn):
				near[kn] = PackedInt32Array()
			near[kn].append(i)
	var scenario := get_world_3d().scenario
	for key in near:
		var list: Array = meshes.get(kinds[key.z], [])
		if list.size() >= 1:
			_add_instance(scenario, list[0], near[key], 0)
	for key in far:
		var kname: String = kinds[key.z]
		var list: Array = meshes.get(kname, [])
		if list.is_empty():
			continue
		if category.get(kname, "tree") == "tree":
			if list.size() >= 2:
				_add_instance(scenario, list[1], far[key], 1)
			if list.size() >= 3:
				_add_instance(scenario, list[2], far[key], 2)
		else:
			_add_instance(scenario, list[0], far[key], 3 if kname == "pebbles_0" else 4)
	_apply_bands()


func _add_instance(scenario: RID, mesh: Mesh, idx: PackedInt32Array, level: int) -> void:
	var mm := RenderingServer.multimesh_create()
	RenderingServer.multimesh_set_mesh(mm, mesh.get_rid())
	RenderingServer.multimesh_allocate_data(mm, idx.size(), RenderingServer.MULTIMESH_TRANSFORM_3D)
	var buf := PackedFloat32Array()
	buf.resize(idx.size() * 12)
	var maab := mesh.get_aabb()
	var reach := maxf(maxf(absf(maab.position.x), absf(maab.end.x)), maxf(absf(maab.position.z), absf(maab.end.z)))
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for j in idx.size():
		var r := idx[j] * FIELDS
		var yaw := records[r + 4]
		var s := records[r + 5]
		var o := Vector3(records[r + 1], records[r + 2], records[r + 3])
		var c := cos(yaw) * s
		var sn := sin(yaw) * s
		var w := j * 12
		# rotation about Y scaled uniformly, row-major 3x4
		buf[w + 0] = c
		buf[w + 1] = 0.0
		buf[w + 2] = sn
		buf[w + 3] = o.x
		buf[w + 4] = 0.0
		buf[w + 5] = s
		buf[w + 6] = 0.0
		buf[w + 7] = o.y
		buf[w + 8] = -sn
		buf[w + 9] = 0.0
		buf[w + 10] = c
		buf[w + 11] = o.z
		var rr := reach * s
		lo = lo.min(o + Vector3(-rr, maab.position.y * s, -rr))
		hi = hi.max(o + Vector3(rr, maab.end.y * s, rr))
	RenderingServer.multimesh_set_buffer(mm, buf)
	RenderingServer.multimesh_set_custom_aabb(mm, AABB(lo, hi - lo))
	var inst := RenderingServer.instance_create2(mm, scenario)
	var shadows := RenderingServer.SHADOW_CASTING_SETTING_ON
	if level == 2 or level == 3:
		shadows = RenderingServer.SHADOW_CASTING_SETTING_OFF
	RenderingServer.instance_geometry_set_cast_shadows_setting(inst, shadows)
	_instances.append({"rid": inst, "mm": mm, "level": level, "half": (hi - lo).length() * 0.5})


## LOD distances come from the quality preset; each chunk is also culled as
## a whole once all of its trees are outside the band.
func _apply_bands() -> void:
	var q := Settings.quality()
	var d0: float = q.tree_lod0
	var d1: float = q.tree_lod1
	var far_d: float = q.tree_far
	var rock_far: float = q.get("rock_far", 380.0)
	for it in _instances:
		var band := Vector2.ZERO
		match int(it.level):
			0:
				band = Vector2(0.0, d0)
			1:
				band = Vector2(d0, d1)
			2:
				band = Vector2(d1, far_d)
			3:
				band = Vector2(0.0, minf(rock_far * 0.35, 120.0))
			_:
				band = Vector2(0.0, rock_far)
		var hd: float = it.half
		var vmin := maxf(0.0, band.x - hd - 12.0)
		var vmax := band.y + hd + 12.0
		RenderingServer.instance_geometry_set_visibility_range(it.rid, vmin, vmax, 0.0, 0.0, RenderingServer.VISIBILITY_RANGE_FADE_DISABLED)
		RenderingServer.instance_geometry_set_shader_parameter(it.rid, "lod_band", band)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		RenderingServer.global_shader_parameter_set("lod_center", cam.global_position)


func _exit_tree() -> void:
	for it in _instances:
		RenderingServer.free_rid(it.rid)
		RenderingServer.free_rid(it.mm)
	_instances.clear()
	for b in _phys_bodies.values():
		PhysicsServer3D.free_rid(b)
	_phys_bodies.clear()
	for s in _shapes.values():
		PhysicsServer3D.free_rid(s)
	_shapes.clear()


# ------------------------------------------------------------------ physics

func _bucket_physics() -> void:
	for i in count:
		var kname: String = kinds[int(records[i * FIELDS])]
		if kname == "pebbles_0":
			continue
		var c := _chunk_of(records[i * FIELDS + 1], records[i * FIELDS + 3], PHYS_CHUNK)
		if not _phys_cells.has(c):
			_phys_cells[c] = PackedInt32Array()
		_phys_cells[c].append(i)


func _physics_process(_delta: float) -> void:
	var center := Vector3.ZERO
	var p := Game.get_player()
	if p:
		center = p.global_position
	else:
		var cam := get_viewport().get_camera_3d()
		if cam == null:
			return
		center = cam.global_position
	var c2 := Vector2(center.x, center.z)
	if c2.distance_to(_last_center) < 6.0:
		return
	_last_center = c2
	update_physics_around(center)


## Makes sure collision exists within PHYS_RADIUS of `center` (also used by
## the population system before spawning enemies far from the player).
func update_physics_around(center: Vector3) -> void:
	var cc := _chunk_of(center.x, center.z, PHYS_CHUNK)
	var r := int(ceil(PHYS_RADIUS / PHYS_CHUNK)) + 1
	var need := {}
	for dx in range(-r, r + 1):
		for dz in range(-r, r + 1):
			var key := cc + Vector2i(dx, dz)
			var mid := Vector2((key.x + 0.5) * PHYS_CHUNK - _half, (key.y + 0.5) * PHYS_CHUNK - _half)
			if mid.distance_to(Vector2(center.x, center.z)) < PHYS_RADIUS + PHYS_CHUNK * 0.75:
				need[key] = true
	for key in _phys_bodies.keys():
		if not need.has(key):
			PhysicsServer3D.free_rid(_phys_bodies[key])
			_phys_bodies.erase(key)
	for key in need:
		if not _phys_bodies.has(key) and _phys_cells.has(key):
			_phys_bodies[key] = _make_body(_phys_cells[key])


func _make_body(idx: PackedInt32Array) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	PhysicsServer3D.body_set_collision_layer(body, 1)
	PhysicsServer3D.body_set_collision_mask(body, 0)
	for i in idx:
		var r := i * FIELDS
		var kname: String = kinds[int(records[r])]
		var s := records[r + 5]
		var yaw := records[r + 4]
		var o := Vector3(records[r + 1], records[r + 2], records[r + 3])
		if category.get(kname, "tree") == "tree":
			var info: Dictionary = tree_info.get(kname, {})
			var rad := float(info.get("trunk_radius", 0.22)) * s * 1.15
			if kname.begins_with("bamboo"):
				rad = 0.9 * s
			var h := TRUNK_HEIGHT * s
			var shape := _capsule(rad, h)
			PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(), o + Vector3(0, h * 0.5, 0)))
		else:
			if not convex.has(kname):
				continue
			var sq := snappedf(s, 0.1)
			var shape := _convex(kname, sq)
			PhysicsServer3D.body_add_shape(body, shape, Transform3D(Basis(Vector3.UP, yaw), o))
	PhysicsServer3D.body_set_space(body, get_world_3d().space)
	return body


func _capsule(radius: float, height: float) -> RID:
	var rq := snappedf(radius, 0.02)
	var hq := snappedf(height, 0.25)
	var key := "cap_%.2f_%.2f" % [rq, hq]
	if not _shapes.has(key):
		var sh := PhysicsServer3D.capsule_shape_create()
		PhysicsServer3D.shape_set_data(sh, {"radius": rq, "height": maxf(hq, rq * 2.0 + 0.01)})
		_shapes[key] = sh
	return _shapes[key]


func _convex(kname: String, s: float) -> RID:
	var key := "%s_%.1f" % [kname, s]
	if not _shapes.has(key):
		var pts: PackedVector3Array = convex[kname]
		var scaled := PackedVector3Array()
		scaled.resize(pts.size())
		for i in pts.size():
			scaled[i] = pts[i] * s
		var sh := PhysicsServer3D.convex_polygon_shape_create()
		PhysicsServer3D.shape_set_data(sh, scaled)
		_shapes[key] = sh
	return _shapes[key]


## Nearest tree trunk/rock record index within `radius` (-1 if none); used
## to keep buildings and camps clear and by the kill-cam framing.
func nearest(x: float, z: float, radius: float) -> int:
	var c := _chunk_of(x, z, PHYS_CHUNK)
	var best := -1
	var bd := radius * radius
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var key := c + Vector2i(dx, dz)
			if not _phys_cells.has(key):
				continue
			for i in _phys_cells[key]:
				var ddx := records[i * FIELDS + 1] - x
				var ddz := records[i * FIELDS + 3] - z
				var d := ddx * ddx + ddz * ddz
				if d < bd:
					bd = d
					best = i
	return best
