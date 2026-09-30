// Shared vertex animation + colouring for every grass-like layer
// (particle instances created by grass_particles.gdshader).
// INSTANCE_CUSTOM: x random, y golden (pampas) share, z clump noise, w forest share.

#include "res://shaders/include/terrain_common.gdshaderinc"

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
global uniform float guide_wind;
global uniform vec4 trample_0;
global uniform vec4 trample_1;
global uniform vec4 trample_2;
global uniform vec4 trample_3;
global uniform float wetness;
global uniform float rain_amount;
global uniform float snow_amount;

uniform vec3 base_color : source_color = vec3(0.07, 0.12, 0.03);
uniform vec3 tip_color : source_color = vec3(0.46, 0.56, 0.16);
uniform vec3 tip_color_dry : source_color = vec3(0.66, 0.6, 0.24);
uniform vec3 gold_base : source_color = vec3(0.24, 0.16, 0.06);
uniform vec3 gold_tip : source_color = vec3(0.86, 0.66, 0.33);
uniform vec3 forest_tip : source_color = vec3(0.34, 0.36, 0.12);
uniform float use_vertex_color = 0.0;
uniform float sway = 1.0;
uniform float stiffness = 1.0;
uniform float backlight = 0.7;

varying float v_h;
varying vec3 v_base;
varying vec3 v_tip;

vec2 trample_push(vec4 tr, vec3 root, float t, inout float flat_k) {
	vec2 away = root.xz - tr.xz;
	float d = length(away);
	float near = (1.0 - smoothstep(tr.w * 0.35, tr.w, d)) * step(abs(tr.y - root.y), 1.8) * step(0.001, tr.w);
	flat_k = max(flat_k, near);
	return (away / max(d, 0.001)) * near * t;
}

void grass_vertex(inout vec3 vtx, inout vec3 nrm, vec2 uv, vec4 vcol, vec4 ic, mat4 model, float time, out float o_h, out vec3 o_base, out vec3 o_tip) {
	float t = uv.y;
	vec3 root = model[3].xyz;
	float blade_h = length(model[1].xyz);
	float phase = dot(root.xz, wind_dir) * 0.32 - wind_time * 1.9 + ic.x * 6.28;
	float wave = sin(phase) * 0.5 + 0.5;
	float gust = value_noise(root.xz * 0.045 - wind_dir * wind_time * 1.6);
	float flutter = sin(time * 6.5 + ic.x * 40.0 + root.x) * 0.05;
	float bend = (0.08 + 0.55 * wave * (0.35 + gust) + flutter) * wind_strength * sway / stiffness;
	bend += guide_wind * 0.9 * sway;
	vec2 disp = wind_dir * bend * t * t * blade_h;
	float flat_k = 0.0;
	vec2 tp = trample_push(trample_0, root, t, flat_k) + trample_push(trample_1, root, t, flat_k)
			+ trample_push(trample_2, root, t, flat_k) + trample_push(trample_3, root, t, flat_k);
	disp += tp * blade_h * 1.3;
	// wet blades are heavy: they droop over and clump together, rain makes them shiver
	float droop = wetness * (0.35 + 0.4 * fract(ic.x * 7.31)) * t * t;
	vec2 droop_dir = normalize(vec2(sin(ic.x * 31.0), cos(ic.x * 17.0)) + wind_dir * 0.6);
	disp += droop_dir * droop * blade_h * 0.55;
	disp += vec2(sin(time * 23.0 + ic.x * 50.0), cos(time * 19.0 + ic.x * 40.0)) * rain_amount * 0.025 * t * blade_h;
	vtx.xz += disp;
	vtx.y -= dot(disp, disp) * 0.45 / max(blade_h, 0.05) + flat_k * t * blade_h * 0.45 + droop * blade_h * 0.25;
	nrm = normalize(mix(nrm, vec3(0.0, 1.0, 0.0), 0.5));
	o_h = t;
	// colour per instance: meadow <-> golden pampas, forest floor shade, clumps
	float gold = ic.y;
	float dry = smoothstep(0.35, 0.8, ic.z) * 0.6 + ic.x * 0.25;
	vec3 tip = mix(tip_color, tip_color_dry, dry);
	tip = mix(tip, gold_tip, gold);
	tip = mix(tip, forest_tip, ic.w * 0.6);
	vec3 base = mix(base_color, gold_base, gold);
	if (use_vertex_color > 0.5) {
		tip = vcol.rgb;
		base = vcol.rgb * 0.35;
	}
	float var_k = 0.85 + 0.3 * ic.x;
	o_tip = mix(tip * var_k, vec3(0.85, 0.87, 0.9), snow_amount * 0.6);
	o_base = base * var_k;
}

vec3 grass_color(float h, vec3 base, vec3 tip) {
	vec3 col = mix(base, tip, smoothstep(0.0, 0.95, h));
	col *= mix(0.5, 1.0, smoothstep(0.0, 0.45, h));
	col *= mix(1.0, 0.62, wetness);
	col = mix(col, col * vec3(0.85, 0.95, 0.9), wetness * 0.5);
	return col;
}
