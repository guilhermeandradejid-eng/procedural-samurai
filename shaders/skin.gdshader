shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Soft doll-like skin (Human Fall Flat look): warm diffuse, subsurface
// scattering, broad rim light, plus blood and hit flash.

#include "res://shaders/include/character_common.gdshaderinc"

uniform vec3 color : source_color = vec3(0.94, 0.84, 0.74);
uniform float roughness = 0.6;
uniform float rim = 0.3;
uniform float sss = 0.3;
uniform float glossy = 0.0;

void vertex() {
	v_local = VERTEX;
	v_local_n = NORMAL;
}

void fragment() {
	vec3 c = color;
	// subtle blotchiness so large parts do not look like plastic
	c *= 0.96 + 0.06 * noise3(v_local * 12.0);
	float r = mix(roughness, 0.18, glossy);
	vec3 e = vec3(0.0);
	apply_character_fx(c, r, e);
	ALBEDO = c;
	ROUGHNESS = r;
	SPECULAR = mix(0.35, 0.7, glossy);
	RIM = rim;
	RIM_TINT = 0.5;
	SSS_STRENGTH = sss;
	EMISSION = e;
}
