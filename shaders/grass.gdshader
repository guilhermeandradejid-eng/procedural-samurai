shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// Geometry grass blades / flowers (no alpha), instanced by GPU particles.

#include "res://shaders/include/grass_common.gdshaderinc"

void vertex() {
	float gh;
	vec3 gb;
	vec3 gt;
	grass_vertex(VERTEX, NORMAL, UV, COLOR, INSTANCE_CUSTOM, MODEL_MATRIX, TIME, gh, gb, gt);
	v_h = gh;
	v_base = gb;
	v_tip = gt;
}

void fragment() {
	vec3 col = grass_color(v_h, v_base, v_tip);
	ALBEDO = col;
	ROUGHNESS = mix(0.62, 0.3, wetness);
	SPECULAR = 0.28;
	BACKLIGHT = col * backlight;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}
