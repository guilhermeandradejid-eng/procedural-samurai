class_name SlashTrail
extends MeshInstance3D
## Sword swing ribbon: records the blade base/tip every frame while active
## and draws a fading, tapering strip (additive, HDR so bloom catches it).

var samples: Array = []       # [base, tip, age]
var active := false
var lifetime := 0.14
var color := Color(1.0, 0.97, 0.9, 0.9)
var _im := ImmediateMesh.new()
var _mat: ShaderMaterial


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/slash_trail.gdshader")
	_mat.set_shader_parameter("trail_tex", load("res://assets/textures/fx/slash_trail.png"))
	material_override = _mat
	extra_cull_margin = 16384.0


func set_color(c: Color) -> void:
	color = c
	if _mat:
		_mat.set_shader_parameter("tint", c)


func push(base: Vector3, tip: Vector3) -> void:
	samples.push_front([base, tip, 0.0])
	if samples.size() > 24:
		samples.pop_back()


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	for smp in samples:
		smp[2] += real * (0.35 if active else 1.0)
	while not samples.is_empty() and samples[samples.size() - 1][2] > lifetime:
		samples.pop_back()
	_im.clear_surfaces()
	if samples.size() < 2:
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := samples.size()
	for i in n:
		var smp: Array = samples[i]
		var k := 1.0 - float(i) / float(n - 1)
		var age_k := 1.0 - clampf(smp[2] / lifetime, 0.0, 1.0)
		var a := k * age_k
		var base: Vector3 = smp[0]
		var tip: Vector3 = smp[1]
		var mid := base.lerp(tip, 0.25 + 0.5 * (1.0 - k))
		_im.surface_set_color(Color(color.r, color.g, color.b, a * color.a))
		_im.surface_set_uv(Vector2(k, 0.0))
		_im.surface_add_vertex(mid)
		_im.surface_set_color(Color(color.r, color.g, color.b, a * color.a))
		_im.surface_set_uv(Vector2(k, 1.0))
		_im.surface_add_vertex(tip)
	_im.surface_end()
