shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Tree leaf cards and bark with wind sway driven by the vertex colours baked
// in Blender: R sway weight, G phase, B leaf flag, A crown occlusion.

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
global uniform float guide_wind;
global uniform float wetness;
global uniform float snow_amount;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool is_leaf = true;
uniform bool use_normal_map = false;
uniform vec3 tint : source_color = vec3(1.0);
uniform float tint_variation = 0.18;
uniform float alpha_cut = 0.45;
uniform float sway_amount = 1.0;
uniform float translucency = 0.85;
uniform float uv_scale_v = 1.0;

varying float v_occl;
varying float v_var;

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float inst = hash11(dot(root, vec3(0.13, 0.71, 0.37)));
	float sway_w = COLOR.r * sway_amount;
	float phase = COLOR.g * 6.2831 + inst * 6.2831;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 wd = wind_dir;
	float strength = wind_strength + guide_wind * 1.2;
	// trunk/branch bending (low frequency) + leaf flutter (high frequency)
	float bend = (sin(wind_time * 0.9 + phase * 0.3 + dot(root.xz, wd) * 0.05) * 0.5 + 0.7) * strength;
	vec3 offset = vec3(wd.x, 0.0, wd.y) * bend * sway_w * sway_w * 0.35;
	float flutter = sin(TIME * 7.0 + phase * 5.0 + wp.x * 1.3 + wp.z * 0.7) * COLOR.b;
	offset += vec3(flutter * 0.03, flutter * 0.05, -flutter * 0.03) * strength * sway_w;
	// bring the offset into model space (models are only rotated/scaled uniformly)
	mat3 inv = inverse(mat3(MODEL_MATRIX));
	VERTEX += inv * offset;
	v_occl = COLOR.a;
	v_var = inst;
}

void fragment() {
	vec2 uv = UV;
	if (!is_leaf) {
		uv.y *= uv_scale_v;
	}
	vec4 tx = texture(albedo_tex, uv);
	vec3 col = tx.rgb * tint;
	// per-instance hue/brightness variation keeps forests from looking cloned
	col *= mix(1.0 - tint_variation, 1.0 + tint_variation, v_var);
	col = mix(col, col * vec3(1.08, 0.94, 0.85), step(0.5, fract(v_var * 7.0)) * tint_variation);
	float occl = mix(0.45, 1.0, v_occl);
	col *= occl;
	col = mix(col, vec3(0.9, 0.92, 0.95), snow_amount * (is_leaf ? 0.55 : 0.2) * smoothstep(0.3, 0.8, NORMAL.y));
	col *= mix(1.0, 0.72, wetness);
	ALBEDO = col;
	if (is_leaf) {
		ALPHA = tx.a;
		ALPHA_SCISSOR_THRESHOLD = alpha_cut;
		BACKLIGHT = col * translucency * occl;
		ROUGHNESS = mix(0.6, 0.35, wetness);
		SPECULAR = 0.3;
		if (!FRONT_FACING) {
			NORMAL = -NORMAL;
		}
	} else {
		ROUGHNESS = mix(0.9, 0.45, wetness);
		SPECULAR = 0.25;
		if (use_normal_map) {
			NORMAL_MAP = texture(normal_tex, uv).rgb;
		}
	}
}
