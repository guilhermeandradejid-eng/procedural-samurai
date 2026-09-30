shader_type fog;

// Ground-hugging valley mist: thickest at the terrain surface, thinning
// with height above it, denser over low ground and water, torn into wisps by
// 3D noise that drifts with the wind.

uniform sampler3D noise_tex : repeat_enable, filter_linear;
uniform float amount = 0.3;
uniform vec3 drift = vec3(0.0);
uniform float thickness = 5.0;

global uniform sampler2D terrain_height;
global uniform vec4 terrain_info;
global uniform vec4 fog_color;

void fog() {
	vec3 p = WORLD_POSITION;
	vec2 g = (p.xz / terrain_info.y + (terrain_info.x - 1.0) * 0.5 + 0.5) / terrain_info.x;
	float gh = texture(terrain_height, g).r;
	float h = p.y - gh;
	float layer = exp(-max(h, 0.0) / thickness) * smoothstep(-3.0, 0.5, h);
	// lowlands and shores are mistier than the ridges
	float low = exp(-max(gh - terrain_info.w, 0.0) * 0.012);
	float n1 = texture(noise_tex, p * 0.018 + drift).r;
	float n2 = texture(noise_tex, p * 0.05 + drift * 1.7 + 0.37).r;
	float wisp = smoothstep(0.25, 0.85, n1 * 0.65 + n2 * 0.35);
	DENSITY = amount * layer * (0.25 + 1.3 * wisp) * (0.4 + 0.9 * low);
	ALBEDO = mix(vec3(0.82, 0.86, 0.92), fog_color.rgb * 1.15, 0.5);
	EMISSION = fog_color.rgb * 0.03;
}
