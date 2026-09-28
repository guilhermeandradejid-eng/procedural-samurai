class_name GrassSystem
extends Node3D
## Camera-following vegetation layers rendered with GPU particles:
## short grass (near + far LOD), golden pampas grass with plumes and red
## spider lilies. Instances are placed on the GPU from the world maps.

var layers: Array[GPUParticles3D] = []
var _process_shader: Shader
var _rng := RandomNumberGenerator.new()


func build() -> void:
	_rng.seed = 4242
	_process_shader = load("res://shaders/grass_particles.gdshader")
	var q := Settings.quality()
	var grass_mat := ShaderMaterial.new()
	grass_mat.shader = load("res://shaders/grass.gdshader")
	var far_mat := grass_mat.duplicate()
	far_mat.set_shader_parameter("sway", 0.8)
	var near_grid: int = q.grass_near
	var far_grid: int = q.grass_far
	var near_r := 36.0
	var far_r := 95.0
	_add_layer("GrassNear", _blade_clump(11, 0.2, 4, Vector2(0.03, 0.055), Vector2(0.5, 1.0)), grass_mat,
			near_grid, near_r * 2.0 / near_grid, 0, 0.0, near_r, {"height_scale": 0.62, "min_scale": 0.6, "max_scale": 1.3})
	_add_layer("GrassFar", _blade_clump(18, 0.6, 2, Vector2(0.05, 0.085), Vector2(0.5, 1.0)), far_mat,
			far_grid, far_r * 2.0 / far_grid, 1, near_r * 0.92, far_r, {"height_scale": 0.62, "min_scale": 0.75, "max_scale": 1.3, "density": 0.85})
	var pampas_mat := ShaderMaterial.new()
	pampas_mat.shader = load("res://shaders/grass_alpha.gdshader")
	pampas_mat.set_shader_parameter("card_tex", load("res://assets/textures/vegetation/pampas_plume.png"))
	pampas_mat.set_shader_parameter("sway", 1.35)
	pampas_mat.set_shader_parameter("stiffness", 1.2)
	pampas_mat.set_shader_parameter("backlight", 1.1)
	pampas_mat.set_shader_parameter("tex_tint", 0.9)
	var pg: int = q.pampas
	var pr := 70.0
	_add_layer("Pampas", _pampas_mesh(), pampas_mat, pg, pr * 2.0 / pg, 2, 0.0, pr,
			{"height_scale": 2.05, "min_scale": 0.75, "max_scale": 1.25, "density": 1.0})
	var flower_mat := ShaderMaterial.new()
	flower_mat.shader = load("res://shaders/grass.gdshader")
	flower_mat.set_shader_parameter("use_vertex_color", 1.0)
	flower_mat.set_shader_parameter("sway", 0.7)
	flower_mat.set_shader_parameter("backlight", 0.9)
	var fg: int = q.flowers
	var fr := 55.0
	_add_layer("Flowers", _spider_lily_mesh(), flower_mat, fg, fr * 2.0 / fg, 3, 0.0, fr,
			{"height_scale": 0.62, "min_scale": 0.75, "max_scale": 1.2, "density": 1.0})


func _add_layer(n: String, mesh: Mesh, mat: Material, grid: int, spacing: float, layer: int,
		inner: float, outer: float, params: Dictionary) -> void:
	var p := GPUParticles3D.new()
	p.name = n
	p.amount = grid * grid
	p.lifetime = 3600.0
	p.explosiveness = 1.0
	p.fixed_fps = 0
	p.interpolate = false
	p.fract_delta = false
	p.local_coords = false
	p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	p.draw_pass_1 = mesh
	p.material_override = mat
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var m := outer + 10.0
	p.visibility_aabb = AABB(Vector3(-m, -250.0, -m), Vector3(m * 2.0, 500.0, m * 2.0))
	var pm := ShaderMaterial.new()
	pm.shader = _process_shader
	pm.set_shader_parameter("grid", grid)
	pm.set_shader_parameter("spacing", spacing)
	pm.set_shader_parameter("layer", layer)
	pm.set_shader_parameter("inner_radius", inner)
	pm.set_shader_parameter("outer_radius", outer)
	for k in params:
		pm.set_shader_parameter(k, params[k])
	p.process_material = pm
	add_child(p)
	layers.append(p)


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var c := cam.global_position
	for p in layers:
		p.global_position = Vector3(c.x, 0.0, c.z)
		(p.process_material as ShaderMaterial).set_shader_parameter("center", c)


# ----------------------------------------------------------------- meshes

## A clump of curved, tapered blades. UV.y = height fraction.
func _blade_clump(blades: int, radius: float, segs: int, width: Vector2, height: Vector2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in blades:
		var ang := _rng.randf() * TAU
		var rr := sqrt(_rng.randf()) * radius
		var base := Vector3(cos(ang) * rr, 0.0, sin(ang) * rr)
		var face := _rng.randf() * TAU
		var right := Vector3(cos(face), 0.0, sin(face))
		var lean_dir := Vector3(-right.z, 0.0, right.x)
		if lean_dir.dot(base) < 0.0:
			lean_dir = -lean_dir
		var h := _rng.randf_range(height.x, height.y)
		var w := _rng.randf_range(width.x, width.y)
		var lean := _rng.randf_range(0.1, 0.45)
		var shade := _rng.randf_range(0.85, 1.0)
		_blade(st, base, right, lean_dir, h, w, lean, segs, Color(shade, shade, shade, 0.0))
	st.generate_tangents()
	return st.commit()


func _blade(st: SurfaceTool, base: Vector3, right: Vector3, lean_dir: Vector3, h: float, w: float,
		lean: float, segs: int, col: Color, uv2_rect := Rect2()) -> void:
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	var prev_t := 0.0
	for s in segs + 1:
		var t := float(s) / segs
		var c := base + Vector3.UP * h * t + lean_dir * lean * h * t * t
		var hw := w * pow(1.0 - t, 0.75) * 0.5 + 0.0015
		var l := c - right * hw
		var r := c + right * hw
		if s > 0:
			var tangent := (c - (base + Vector3.UP * h * prev_t + lean_dir * lean * h * prev_t * prev_t)).normalized()
			var n := right.cross(tangent).normalized()
			_quad(st, prev_l, prev_r, l, r, n, prev_t, t, col)
		prev_l = l
		prev_r = r
		prev_t = t


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, t0: float, t1: float, col: Color) -> void:
	# a,b bottom (left,right) ; c,d top (left,right)
	st.set_color(col)
	st.set_uv2(Vector2.ZERO)
	st.set_normal(n)
	st.set_uv(Vector2(0.0, t0))
	st.add_vertex(a)
	st.set_uv(Vector2(0.0, t1))
	st.add_vertex(c)
	st.set_uv(Vector2(1.0, t0))
	st.add_vertex(b)
	st.set_uv(Vector2(1.0, t0))
	st.add_vertex(b)
	st.set_uv(Vector2(0.0, t1))
	st.add_vertex(c)
	st.set_uv(Vector2(1.0, t1))
	st.add_vertex(d)


## Susuki pampas: arching leaves, a few stems and crossed feathery plume cards.
func _pampas_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# arching leaves (height fraction mapped to 0..0.55 of the plant)
	for i in 9:
		var ang := _rng.randf() * TAU
		var right := Vector3(cos(ang), 0.0, sin(ang))
		var lean_dir := Vector3(-right.z, 0.0, right.x)
		_blade(st, Vector3(_rng.randf_range(-0.05, 0.05), 0, _rng.randf_range(-0.05, 0.05)), right, lean_dir,
				_rng.randf_range(0.35, 0.6), 0.035, _rng.randf_range(0.5, 0.9), 4, Color(0.8, 0.8, 0.8, 0.0))
	# stems with plumes
	var stems := 4
	for s in stems:
		var ang := TAU * s / stems + _rng.randf_range(-0.4, 0.4)
		var lean_dir := Vector3(cos(ang), 0.0, sin(ang))
		var right := Vector3(-lean_dir.z, 0.0, lean_dir.x)
		var h := _rng.randf_range(0.8, 1.0)
		var lean := _rng.randf_range(0.08, 0.22)
		_blade(st, Vector3.ZERO, right, lean_dir, h * 0.78, 0.012, lean, 4, Color(0.9, 0.9, 0.9, 0.0))
		var top := Vector3.UP * h * 0.78 + lean_dir * lean * h * 0.78
		# two crossed plume cards hanging from the stem top
		for k in 2:
			var card_right := right.rotated(Vector3.UP, k * PI * 0.5)
			var bottom := top - Vector3.UP * 0.06
			var ptop := top + Vector3.UP * h * 0.42 + lean_dir * 0.12
			var half := 0.11
			var a := bottom - card_right * half
			var b := bottom + card_right * half
			var c := ptop - card_right * half
			var d := ptop + card_right * half
			var n := card_right.cross(Vector3.UP).normalized()
			var col := Color(1, 1, 1, 1.0)
			st.set_color(col)
			st.set_normal(n)
			st.set_uv(Vector2(0.0, 0.8))
			st.set_uv2(Vector2(0.0, 1.0))
			st.add_vertex(a)
			st.set_uv(Vector2(0.0, 1.0))
			st.set_uv2(Vector2(0.0, 0.0))
			st.add_vertex(c)
			st.set_uv(Vector2(1.0, 0.8))
			st.set_uv2(Vector2(1.0, 1.0))
			st.add_vertex(b)
			st.set_uv(Vector2(1.0, 0.8))
			st.set_uv2(Vector2(1.0, 1.0))
			st.add_vertex(b)
			st.set_uv(Vector2(0.0, 1.0))
			st.set_uv2(Vector2(0.0, 0.0))
			st.add_vertex(c)
			st.set_uv(Vector2(1.0, 1.0))
			st.set_uv2(Vector2(1.0, 0.0))
			st.add_vertex(d)
	st.generate_tangents()
	return st.commit()


## Higanbana (red spider lily): bare stem, recurved petals and long stamens.
func _spider_lily_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stem_col := Color(0.25, 0.42, 0.12)
	var petal_col := Color(0.86, 0.05, 0.04)
	var heads := 3
	for hidx in heads:
		var off := Vector3(_rng.randf_range(-0.12, 0.12), 0, _rng.randf_range(-0.12, 0.12))
		var h := _rng.randf_range(0.7, 1.0)
		var sa := _rng.randf() * TAU
		var sright := Vector3(cos(sa), 0, sin(sa))
		_blade(st, off, sright, Vector3(-sright.z, 0, sright.x), h, 0.014, 0.05, 3, stem_col)
		_blade(st, off, sright.rotated(Vector3.UP, PI * 0.5), Vector3(sright.x, 0, sright.z), h, 0.014, 0.05, 3, stem_col)
		var top := off + Vector3.UP * h
		for p in 6:
			var a := TAU * p / 6 + _rng.randf_range(-0.2, 0.2)
			var out := Vector3(cos(a), 0, sin(a))
			var right := Vector3(-out.z, 0, out.x)
			# recurved petal: goes out, then curls up
			var prev_l := top
			var prev_r := top
			for k in 5:
				var t := float(k + 1) / 5.0
				var c := top + out * 0.1 * t + Vector3.UP * (0.02 * t - 0.05 * t * t + 0.07 * t * t * t)
				var hw := 0.012 * sin(t * PI) + 0.002
				var l := c - right * hw
				var r := c + right * hw
				_quad(st, prev_l, prev_r, l, r, Vector3.UP, 0.8 + 0.2 * (k / 5.0), 0.8 + 0.2 * t, petal_col)
				prev_l = l
				prev_r = r
			# stamens
			var sa2 := a + 0.5
			var so := Vector3(cos(sa2), 0, sin(sa2))
			var sr := Vector3(-so.z, 0, so.x)
			var p0 := top
			for k in 4:
				var t := float(k + 1) / 4.0
				var c := top + so * 0.16 * t + Vector3.UP * (0.1 * t - 0.03 * t * t)
				_quad(st, p0 - sr * 0.002, p0 + sr * 0.002, c - sr * 0.002, c + sr * 0.002, Vector3.UP, 0.9, 1.0, petal_col * 1.05)
				p0 = c
	st.generate_tangents()
	return st.commit()
