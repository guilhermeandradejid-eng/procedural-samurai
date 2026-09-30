class_name CharacterStyle
extends RefCounted
## Visual archetypes (palettes, armour pieces, hats, weapons, proportions)
## for the player and every enemy type, plus the material factories used to
## colour the Human-Fall-Flat style body.

const GOLD := Color(0.8, 0.6, 0.26)

## Every archetype: colours per slot, which gear pieces to attach, scale and weapon.
## Gear entries prefixed with "?" are optional (random 50%), entries with "|"
## are alternatives (one is picked).
const STYLES := {
	"player": {
		"skin": Color(0.95, 0.85, 0.75),
		"cloth_top": [Color(0.86, 0.84, 0.78), Color(0.7, 0.68, 0.62), 2],
		"cloth_bottom": [Color(0.08, 0.1, 0.17), Color(0.2, 0.25, 0.4), 1],
		"cloth_accent": [Color(0.62, 0.09, 0.07), Color(0.62, 0.09, 0.07), 0],
		"feet": [Color(0.9, 0.88, 0.84), Color(0.9, 0.88, 0.84), 0],
		"armor": [Color(0.05, 0.06, 0.08), Color(0.13, 0.28, 0.6), GOLD],
		"gear": ["chest__do", "belly__do", "pelvis__kusazuri_0", "pelvis__kusazuri_1", "pelvis__kusazuri_2",
			"pelvis__kusazuri_3", "pelvis__kusazuri_4", "upper_arm_r__sode", "upper_arm_l__sode",
			"forearm_r__kote", "forearm_l__kote", "hand_r__tekko", "hand_l__tekko", "shin_r__suneate",
			"shin_l__suneate", "head__kasa", "head__eye_r", "head__eye_l", "head__lid_r", "head__lid_l", "head__brows_calm", "head__hachimaki"],
		"scale": 1.0,
		"weapon": "katana",
		"hp": 100.0,
	},
	"ronin": {
		"skin": Color(0.93, 0.82, 0.72),
		"cloth_top": [Color(0.42, 0.36, 0.3), Color(0.3, 0.26, 0.22), 3],
		"cloth_bottom": [Color(0.22, 0.14, 0.1), Color(0.3, 0.2, 0.14), 0],
		"cloth_accent": [Color(0.15, 0.13, 0.12), Color(0.15, 0.13, 0.12), 0],
		"feet": [Color(0.55, 0.5, 0.42), Color(0.55, 0.5, 0.42), 0],
		"armor": [Color(0.32, 0.08, 0.06), Color(0.08, 0.07, 0.07), GOLD],
		"gear": ["chest__do", "?belly__do", "?pelvis__kusazuri_0", "?pelvis__kusazuri_1", "forearm_r__kote",
			"head__jingasa|head__topknot|head__kasa", "head__eye_r", "head__eye_l", "head__lid_r", "head__lid_l", "head__brows_angry", "?head__menpo"],
		"scale": 1.0,
		"weapon": "katana",
		"hp": 55.0,
	},
	"brute": {
		"skin": Color(0.9, 0.76, 0.64),
		"cloth_top": [Color(0.2, 0.2, 0.2), Color(0.3, 0.3, 0.3), 2],
		"cloth_bottom": [Color(0.14, 0.12, 0.1), Color(0.2, 0.18, 0.15), 0],
		"cloth_accent": [Color(0.55, 0.12, 0.08), Color(0.55, 0.12, 0.08), 0],
		"feet": [Color(0.4, 0.35, 0.3), Color(0.4, 0.35, 0.3), 0],
		"armor": [Color(0.12, 0.1, 0.09), Color(0.45, 0.1, 0.07), Color(0.3, 0.3, 0.32)],
		"gear": ["chest__do", "belly__do", "upper_arm_r__sode", "upper_arm_l__sode", "shin_r__suneate",
			"shin_l__suneate", "head__topknot", "head__beard", "head__eye_r", "head__eye_l", "head__lid_r", "head__lid_l", "head__brows_angry"],
		"scale": 1.22,
		"weapon": "kanabo",
		"hp": 150.0,
	},
	"leader": {
		"skin": Color(0.93, 0.83, 0.73),
		"cloth_top": [Color(0.12, 0.1, 0.1), Color(0.5, 0.1, 0.08), 1],
		"cloth_bottom": [Color(0.1, 0.08, 0.08), Color(0.35, 0.08, 0.06), 2],
		"cloth_accent": [Color(0.75, 0.6, 0.25), Color(0.75, 0.6, 0.25), 0],
		"feet": [Color(0.15, 0.13, 0.12), Color(0.15, 0.13, 0.12), 0],
		"armor": [Color(0.04, 0.035, 0.035), Color(0.62, 0.08, 0.06), GOLD],
		"gear": ["chest__do", "belly__do", "pelvis__kusazuri_0", "pelvis__kusazuri_1", "pelvis__kusazuri_2",
			"pelvis__kusazuri_3", "pelvis__kusazuri_4", "upper_arm_r__sode", "upper_arm_l__sode",
			"forearm_r__kote", "forearm_l__kote", "thigh_r__haidate", "thigh_l__haidate", "shin_r__suneate",
			"shin_l__suneate", "head__kabuto", "head__menpo", "head__eye_r", "head__eye_l", "head__lid_r", "head__lid_l", "head__brows_angry", "chest__sashimono"],
		"scale": 1.08,
		"weapon": "nodachi",
		"hp": 120.0,
	},
	"spearman": {
		"skin": Color(0.93, 0.82, 0.72),
		"cloth_top": [Color(0.3, 0.32, 0.26), Color(0.22, 0.24, 0.2), 0],
		"cloth_bottom": [Color(0.2, 0.18, 0.14), Color(0.2, 0.18, 0.14), 0],
		"cloth_accent": [Color(0.2, 0.15, 0.1), Color(0.2, 0.15, 0.1), 0],
		"feet": [Color(0.55, 0.5, 0.42), Color(0.55, 0.5, 0.42), 0],
		"armor": [Color(0.2, 0.16, 0.1), Color(0.1, 0.1, 0.1), Color(0.35, 0.35, 0.36)],
		"gear": ["chest__do", "?belly__do", "head__jingasa", "head__eye_r", "head__eye_l", "head__lid_r", "head__lid_l", "head__brows_angry", "?shin_r__suneate", "?shin_l__suneate"],
		"scale": 1.0,
		"weapon": "yari",
		"hp": 60.0,
	},
}


static func skin_material(color: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/skin.gdshader")
	m.set_shader_parameter("color", color)
	return m


static func cloth_material(base: Color, pattern_col: Color, pattern: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/cloth.gdshader")
	m.set_shader_parameter("base_color", base)
	m.set_shader_parameter("pattern_color", pattern_col)
	m.set_shader_parameter("pattern", pattern)
	m.set_shader_parameter("cloth_mask", load("res://assets/textures/materials/cloth_mask.png"))
	return m


static func armor_material(plate: Color, lacing: Color, trim := GOLD) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/armor.gdshader")
	m.set_shader_parameter("plate_color", plate)
	m.set_shader_parameter("lacing_color", lacing)
	m.set_shader_parameter("trim_color", trim)
	m.set_shader_parameter("armor_mask", load("res://assets/textures/materials/armor_mask.png"))
	return m


## Builds the material override table for an archetype (optionally varied).
static func overrides_for(style_name: String, rng: RandomNumberGenerator = null) -> Dictionary:
	var s: Dictionary = STYLES.get(style_name, STYLES["ronin"])
	var vary := func(c: Color) -> Color:
		if rng == null:
			return c
		var k := rng.randf_range(0.85, 1.15)
		return Color(clampf(c.r * k, 0, 1), clampf(c.g * k, 0, 1), clampf(c.b * k, 0, 1))
	var out := {}
	out["skin"] = skin_material(vary.call(s.skin))
	for slot in ["cloth_top", "cloth_bottom", "cloth_accent", "feet"]:
		var d: Array = s[slot]
		out[slot] = cloth_material(vary.call(d[0]), vary.call(d[1]), int(d[2]))
	var a: Array = s.armor
	out["armor_plate"] = armor_material(vary.call(a[0]), a[1], a[2])
	return out


## Resolves the gear list ("?" optional, "|" alternatives).
static func gear_for(style_name: String, rng: RandomNumberGenerator = null) -> Array[String]:
	var s: Dictionary = STYLES.get(style_name, STYLES["ronin"])
	var out: Array[String] = []
	for g in s.gear:
		var entry: String = g
		if entry.begins_with("?"):
			if rng == null or rng.randf() < 0.5:
				continue
			entry = entry.substr(1)
		if entry.contains("|"):
			var opts := entry.split("|")
			entry = opts[rng.randi() % opts.size()] if rng else opts[0]
		out.append(entry)
	return out
