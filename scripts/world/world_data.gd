class_name WorldData
extends RefCounted
## Loads the generated world (heightmap, biome maps, layout json) and answers
## spatial queries (height, normal, biome samples, lakes, regions).

const DIR := "res://assets/world/"

static var current: WorldData

var size := 1024
var spacing := 2.0
var half_extent := 1023.0
var sea_level := 0.0
var min_height := 0.0
var max_height := 0.0
var heights := PackedFloat32Array()
var height_image: Image
var height_texture: ImageTexture
var normal_texture: Texture2D
var splat_texture: Texture2D
var veg_texture: Texture2D
var splat_image: Image
var veg_image: Image
var meta := {}
var pois: Array = []
var roads: Array = []
var lakes: Array = []
var regions: Array = []
var spawn := Vector3.ZERO
var volcano := Vector3.ZERO
var tree_codes := {}


func load_all() -> bool:
	var f := FileAccess.open(DIR + "world.json", FileAccess.READ)
	if f == null:
		push_error("WorldData: missing world.json - run tools/worldgen/generate_world.py")
		return false
	meta = JSON.parse_string(f.get_as_text())
	size = int(meta.size)
	spacing = float(meta.spacing)
	half_extent = float(meta.half_extent)
	sea_level = float(meta.sea_level)
	min_height = float(meta.min_height)
	max_height = float(meta.max_height)
	pois = meta.pois
	roads = meta.roads
	lakes = meta.lakes
	regions = meta.regions
	tree_codes = meta.tree_types
	var bytes := FileAccess.get_file_as_bytes(DIR + "height.f32")
	if bytes.size() != size * size * 4:
		push_error("WorldData: height.f32 has unexpected size %d" % bytes.size())
		return false
	heights = bytes.to_float32_array()
	height_image = Image.create_from_data(size, size, false, Image.FORMAT_RF, bytes)
	height_texture = ImageTexture.create_from_image(height_image)
	normal_texture = load(DIR + "normal.png")
	splat_texture = load(DIR + "splat.png")
	veg_texture = load(DIR + "veg.png")
	splat_image = _cpu_image(splat_texture)
	veg_image = _cpu_image(veg_texture)
	spawn = Vector3(meta.spawn.x, 0.0, meta.spawn.z)
	spawn.y = get_height(spawn.x, spawn.z)
	volcano = Vector3(meta.volcano.x, 0.0, meta.volcano.z)
	volcano.y = get_height(volcano.x, volcano.z)
	current = self
	return true


func _cpu_image(tex: Texture2D) -> Image:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


## Pushes the world textures to the global shader uniforms used by every
## terrain-aware shader (terrain, grass, water, particles).
func apply_shader_globals() -> void:
	RenderingServer.global_shader_parameter_set("terrain_height", height_texture)
	RenderingServer.global_shader_parameter_set("terrain_normal", normal_texture)
	RenderingServer.global_shader_parameter_set("terrain_splat", splat_texture)
	RenderingServer.global_shader_parameter_set("terrain_veg", veg_texture)
	RenderingServer.global_shader_parameter_set("terrain_info", Vector4(size, spacing, half_extent, sea_level))


func grid_coord(x: float, z: float) -> Vector2:
	var c := (size - 1) * 0.5
	return Vector2(x / spacing + c, z / spacing + c)


func world_from_grid(gx: float, gz: float) -> Vector2:
	var c := (size - 1) * 0.5
	return Vector2((gx - c) * spacing, (gz - c) * spacing)


func get_height(x: float, z: float) -> float:
	# Same triangulation as the physics heightfield (diagonal from (1,0) to (0,1)),
	# so gameplay queries match collision exactly.
	var g := grid_coord(x, z)
	var fx := clampf(g.x, 0.0, size - 1.001)
	var fz := clampf(g.y, 0.0, size - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * size + ix
	var a := heights[i]
	var b := heights[i + 1]
	var c := heights[i + size]
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	var d := heights[i + size + 1]
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


func get_normal(x: float, z: float) -> Vector3:
	var e := spacing
	var hl := get_height(x - e, z)
	var hr := get_height(x + e, z)
	var hd := get_height(x, z - e)
	var hu := get_height(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func slope_degrees(x: float, z: float) -> float:
	return rad_to_deg(acos(clampf(get_normal(x, z).y, -1.0, 1.0)))


func _sample(img: Image, x: float, z: float) -> Color:
	var g := grid_coord(x, z)
	var ix := clampi(int(round(g.x)), 0, size - 1)
	var iz := clampi(int(round(g.y)), 0, size - 1)
	return img.get_pixel(ix, iz)


## R meadow grass, G golden pampas, B dirt/road, A forest floor
func sample_splat(x: float, z: float) -> Color:
	return _sample(splat_image, x, z)


## R tree density, G tree type code, B flowers, A grass height
func sample_veg(x: float, z: float) -> Color:
	return _sample(veg_image, x, z)


func tree_type_name(code01: float) -> String:
	var code := int(round(code01 * 255.0))
	var best := ""
	var best_d := 999
	for k in tree_codes:
		var d: int = abs(int(tree_codes[k]) - code)
		if d < best_d:
			best_d = d
			best = k
	return best


func is_inside_world(x: float, z: float, margin := 0.0) -> bool:
	return absf(x) < half_extent - margin and absf(z) < half_extent - margin


## Returns the water surface height at (x, z) if the point is covered by a
## lake or the sea, otherwise NAN.
func water_level_at(x: float, z: float) -> float:
	var h := get_height(x, z)
	for lk in lakes:
		var dx := x - float(lk.x)
		var dz := (z - float(lk.z)) * 1.25
		if dx * dx + dz * dz < pow(float(lk.radius) * 1.6, 2.0) and h < float(lk.level):
			return float(lk.level)
	if h < sea_level:
		return sea_level
	return NAN


func region_name_at(x: float, z: float) -> String:
	var best := ""
	var best_d := INF
	for r in regions:
		var d := Vector2(x - float(r.x), z - float(r.z)).length_squared()
		if d < best_d:
			best_d = d
			best = r.name
	return best


func pois_of_type(t: String) -> Array:
	var out := []
	for p in pois:
		if p.type == t:
			out.append(p)
	return out


func poi_position(p: Dictionary) -> Vector3:
	return Vector3(float(p.x), get_height(float(p.x), float(p.z)), float(p.z))
