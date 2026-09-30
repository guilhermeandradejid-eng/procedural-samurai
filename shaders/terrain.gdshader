shader_type spatial;
render_mode world_vertex_coords, cull_back, depth_draw_opaque;

// Terrain surface: 8 material layers from two Texture2DArrays, weighted by the
// world splat map, slope, altitude and weather; height-based blending,
// triplanar rock on cliffs, two tiling scales against repetition and a
// distance tint so far-away fields read as grass.

#include "res://shaders/include/terrain_common.gdshaderinc"

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_array : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float near_scale = 0.26;
uniform float far_scale = 0.043;
uniform float rock_scale = 0.09;
uniform float detail_normal = 0.75;
uniform vec3 meadow_tint : source_color = vec3(0.33, 0.42, 0.15);
uniform vec3 pampas_tint : source_color = vec3(0.74, 0.6, 0.33);
uniform vec3 forest_tint : source_color = vec3(0.3, 0.16, 0.09);
uniform float distant_tint_start = 20.0;
uniform float distant_tint_end = 160.0;

global uniform float wetness;
global uniform float rain_amount;

// animated rain ripples: returns a height-field gradient (xz) for puddles
vec2 rain_ripples(vec2 p, float t) {
	vec2 g = vec2(0.0);
	for (int layer = 0; layer < 2; layer++) {
		vec2 q = p * (layer == 0 ? 2.3 : 3.7) + float(layer) * 9.1;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float h1 = fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
		float h2 = fract(sin(dot(cell, vec2(269.5, 183.3))) * 43758.5453);
		float ph = fract(t * (0.8 + h2 * 0.6) + h1);
		vec2 c = f - (vec2(h1, h2) - 0.5) * 0.6;
		float d = length(c);
		float r = ph * 0.45;
		float ring = sin((d - r) * 60.0) * exp(-abs(d - r) * 14.0) * (1.0 - ph) * step(h1, 0.35 + rain_amount * 0.5);
		g += normalize(c + vec2(1e-4)) * ring * 0.5;
	}
	return g;
}
global uniform float snow_amount;

varying vec3 v_world;

const int L_GRASS = 0;
const int L_DRY = 1;
const int L_DIRT = 2;
const int L_FOREST = 3;
const int L_ROCK = 4;
const int L_SAND = 5;
const int L_SNOW = 6;
const int L_SCREE = 7;

void vertex() {
	float h = terrain_height_at(VERTEX.xz);
	float chunk = length(MODEL_MATRIX[0].xyz);
	VERTEX.y = h - UV2.x * chunk / 16.0;
	v_world = VERTEX;
	NORMAL = terrain_normal_at(VERTEX.xz);
}

vec4 sample_layer_alb(vec2 uv, int layer) {
	return texture(albedo_array, vec3(uv, float(layer)));
}

vec4 sample_layer_nrh(vec2 uv, int layer) {
	return texture(nrh_array, vec3(uv, float(layer)));
}

// Rock with triplanar projection (cliffs would stretch a top-down projection).
void rock_triplanar(vec3 wp, vec3 n, out vec3 alb, out vec3 nrm_off, out float rough, out float height) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec2 uvx = wp.zy * rock_scale;
	vec2 uvy = wp.xz * rock_scale;
	vec2 uvz = wp.xy * rock_scale;
	vec4 ax = sample_layer_alb(uvx, L_ROCK);
	vec4 ay = sample_layer_alb(uvy, L_ROCK);
	vec4 az = sample_layer_alb(uvz, L_ROCK);
	vec4 nx = sample_layer_nrh(uvx, L_ROCK);
	vec4 ny = sample_layer_nrh(uvy, L_ROCK);
	vec4 nz = sample_layer_nrh(uvz, L_ROCK);
	alb = ax.rgb * w.x + ay.rgb * w.y + az.rgb * w.z;
	rough = nx.b * w.x + ny.b * w.y + nz.b * w.z;
	height = nx.a * w.x + ny.a * w.y + nz.a * w.z;
	vec2 tx = nx.rg * 2.0 - 1.0;
	vec2 ty = ny.rg * 2.0 - 1.0;
	vec2 tz = nz.rg * 2.0 - 1.0;
	// map each projection's tangent perturbation back to world space
	nrm_off = vec3(0.0, tx.y, tx.x) * sign(n.x) * w.x
			+ vec3(ty.x, 0.0, -ty.y) * w.y
			+ vec3(tz.x, tz.y, 0.0) * sign(n.z) * w.z;
}

void fragment() {
	vec3 wp = v_world;
	vec3 wn = terrain_normal_at(wp.xz);
	vec4 sp = terrain_splat_at(wp.xz);
	float dist = length(wp - CAMERA_POSITION_WORLD);

	// macro variation, breaks tiling at every distance
	float macro = value_noise(wp.xz * 0.021) * 0.6 + value_noise(wp.xz * 0.0045) * 0.4;
	float micro = value_noise(wp.xz * 0.35);

	// ---------------------------------------------------------------- weights
	float w[8];
	float slope = 1.0 - wn.y;
	float rock = smoothstep(0.2, 0.33, slope + (micro - 0.5) * 0.06);
	float snow_line = 255.0 + (macro - 0.5) * 45.0;
	float snow = smoothstep(snow_line - 18.0, snow_line + 12.0, wp.y) * (1.0 - smoothstep(0.35, 0.55, slope));
	snow = max(snow, snow_amount * smoothstep(0.4, 0.2, slope) * step(terrain_info.w + 2.0, wp.y));
	float sand = smoothstep(3.4, 1.3, wp.y + (micro - 0.5) * 0.8) * (1.0 - rock);
	float scree = smoothstep(170.0, 215.0, wp.y + (macro - 0.5) * 40.0) * (1.0 - snow);
	float ground = (1.0 - rock) * (1.0 - snow) * (1.0 - sand);
	w[L_GRASS] = sp.r;
	w[L_DRY] = sp.g;
	w[L_DIRT] = sp.b;
	w[L_FOREST] = sp.a;
	float cover = sp.r + sp.g + sp.b + sp.a;
	w[L_GRASS] += max(0.0, 1.0 - cover);
	float scree_share = scree * (1.0 - sp.b);
	for (int i = 0; i < 4; i++) {
		w[i] *= ground * (1.0 - scree_share);
	}
	w[L_SCREE] = scree_share * ground;
	w[L_ROCK] = rock * (1.0 - snow * 0.7);
	w[L_SAND] = sand * (1.0 - snow);
	w[L_SNOW] = snow;

	// ------------------------------------------------------------- sampling
	vec2 uv_near = wp.xz * near_scale;
	vec2 uv_far = wp.xz * far_scale + vec2(0.37, 0.71);
	float far_mix = smoothstep(18.0, 70.0, dist);
	float hmax = -10.0;
	float hl[8];
	vec3 alb[8];
	vec3 noff[8];
	float rgh[8];
	for (int i = 0; i < 8; i++) {
		hl[i] = 0.0;
		alb[i] = vec3(0.0);
		noff[i] = vec3(0.0);
		rgh[i] = 0.9;
		if (w[i] < 0.004) {
			continue;
		}
		if (i == L_ROCK) {
			rock_triplanar(wp, wn, alb[i], noff[i], rgh[i], hl[i]);
		} else {
			vec4 a = vec4(0.0);
			vec4 n = vec4(0.0);
			if (far_mix < 0.999) {
				a = sample_layer_alb(uv_near, i);
				n = sample_layer_nrh(uv_near, i);
			}
			if (far_mix > 0.001) {
				a = mix(a, sample_layer_alb(uv_far, i), far_mix);
				n = mix(n, sample_layer_nrh(uv_far, i), far_mix);
			}
			alb[i] = a.rgb;
			vec2 t = n.rg * 2.0 - 1.0;
			noff[i] = vec3(t.x, 0.0, -t.y);
			rgh[i] = n.b;
			hl[i] = n.a;
		}
		hmax = max(hmax, hl[i] + w[i]);
	}
	// height blend: layers with higher surface detail poke through transitions
	float depth = 0.22;
	float wsum = 0.0;
	vec3 albedo = vec3(0.0);
	vec3 nsum = vec3(0.0);
	float rough = 0.0;
	for (int i = 0; i < 8; i++) {
		if (w[i] < 0.004) {
			continue;
		}
		float b = max(hl[i] + w[i] - (hmax - depth), 0.0);
		wsum += b;
		albedo += alb[i] * b;
		nsum += noff[i] * b;
		rough += rgh[i] * b;
	}
	wsum = max(wsum, 1e-4);
	albedo /= wsum;
	nsum /= wsum;
	rough /= wsum;

	// far fields read as the grass that grows on them
	float tint_k = smoothstep(distant_tint_start, distant_tint_end, dist);
	vec3 grass_col = (meadow_tint * w[L_GRASS] + pampas_tint * w[L_DRY] + forest_tint * w[L_FOREST])
			/ max(w[L_GRASS] + w[L_DRY] + w[L_FOREST], 1e-3);
	float grassy = clamp(w[L_GRASS] + w[L_DRY] + w[L_FOREST] * 0.6, 0.0, 1.0);
	albedo = mix(albedo, grass_col * (0.72 + 0.3 * macro), mix(0.3, 0.78, tint_k) * grassy);

	albedo *= 0.86 + 0.28 * macro;
	albedo = mix(albedo, albedo * vec3(1.06, 1.0, 0.9), smoothstep(0.55, 0.8, macro) * 0.5);

	// rain: darker, glossier, puddles that gather in the low flat spots
	float flat_area = smoothstep(0.1, 0.0, slope);
	float wet = wetness * (1.0 - w[L_SNOW]);
	float puddle = wet * flat_area * smoothstep(0.52, 0.4, macro) * smoothstep(0.3, 0.9, wetness) * (1.0 - w[L_ROCK]);
	albedo *= mix(1.0, 0.58, wet);
	albedo = mix(albedo, albedo * vec3(0.55, 0.6, 0.66), puddle);
	rough = mix(rough, 0.16, wet * 0.6);
	rough = mix(rough, 0.02, puddle);

	vec3 n_world = normalize(wn + nsum * detail_normal * (1.0 - far_mix * 0.6) * (1.0 - puddle * 0.9));
	if (puddle > 0.02 && rain_amount > 0.05 && dist < 45.0) {
		vec2 rg = rain_ripples(wp.xz, TIME);
		n_world = normalize(n_world + vec3(rg.x, 0.0, rg.y) * puddle * rain_amount * (1.0 - dist / 45.0));
	}
	ALBEDO = albedo;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	SPECULAR = 0.35;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
}
