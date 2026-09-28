shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx, world_vertex_coords;

// Ocean / lake / hot-spring water. Gerstner swell in the vertex stage, two
// scrolling detail normal maps, depth-based absorption with screen-space
// refraction, shoreline foam driven by the terrain heightmap and animated
// surf lines rolling towards the beach.

#include "res://shaders/include/terrain_common.gdshaderinc"

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
global uniform vec3 sun_dir;
global uniform vec4 sun_color;
global uniform float wetness;

uniform float water_level = 0.0;
uniform float wave_height = 0.42;
uniform float wave_length = 1.0;
uniform float choppiness = 0.6;
uniform float detail_scale = 0.07;
uniform float detail_strength = 0.55;
uniform vec3 deep_color : source_color = vec3(0.012, 0.075, 0.12);
uniform vec3 shallow_color : source_color = vec3(0.07, 0.36, 0.38);
uniform vec3 scatter_color : source_color = vec3(0.05, 0.28, 0.26);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);
uniform float clarity = 0.18;
uniform float roughness = 0.035;
uniform float shore_foam = 1.0;
uniform float surf = 1.0;
uniform float milky = 0.0;
uniform sampler2D normal_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D foam_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 v_world;
varying float v_crest;
varying float v_depth;

vec2 rotate_dir(vec2 d, float a) {
	return vec2(d.x * cos(a) - d.y * sin(a), d.x * sin(a) + d.y * cos(a));
}

vec3 gerstner(vec2 p, vec2 dir, float steep, float wl, inout vec3 tangent, inout vec3 binormal, float t) {
	float k = 6.28318 / wl;
	float c = sqrt(9.8 / k);
	vec2 d = normalize(dir);
	float f = k * (dot(d, p) - c * t);
	float a = steep / k;
	tangent += vec3(-d.x * d.x * steep * sin(f), d.x * steep * cos(f), -d.x * d.y * steep * sin(f));
	binormal += vec3(-d.x * d.y * steep * sin(f), d.y * steep * cos(f), -d.y * d.y * steep * sin(f));
	return vec3(d.x * a * cos(f), a * sin(f), d.y * a * cos(f));
}

void vertex() {
	vec2 p = VERTEX.xz;
	float ground = terrain_height_at(p);
	float depth = water_level - ground;
	v_depth = depth;
	float calm = smoothstep(0.0, 6.0, depth);
	float amp = wave_height * (0.55 + 0.45 * clamp(wind_strength, 0.0, 2.0)) * calm;
	vec3 tangent = vec3(1.0, 0.0, 0.0);
	vec3 binormal = vec3(0.0, 0.0, 1.0);
	vec2 wd = normalize(wind_dir + vec2(1e-4));
	float t = TIME;
	vec3 off = vec3(0.0);
	float s = choppiness * clamp(amp / max(wave_height, 1e-3), 0.0, 1.5);
	off += gerstner(p, wd, 0.16 * s, 34.0 * wave_length, tangent, binormal, t);
	off += gerstner(p, rotate_dir(wd, 0.6), 0.12 * s, 17.0 * wave_length, tangent, binormal, t);
	off += gerstner(p, rotate_dir(wd, -0.5), 0.1 * s, 9.0 * wave_length, tangent, binormal, t);
	off += gerstner(p, rotate_dir(wd, 1.4), 0.07 * s, 4.6 * wave_length, tangent, binormal, t);
	float scale = amp / max(wave_height, 1e-3) * wave_height / 0.42;
	VERTEX += off * vec3(1.0, scale, 1.0) * step(0.01, wave_height);
	v_crest = off.y * scale;
	NORMAL = normalize(cross(binormal, tangent));
	v_world = VERTEX;
}

void fragment() {
	vec3 wp = v_world;
	vec2 wd = normalize(wind_dir + vec2(1e-4));
	float spd = 0.02 + 0.02 * wind_strength;
	vec2 uv1 = wp.xz * detail_scale + wd * TIME * spd;
	vec2 uv2 = wp.xz * detail_scale * 1.9 + rotate_dir(wd, 1.1) * TIME * spd * 1.3;
	vec3 n1 = texture(normal_a, uv1).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_b, uv2).rgb * 2.0 - 1.0;
	vec3 dn = vec3(n1.x + n2.x, 0.0, -(n1.y + n2.y)) * detail_strength;
	float dist = length(wp - CAMERA_POSITION_WORLD);
	dn *= mix(1.0, 0.35, smoothstep(40.0, 300.0, dist));
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz + dn);

	// scene depth behind the surface
	float raw = texture(depth_tex, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, raw, 1.0);
	vec4 view = INV_PROJECTION_MATRIX * ndc;
	view.xyz /= view.w;
	float scene_dist = -view.z;
	float surf_dist = -VERTEX.z;
	float thickness = max(scene_dist - surf_dist, 0.0);
	float column = max(v_depth, 0.0);
	float d = min(thickness, column * 2.5 + 0.5);

	// refraction
	vec2 ruv = SCREEN_UV + (VIEW_MATRIX * vec4(dn, 0.0)).xy * 0.03 * clamp(d * 0.5, 0.0, 1.0);
	float raw2 = texture(depth_tex, ruv).r;
	vec4 v2 = INV_PROJECTION_MATRIX * vec4(ruv * 2.0 - 1.0, raw2, 1.0);
	v2.xyz /= v2.w;
	if (-v2.z < surf_dist) {
		ruv = SCREEN_UV;  // do not refract things in front of the water
	}
	vec3 behind = textureLod(screen_tex, ruv, 0.0).rgb;
	float trans = exp(-d * clarity);
	vec3 water_col = mix(deep_color, shallow_color, exp(-column * 0.25));
	water_col = mix(water_col, vec3(0.55, 0.72, 0.7), milky);
	vec3 refracted = behind * mix(vec3(1.0), shallow_color * 2.2, 1.0 - trans) * trans;

	// foam: shoreline, object intersections and wave crests
	float f = texture(foam_tex, wp.xz * 0.18 + wd * TIME * 0.03).a;
	float f2 = texture(foam_tex, wp.xz * 0.07 - wd * TIME * 0.02).a;
	float shore = smoothstep(1.4, 0.0, column) * shore_foam;
	float contact = smoothstep(0.6, 0.0, thickness);
	float waves_in = sin(column * 3.2 - TIME * 1.6 + f2 * 3.0) * 0.5 + 0.5;
	float surf_line = smoothstep(0.75, 0.95, waves_in) * smoothstep(3.5, 0.6, column) * surf;
	float crest = smoothstep(0.35, 0.7, v_crest / max(wave_height, 0.01));
	float foam = clamp(shore * (f * 1.4 + 0.2) + contact * f + surf_line * f * 1.6 + crest * f2 * 0.8, 0.0, 1.0);

	// sub-surface glow when the sun shines through wave crests
	float sss = pow(max(dot(normalize(-sun_dir), normalize(CAMERA_POSITION_WORLD - wp)), 0.0), 4.0) * max(v_crest, 0.0);

	ALBEDO = mix(water_col * (1.0 - trans) * 0.6, foam_color, foam);
	EMISSION = refracted * (1.0 - foam) + scatter_color * sss * sun_color.rgb * 0.4;
	ROUGHNESS = mix(roughness + wetness * 0.02, 0.8, foam);
	SPECULAR = 0.6;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	ALPHA = clamp(smoothstep(0.0, 0.25, thickness) + foam, 0.0, 1.0);
}
