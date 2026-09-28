shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// Alpha-tested vegetation cards (pampas plumes, ferns), instanced by particles.

#include "res://shaders/include/grass_common.gdshaderinc"

uniform sampler2D card_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float alpha_cut = 0.42;
uniform float tex_tint = 1.0;

varying float v_tex;

void vertex() {
	v_tex = COLOR.a;
	float gh;
	vec3 gb;
	vec3 gt;
	grass_vertex(VERTEX, NORMAL, UV, vec4(COLOR.rgb, 1.0), INSTANCE_CUSTOM, MODEL_MATRIX, TIME, gh, gb, gt);
	v_h = gh;
	v_base = gb;
	v_tip = gt;
}

void fragment() {
	vec3 col = grass_color(v_h, v_base, v_tip);
	if (v_tex > 0.5) {
		vec4 tx = texture(card_tex, UV2);
		col = mix(col, tx.rgb * mix(vec3(1.0), v_tip * 1.6, 0.35), tex_tint);
		ALPHA = tx.a;
	} else {
		ALPHA = 1.0;
	}
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ALBEDO = col;
	ROUGHNESS = 0.7;
	SPECULAR = 0.2;
	BACKLIGHT = col * backlight;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
