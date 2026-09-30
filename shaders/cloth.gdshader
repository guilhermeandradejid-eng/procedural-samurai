shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Kimono / hakama cloth with procedural Japanese patterns (seigaiha waves,
// asanoha, stripes) projected in the part's local space, fabric sheen,
// blood and hit flash.

#include "res://shaders/include/character_common.gdshaderinc"

uniform vec3 base_color : source_color = vec3(0.16, 0.18, 0.28);
uniform vec3 pattern_color : source_color = vec3(0.3, 0.33, 0.48);
uniform int pattern = 0;  // 0 plain, 1 seigaiha, 2 asanoha, 3 stripes
uniform float pattern_scale = 3.2;
uniform float pattern_strength = 0.8;
uniform sampler2D cloth_mask : filter_linear_mipmap, repeat_enable;
uniform float sheen = 0.25;

void vertex() {
	v_local = VERTEX;
	v_local_n = NORMAL;
}

float pat(vec2 uv) {
	vec4 m = texture(cloth_mask, uv);
	if (pattern == 1) {
		return m.r;
	} else if (pattern == 2) {
		return m.g;
	} else if (pattern == 3) {
		return m.b;
	}
	return 0.0;
}

void fragment() {
	if (slice_clipped(v_local)) {
		discard;
	}
	vec3 n = normalize(v_local_n);
	vec3 w = pow(abs(n), vec3(3.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_local * pattern_scale;
	float m = pat(p.zy) * w.x + pat(p.xz) * w.y + pat(p.xy) * w.z;
	float weave = texture(cloth_mask, p.xy * 6.0).a * w.z + texture(cloth_mask, p.zy * 6.0).a * w.x + texture(cloth_mask, p.xz * 6.0).a * w.y;
	vec3 c = mix(base_color, pattern_color, m * pattern_strength);
	c *= 0.9 + 0.12 * weave;
	float r = 0.82;
	vec3 e = vec3(0.0);
	apply_character_fx(c, r, e);
	slice_interior(FRONT_FACING, c, r, e);
	ALBEDO = c;
	ROUGHNESS = r;
	SPECULAR = 0.25;
	RIM = sheen;
	RIM_TINT = 0.7;
	EMISSION = e;
}
