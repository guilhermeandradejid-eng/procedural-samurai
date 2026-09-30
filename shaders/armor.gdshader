shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

// Lacquered lamellar armour: glossy plates, coloured silk lacing (odoshi),
// metal rivets, worn edges; plus blood and hit flash.

#include "res://shaders/include/character_common.gdshaderinc"

uniform vec3 plate_color : source_color = vec3(0.07, 0.08, 0.1);
uniform vec3 lacing_color : source_color = vec3(0.12, 0.22, 0.52);
uniform vec3 trim_color : source_color = vec3(0.75, 0.58, 0.25);
uniform sampler2D armor_mask : filter_linear_mipmap, repeat_enable;
uniform float mask_scale = 5.0;
uniform float lacing = 1.0;
uniform float metallic_plate = 0.0;
uniform float wear = 0.35;

void vertex() {
	v_local = VERTEX;
	v_local_n = NORMAL;
}

void fragment() {
	if (slice_clipped(v_local)) {
		discard;
	}
	vec3 n = normalize(v_local_n);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = v_local * mask_scale;
	vec4 m = texture(armor_mask, p.zy) * w.x + texture(armor_mask, vec2(p.x, p.z)) * w.y + texture(armor_mask, p.xy) * w.z;
	float lace = m.g * lacing;
	vec3 c = plate_color * (0.55 + 0.6 * m.r);
	c = mix(c, lacing_color * (0.7 + 0.3 * m.a), lace);
	c = mix(c, trim_color, m.b * 0.9);
	// worn edges catch the light
	float edge = smoothstep(0.62, 0.95, noise3(v_local * 25.0)) * wear;
	c = mix(c, c * 1.8 + vec3(0.04), edge * (1.0 - lace));
	float r = mix(0.22, 0.75, lace);
	r = mix(r, 0.35, m.b);
	vec3 e = vec3(0.0);
	apply_character_fx(c, r, e);
	slice_interior(FRONT_FACING, c, r, e);
	ALBEDO = c;
	ROUGHNESS = r;
	METALLIC = max(m.b * 0.9, metallic_plate * (1.0 - lace));
	SPECULAR = 0.6;
	EMISSION = e;
	if (!FRONT_FACING && dot(slice_plane.xyz, slice_plane.xyz) > 0.01) {
		METALLIC = 0.0;
	}
}
