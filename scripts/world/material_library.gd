class_name MaterialLibrary
extends RefCounted
## Maps the material slot names exported from Blender (glTF material names)
## to the game's materials: triplanar textured architecture, foliage and
## rock shaders, and default character palettes.

const TEX := "res://assets/textures/"

static var _cache := {}


static func _tex(path: String) -> Texture2D:
	return load(TEX + path) as Texture2D


static func _triplanar(albedo: String, normal: String, scale := 0.5, rough := 0.8, tint := Color.WHITE, cull := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(albedo)
	m.albedo_color = tint
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = _tex(normal)
		m.normal_scale = 0.8
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not cull:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _flat(color: Color, rough := 0.7, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m


static func _uv(albedo: String, normal: String, rough := 0.8, cull := true, uv_scale := Vector3.ONE) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(albedo)
	if normal != "":
		m.normal_enabled = true
		m.normal_texture = _tex(normal)
	m.roughness = rough
	m.uv1_scale = uv_scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if not cull:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _foliage(card: String, tint := Color.WHITE, translucency := 0.85) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(card))
	m.set_shader_parameter("is_leaf", true)
	m.set_shader_parameter("tint", tint)
	m.set_shader_parameter("translucency", translucency)
	return m


static func _bark(albedo: String, normal: String, uv_v := 0.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/foliage.gdshader")
	m.set_shader_parameter("albedo_tex", _tex(albedo))
	m.set_shader_parameter("normal_tex", _tex(normal))
	m.set_shader_parameter("use_normal_map", true)
	m.set_shader_parameter("is_leaf", false)
	m.set_shader_parameter("tint_variation", 0.08)
	m.set_shader_parameter("uv_scale_v", uv_v)
	return m


static func make(name: String) -> Material:
	match name:
		# ------------------------------------------------------ architecture
		"wood_dark":
			return _triplanar("materials/wood_dark.jpg", "materials/wood_dark_n.png", 0.45, 0.75)
		"wood_light":
			return _triplanar("materials/wood_light.jpg", "materials/wood_light_n.png", 0.45, 0.8)
		"wood_raw":
			return _triplanar("materials/wood_light.jpg", "materials/wood_light_n.png", 0.6, 0.85, Color(0.78, 0.72, 0.64))
		"vermilion":
			return _triplanar("materials/vermilion.jpg", "materials/vermilion_n.png", 0.4, 0.55)
		"black_paint":
			return _flat(Color(0.045, 0.04, 0.04), 0.45)
		"roof_tiles":
			return _triplanar("materials/roof_tiles.jpg", "materials/roof_tiles_n.png", 0.4, 0.6)
		"roof_copper":
			return _triplanar("materials/roof_tiles.jpg", "materials/roof_tiles_n.png", 0.8, 0.55, Color(0.45, 0.85, 0.72))
		"thatch":
			return _triplanar("materials/thatch.jpg", "materials/thatch_n.png", 0.35, 0.95)
		"plaster":
			return _triplanar("materials/plaster.jpg", "materials/plaster_n.png", 0.3, 0.9)
		"shoji":
			return _triplanar("materials/shoji.jpg", "materials/shoji_n.png", 0.5, 0.9)
		"stone":
			return _triplanar("materials/stone.jpg", "materials/stone_n.png", 0.4, 0.85)
		"canvas":
			return _triplanar("materials/canvas.jpg", "materials/canvas_n.png", 0.35, 0.95, Color.WHITE, false)
		"rope":
			return _uv("materials/rope.jpg", "materials/rope_n.png", 0.9)
		"bronze":
			return _flat(Color(0.55, 0.4, 0.22), 0.4, 0.85)
		"bamboo_pole":
			return _uv("vegetation/bark_bamboo.jpg", "vegetation/bark_bamboo_n.png", 0.6)
		"curtain_0":
			return _uv("materials/banner_0.jpg", "", 0.9, false)
		"curtain_1":
			return _uv("materials/banner_3.jpg", "", 0.9, false)
		"banner":
			return _uv("materials/banner_1.jpg", "", 0.9, false)
		"paper_lantern":
			var m := _flat(Color(0.95, 0.85, 0.7), 0.9)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.62, 0.3)
			m.emission_energy_multiplier = 1.6
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"collision":
			return _flat(Color(1, 0, 1))
		"wood_charred":
			var wc := _flat(Color(0.05, 0.04, 0.035), 0.95)
			wc.emission_enabled = true
			wc.emission = Color(0.9, 0.28, 0.06)
			wc.emission_energy_multiplier = 0.35
			return wc
		"ash":
			return _flat(Color(0.3, 0.29, 0.28), 1.0)
		"paper":
			var pp := _flat(Color(0.95, 0.94, 0.9), 0.9)
			pp.cull_mode = BaseMaterial3D.CULL_DISABLED
			return pp
		"ceramic":
			return _flat(Color(0.35, 0.2, 0.1), 0.25)
		"flag_0", "flag_1":
			var fl := ShaderMaterial.new()
			fl.shader = load("res://shaders/flag.gdshader")
			fl.set_shader_parameter("albedo_tex", _tex("materials/banner_%d.jpg" % (0 if name == "flag_0" else 1)))
			return fl
		# ------------------------------------------------------------- nature
		"rock":
			var r := ShaderMaterial.new()
			r.shader = load("res://shaders/rock.gdshader")
			r.set_shader_parameter("albedo_array", load(TEX + "terrain/terrain_albedo.jpg"))
			r.set_shader_parameter("nrh_array", load(TEX + "terrain/terrain_nrh.png"))
			return r
		"bark_dark":
			return _bark("vegetation/bark_dark.jpg", "vegetation/bark_dark_n.png")
		"bark_pine":
			return _bark("vegetation/bark_pine.jpg", "vegetation/bark_pine_n.png")
		"bark_birch":
			return _bark("vegetation/bark_birch.jpg", "vegetation/bark_birch_n.png")
		"bamboo":
			return _bark("vegetation/bark_bamboo.jpg", "vegetation/bark_bamboo_n.png", 1.0)
		"leaves_maple":
			return _foliage("vegetation/foliage_maple.png", Color(1.05, 1.0, 1.0), 1.0)
		"leaves_ginkgo":
			return _foliage("vegetation/foliage_ginkgo.png", Color(1.0, 1.0, 0.95), 1.0)
		"leaves_pine":
			return _foliage("vegetation/foliage_pine.png", Color(0.95, 1.0, 0.95), 0.5)
		"leaves_birch":
			return _foliage("vegetation/foliage_birch.png", Color(1.0, 1.0, 1.0), 0.9)
		"leaves_bamboo":
			return _foliage("vegetation/foliage_bamboo.png", Color(1.0, 1.0, 1.0), 0.8)
		"leaves_sakura":
			return _foliage("vegetation/foliage_sakura.png", Color(1.0, 1.0, 1.0), 0.9)
		# ---------------------------------------------------------- characters
		"skin":
			return CharacterStyle.skin_material(Color(0.94, 0.84, 0.74))
		"cloth_top":
			return CharacterStyle.cloth_material(Color(0.82, 0.8, 0.74), Color(0.7, 0.68, 0.62), 0)
		"cloth_bottom":
			return CharacterStyle.cloth_material(Color(0.14, 0.15, 0.22), Color(0.22, 0.24, 0.34), 3)
		"cloth_accent":
			return CharacterStyle.cloth_material(Color(0.9, 0.88, 0.82), Color(0.9, 0.88, 0.82), 0)
		"feet":
			return CharacterStyle.cloth_material(Color(0.86, 0.84, 0.8), Color(0.86, 0.84, 0.8), 0)
		"armor_plate":
			return CharacterStyle.armor_material(Color(0.07, 0.08, 0.1), Color(0.12, 0.22, 0.52))
		"armor_trim", "gold":
			return _flat(Color(0.8, 0.6, 0.26), 0.3, 0.95)
		"metal_dark":
			return _flat(Color(0.12, 0.12, 0.13), 0.4, 0.8)
		"leather":
			return _flat(Color(0.2, 0.12, 0.07), 0.7)
		"straw":
			var s := _uv("materials/straw_weave.jpg", "materials/straw_weave_n.png", 0.85, false, Vector3(3.0, 3.0, 1.0))
			return s
		"cord":
			return _flat(Color(0.35, 0.08, 0.06), 0.8)
		"eyes":
			return _flat(Color(0.02, 0.02, 0.025), 0.15)
		"hair":
			return _flat(Color(0.04, 0.035, 0.03), 0.55)
		"mask":
			return _flat(Color(0.55, 0.06, 0.05), 0.35)
		"teeth":
			return _flat(Color(0.92, 0.88, 0.78), 0.4)
		# ------------------------------------------------------------ weapons
		"blade":
			var b := ShaderMaterial.new()
			b.shader = load("res://shaders/blade.gdshader")
			return b
		"tsuka_wrap":
			var t := _flat(Color(0.06, 0.05, 0.05), 0.8)
			return t
		"tsuba":
			return _flat(Color(0.1, 0.09, 0.09), 0.45, 0.8)
		"habaki":
			return _flat(Color(0.82, 0.62, 0.28), 0.25, 1.0)
		"saya":
			var sy := _flat(Color(0.03, 0.025, 0.025), 0.12)
			sy.clearcoat_enabled = true
			sy.clearcoat = 0.8
			return sy
	return null


static func get_material(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m := make(name)
	_cache[name] = m
	return m


## Replaces imported glTF materials under `root` with library materials.
## `overrides` maps slot name -> Material (per-character palettes).
static func apply(root: Node, overrides := {}) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh:
				for i in mi.mesh.get_surface_count():
					var src := mi.mesh.surface_get_material(i)
					if src == null:
						continue
					var slot := src.resource_name
					var m: Material = overrides.get(slot, null)
					if m == null:
						m = get_material(slot)
					if m != null:
						mi.set_surface_override_material(i, m)
		for c in n.get_children():
			stack.push_back(c)


## Returns a mesh with library materials baked into its surfaces (for
## MultiMesh use where per-instance overrides are not possible).
static func baked_mesh(mesh: Mesh) -> Mesh:
	var copy := mesh.duplicate() as Mesh
	for i in copy.get_surface_count():
		var src := copy.surface_get_material(i)
		if src == null:
			continue
		var m := get_material(src.resource_name)
		if m != null:
			copy.surface_set_material(i, m)
	return copy
