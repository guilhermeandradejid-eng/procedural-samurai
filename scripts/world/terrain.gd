class_name Terrain
extends Node3D
## GPU displaced terrain made of a quadtree of chunks that share a single grid
## mesh. Coarse chunks hide when the camera gets close (visibility range) and
## their children appear instead (visibility_parent), a classic HLOD setup.
## Skirts hide the cracks between neighbouring LODs. Collision is a single
## HeightMapShape3D (Jolt) scaled to the world spacing.

const GRID := 32
const LEVELS := 5
const BASE_CHUNK := 64.0
## distance at which a chunk of level L is replaced by its 4 children
const SPLIT_DIST: Array[float] = [0.0, 185.0, 390.0, 800.0, 1650.0]

var data: WorldData
var material: ShaderMaterial
var grid_mesh: ArrayMesh
var body: StaticBody3D
var _ranges := {}  # Vector2i(level0 chunk) -> Vector2(min, max)
var chunk_count := 0
var origin := -1023.0


func build(world_data: WorldData, mat: ShaderMaterial) -> void:
	data = world_data
	material = mat
	grid_mesh = _make_grid_mesh(GRID)
	_compute_ranges()
	var top := BASE_CHUNK * pow(2.0, LEVELS - 1)
	# level-0 vertices land exactly on heightmap samples (x = -half_extent + k * spacing)
	for iz in 2:
		for ix in 2:
			_make_chunk(LEVELS - 1, Vector2(origin + ix * top, origin + iz * top), null)
	_build_collision()


func _make_grid_mesh(n: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for z in n + 1:
		for x in n + 1:
			verts.append(Vector3(float(x) / n, 0.0, float(z) / n))
			uv2.append(Vector2.ZERO)
	for z in n:
		for x in n:
			var i := z * (n + 1) + x
			# same diagonal as the physics heightfield: (x+1, z) -> (x, z+1)
			idx.append_array([i, i + 1, i + n + 1, i + 1, i + n + 2, i + n + 1])
	# skirts: one extra vertex below every border vertex
	var border: Array[int] = []
	for x in n + 1:
		border.append(x)  # z = 0 edge (north)
	for z in range(1, n + 1):
		border.append(z * (n + 1) + n)  # x = n edge (east)
	for x in range(n - 1, -1, -1):
		border.append(n * (n + 1) + x)  # z = n edge (south)
	for z in range(n - 1, 0, -1):
		border.append(z * (n + 1))  # x = 0 edge (west)
	var skirt_start := verts.size()
	for b in border:
		verts.append(verts[b])
		uv2.append(Vector2(1.0, 0.0))
	var count := border.size()
	for k in count:
		var a := border[k]
		var b := border[(k + 1) % count]
		var sa := skirt_start + k
		var sb := skirt_start + (k + 1) % count
		# border runs clockwise seen from above -> these triangles face outward
		idx.append_array([a, sa, b, b, sa, sb])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _compute_ranges() -> void:
	# min/max height of every level-0 chunk, from a 1-in-2 subsample
	var cells := int(2.0 * 1024.0 / BASE_CHUNK)
	origin = -data.half_extent
	var mins := PackedFloat32Array()
	var maxs := PackedFloat32Array()
	mins.resize(cells * cells)
	maxs.resize(cells * cells)
	mins.fill(INF)
	maxs.fill(-INF)
	var n := data.size
	var step := 2
	for gz in range(0, n, step):
		var wz := (gz - (n - 1) * 0.5) * data.spacing
		var cz := clampi(int((wz - origin) / BASE_CHUNK), 0, cells - 1)
		var row := gz * n
		for gx in range(0, n, step):
			var h := data.heights[row + gx]
			var wx := (gx - (n - 1) * 0.5) * data.spacing
			var cx := clampi(int((wx - origin) / BASE_CHUNK), 0, cells - 1)
			var k := cz * cells + cx
			if h < mins[k]:
				mins[k] = h
			if h > maxs[k]:
				maxs[k] = h
	for cz in cells:
		for cx in cells:
			var k := cz * cells + cx
			_ranges[Vector2i(cx, cz)] = Vector2(mins[k] - 3.0, maxs[k] + 3.0)


func _range_for(chunk_origin: Vector2, size: float) -> Vector2:
	var c0 := Vector2i(int((chunk_origin.x - origin) / BASE_CHUNK), int((chunk_origin.y - origin) / BASE_CHUNK))
	var c := int(size / BASE_CHUNK)
	var r := Vector2(INF, -INF)
	for z in c:
		for x in c:
			var v: Vector2 = _ranges.get(c0 + Vector2i(x, z), Vector2(data.min_height, data.max_height))
			r.x = minf(r.x, v.x)
			r.y = maxf(r.y, v.y)
	return r


func _make_chunk(level: int, origin: Vector2, parent: MeshInstance3D) -> void:
	var size := BASE_CHUNK * pow(2.0, level)
	var mi := MeshInstance3D.new()
	mi.name = "L%d_%d_%d" % [level, int(origin.x), int(origin.y)]
	mi.mesh = grid_mesh
	mi.material_override = material
	mi.transform = Transform3D(Basis.from_scale(Vector3(size, 1.0, size)), Vector3(origin.x, 0.0, origin.y))
	var r := _range_for(origin, size)
	var skirt := size / GRID * 2.0
	mi.custom_aabb = AABB(Vector3(0.0, r.x - skirt, 0.0), Vector3(1.0, r.y - r.x + skirt, 1.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if level > 0:
		mi.visibility_range_begin = SPLIT_DIST[level]
	add_child(mi)
	chunk_count += 1
	if parent != null:
		mi.visibility_parent = mi.get_path_to(parent)
	if level > 0:
		var half := size * 0.5
		for iz in 2:
			for ix in 2:
				_make_chunk(level - 1, origin + Vector2(ix * half, iz * half), mi)


func _build_collision() -> void:
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := HeightMapShape3D.new()
	shape.map_width = data.size
	shape.map_depth = data.size
	# the shape is scaled uniformly by `spacing`, so heights are divided by it
	var scaled := data.heights.duplicate()
	var inv := 1.0 / data.spacing
	for i in scaled.size():
		scaled[i] *= inv
	shape.map_data = scaled
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.scale = Vector3.ONE * data.spacing
	body.add_child(cs)
	body.set_meta("surface", "terrain")
	add_child(body)
