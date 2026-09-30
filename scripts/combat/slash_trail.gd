class_name SlashTrail
extends MeshInstance3D
## Sword swing ribbon: records the blade base/tip every frame while active
## and draws a fading, tapering strip (additive, HDR so bloom catches it).

var samples: Array = []       # [base, tip, age]
var active := false
var lifetime := 0.24
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
	if samples.size() > 20:
		samples.pop_back()


static func _cr(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _process(delta: float) -> void:
	var real := delta / maxf(Engine.time_scale, 0.05)
	for smp in samples:
		smp[2] += real * (0.3 if active else 1.0)
	while not samples.is_empty() and samples[samples.size() - 1][2] > lifetime:
		samples.pop_back()
	_im.clear_surfaces()
	if samples.size() < 3:
		return
	# Catmull-Rom subdivision so fast swings stay smooth arcs instead of polylines
	var pts: Array = []   # [base, tip, k, age]
	var n := samples.size()
	for i in range(n - 1):
		var a: Array = samples[maxi(i - 1, 0)]
		var b: Array = samples[i]
		var c: Array = samples[i + 1]
		var d2: Array = samples[mini(i + 2, n - 1)]
		for sub_i in 3:
			var u := float(sub_i) / 3.0
			pts.append([_cr(a[0], b[0], c[0], d2[0], u), _cr(a[1], b[1], c[1], d2[1], u),
				(float(i) + u) / float(n - 1), lerpf(b[2], c[2], u)])
	var last: Array = samples[n - 1]
	pts.append([last[0], last[1], 1.0, last[2]])
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in pts:
		var k := 1.0 - float(p[2])
		var age_k := 1.0 - clampf(float(p[3]) / lifetime, 0.0, 1.0)
		var a := k * k * age_k
		var base: Vector3 = p[0]
		var tip: Vector3 = p[1]
		# the ribbon spans most of the blade, not just the tip
		var inner := base.lerp(tip, 0.18)
		_im.surface_set_color(Color(color.r, color.g, color.b, a * color.a))
		_im.surface_set_uv(Vector2(k, 0.0))
		_im.surface_add_vertex(inner)
		_im.surface_set_color(Color(color.r, color.g, color.b, a * color.a))
		_im.surface_set_uv(Vector2(k, 1.0))
		_im.surface_add_vertex(tip)
	_im.surface_end()
