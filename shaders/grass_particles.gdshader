shader_type particles;
render_mode disable_velocity, disable_force;

// Places vegetation instances on a world-aligned grid that follows the camera.
// Every frame each particle recomputes its cell, samples the world maps and
// decides visibility/scale, so nothing needs to be streamed from the CPU.

#include "res://shaders/include/terrain_common.gdshaderinc"

uniform vec3 center = vec3(0.0);
uniform float spacing = 0.45;
uniform int grid = 200;
uniform int layer = 0;          // 0 grass near, 1 grass far, 2 pampas, 3 flowers, 4 ferns
uniform float inner_radius = 0.0;
uniform float outer_radius = 45.0;
uniform float density = 1.0;
uniform float height_scale = 1.0;
uniform float min_scale = 0.7;
uniform float max_scale = 1.25;

float layer_density(vec4 sp, vec4 veg, vec3 n, float h, vec2 rnd) {
	float slope = 1.0 - n.y;
	float ok = (1.0 - smoothstep(0.24, 0.34, slope)) * smoothstep(1.6, 3.2, h) * (1.0 - smoothstep(205.0, 240.0, h));
	float road = sp.b;
	if (layer <= 1) {
		return (sp.r * 1.0 + sp.g * 0.8 + sp.a * 0.28) * (1.0 - road * 0.95) * ok;
	} else if (layer == 2) {
		return smoothstep(0.25, 0.75, sp.g) * (1.0 - road) * ok * (1.0 - smoothstep(0.2, 0.28, slope));
	} else if (layer == 3) {
		return veg.b * (1.0 - road) * ok * (1.0 - sp.a * 0.6);
	}
	// ferns / bushes in forests
	return sp.a * (1.0 - road) * ok * 0.9;
}

void process() {
	int gi = int(INDEX);
	int ix = gi % grid;
	int iz = gi / grid;
	vec2 base_cell = floor(center.xz / spacing) - vec2(float(grid / 2));
	vec2 cell = base_cell + vec2(float(ix), float(iz));
	vec2 rnd = hash22(cell * 1.371 + vec2(float(layer) * 17.13, 3.7));
	vec2 rnd2 = hash22(cell * 0.713 + vec2(5.1, float(layer) * 9.7));
	vec2 pos = (cell + rnd) * spacing;
	float h = terrain_height_at(pos);
	vec3 n = terrain_normal_at(pos);
	vec4 sp = terrain_splat_at(pos);
	vec4 veg = terrain_veg_at(pos);
	float dens = layer_density(sp, veg, n, h, rnd) * density;
	float d = length(pos - center.xz);
	float fade = 1.0 - smoothstep(outer_radius * 0.82, outer_radius, d);
	if (inner_radius > 0.0) {
		fade *= smoothstep(inner_radius * 0.8, inner_radius, d);
	}
	// clustering noise so fields have natural clumps and clearings
	float clump = value_noise(pos * 0.23 + float(layer) * 3.1);
	if (layer == 3) {
		clump = smoothstep(0.35, 0.75, value_noise(pos * 0.12 + 7.0));
	}
	float keep = step(rnd2.x, dens * mix(0.55, 1.25, clump));
	float tall = veg.a;
	float s = mix(min_scale, max_scale, rnd2.y) * height_scale * mix(0.55, 1.15, tall) * mix(0.8, 1.15, clump);
	if (layer == 2) {
		s = mix(min_scale, max_scale, rnd2.y) * height_scale * mix(0.8, 1.1, tall);
	}
	s *= keep * fade;
	// wide rotation, slight lean downhill
	float ang = rnd.x * 6.2831;
	float ca = cos(ang);
	float sa = sin(ang);
	vec3 up = normalize(mix(vec3(0.0, 1.0, 0.0), n, 0.35));
	vec3 right = normalize(cross(up, vec3(sa, 0.0, ca)));
	vec3 fwd = cross(right, up);
	float sxz = s * mix(0.85, 1.2, rnd.y);
	TRANSFORM = mat4(vec4(right * sxz, 0.0), vec4(up * s, 0.0), vec4(fwd * sxz, 0.0), vec4(pos.x, h - 0.03, pos.y, 1.0));
	// custom: random, pampas share (colour), clump value, meadow share
	float gold = sp.g / max(sp.r + sp.g + sp.a * 0.5, 0.001);
	CUSTOM = vec4(rnd2.y, clamp(gold, 0.0, 1.0), clump, sp.a);
	COLOR = vec4(1.0);
	VELOCITY = vec3(0.0);
}
