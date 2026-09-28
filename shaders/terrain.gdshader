shader_type spatial;
render_mode world_vertex_coords, cull_back, depth_draw_opaque;

#include "res://shaders/include/terrain_common.gdshaderinc"

varying vec3 v_world;

void vertex() {
	float h = terrain_height_at(VERTEX.xz);
	float chunk = length(MODEL_MATRIX[0].xyz);
	VERTEX.y = h - UV2.x * chunk / 16.0;
	v_world = VERTEX;
	NORMAL = terrain_normal_at(VERTEX.xz);
}

void fragment() {
	vec3 wn = terrain_normal_at(v_world.xz);
	vec4 sp = terrain_splat_at(v_world.xz);
	float slope = 1.0 - wn.y;
	vec3 col = vec3(0.32, 0.36, 0.2);
	col = mix(col, vec3(0.62, 0.5, 0.28), sp.g);
	col = mix(col, vec3(0.42, 0.33, 0.24), sp.b);
	col = mix(col, vec3(0.26, 0.2, 0.15), sp.a * 0.7);
	col = mix(col, vec3(0.35, 0.33, 0.31), smoothstep(0.25, 0.4, slope));
	col = mix(col, vec3(0.9, 0.92, 0.95), smoothstep(255.0, 290.0, v_world.y));
	col = mix(col, vec3(0.76, 0.7, 0.55), smoothstep(3.0, 1.5, v_world.y));
	ALBEDO = col;
	ROUGHNESS = 0.9;
	NORMAL = (VIEW_MATRIX * vec4(wn, 0.0)).xyz;
}
