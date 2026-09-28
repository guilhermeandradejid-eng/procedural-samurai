class_name Water
extends Node3D
## Ocean (a polar grid that follows the camera, dense near the viewer and
## sparse towards the horizon) and lake surfaces sharing the water shader.

var data: WorldData
var ocean: MeshInstance3D
var ocean_mat: ShaderMaterial
var lakes: Array[MeshInstance3D] = []
var normal_a: NoiseTexture2D
var normal_b: NoiseTexture2D


func build(world_data: WorldData) -> void:
	data = world_data
	normal_a = _normal_noise(21, 0.02)
	normal_b = _normal_noise(22, 0.045)
	var foam: Texture2D = load("res://assets/textures/fx/foam.png")
	ocean_mat = _make_material(foam)
	ocean_mat.set_shader_parameter("water_level", data.sea_level)
	ocean = MeshInstance3D.new()
	ocean.name = "Ocean"
	ocean.mesh = _polar_mesh(110, 96, 0.55, 1.052)
	ocean.material_override = ocean_mat
	ocean.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ocean.custom_aabb = AABB(Vector3(-6000, -20, -6000), Vector3(12000, 40, 12000))
	add_child(ocean)
	for lk in data.lakes:
		var m := MeshInstance3D.new()
		m.name = "Lake"
		var pm := PlaneMesh.new()
		var r := float(lk.radius) * 1.8
		pm.size = Vector2(r * 2.0, r * 2.0)
		pm.subdivide_width = 48
		pm.subdivide_depth = 48
		m.mesh = pm
		m.position = Vector3(float(lk.x), float(lk.level), float(lk.z))
		var mat := _make_material(foam)
		mat.set_shader_parameter("water_level", float(lk.level))
		mat.set_shader_parameter("wave_height", 0.06)
		mat.set_shader_parameter("wave_length", 0.35)
		mat.set_shader_parameter("deep_color", Color(0.02, 0.07, 0.08))
		mat.set_shader_parameter("shallow_color", Color(0.1, 0.3, 0.26))
		mat.set_shader_parameter("clarity", 0.28)
		mat.set_shader_parameter("surf", 0.0)
		mat.set_shader_parameter("shore_foam", 0.25)
		mat.set_shader_parameter("detail_strength", 0.3)
		mat.set_shader_parameter("roughness", 0.02)
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(m)
		lakes.append(m)


func make_pool(center: Vector3, radius: float, milky := 0.6) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	m.mesh = pm
	m.position = center
	var mat := _make_material(load("res://assets/textures/fx/foam.png"))
	mat.set_shader_parameter("water_level", center.y)
	mat.set_shader_parameter("wave_height", 0.0)
	mat.set_shader_parameter("milky", milky)
	mat.set_shader_parameter("surf", 0.0)
	mat.set_shader_parameter("shore_foam", 0.0)
	mat.set_shader_parameter("clarity", 0.9)
	mat.set_shader_parameter("detail_strength", 0.15)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(m)
	return m


func _make_material(foam: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("normal_a", normal_a)
	mat.set_shader_parameter("normal_b", normal_b)
	mat.set_shader_parameter("foam_tex", foam)
	mat.render_priority = -1
	return mat


func _normal_noise(seed: int, freq: float) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.frequency = freq
	n.fractal_octaves = 4
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	var t := NoiseTexture2D.new()
	t.width = 512
	t.height = 512
	t.seamless = true
	t.as_normal_map = true
	t.bump_strength = 6.0
	t.generate_mipmaps = true
	t.noise = n
	return t


## Radial grid: `rings` rings growing geometrically, `segs` segments around.
func _polar_mesh(rings: int, segs: int, first: float, growth: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	verts.append(Vector3.ZERO)
	var r := 0.0
	var step := first
	var radii: Array[float] = []
	for k in rings:
		r += step
		step *= growth
		radii.append(r)
		for s in segs:
			var a := TAU * float(s) / segs
			verts.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	# centre fan
	for s in segs:
		var a := 1 + s
		var b := 1 + (s + 1) % segs
		idx.append_array([0, a, b])
	for k in rings - 1:
		var base0 := 1 + k * segs
		var base1 := 1 + (k + 1) * segs
		for s in segs:
			var a0 := base0 + s
			var a1 := base0 + (s + 1) % segs
			var b0 := base1 + s
			var b1 := base1 + (s + 1) % segs
			idx.append_array([a0, b0, a1, a1, b0, b1])
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null or ocean == null:
		return
	var p := cam.global_position
	ocean.global_position = Vector3(snappedf(p.x, 2.0), data.sea_level, snappedf(p.z, 2.0))
