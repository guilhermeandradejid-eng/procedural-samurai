shader_type spatial;
render_mode cull_back, diffuse_burley;

// World-space triplanar rock (shares the terrain texture arrays) with moss
// or snow settling on upward faces, so props match the ground they sit on.

uniform sampler2DArray albedo_array : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray nrh_array : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale = 0.22;
uniform float moss_amount = 0.6;
uniform vec3 tint : source_color = vec3(1.0);
uniform int rock_layer = 4;
uniform int moss_layer = 0;

global uniform float wetness;
global uniform float snow_amount;
global uniform vec3 lod_center;

instance uniform vec2 lod_band = vec2(0.0, 1000000.0);

varying vec3 v_wpos;
varying vec3 v_wnrm;
varying float v_fade;

void vertex() {
	float lod_d = length(MODEL_MATRIX[3].xz - lod_center.xz);
	v_fade = clamp((lod_band.y - lod_d) / 12.0 + 0.5, 0.0, 1.0);
	if (v_fade <= 0.0) {
		VERTEX = vec3(0.0);
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec4 tri(sampler2DArray t, vec3 p, vec3 w, int layer) {
	return texture(t, vec3(p.zy * scale, float(layer))) * w.x
		+ texture(t, vec3(p.xz * scale, float(layer))) * w.y
		+ texture(t, vec3(p.xy * scale, float(layer))) * w.z;
}

void fragment() {
	if (v_fade < 0.999 && fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453) > v_fade) {
		discard;
	}
	vec3 n = normalize(v_wnrm);
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec4 a = tri(albedo_array, v_wpos, w, rock_layer);
	vec4 nr = tri(nrh_array, v_wpos, w, rock_layer);
	vec3 col = a.rgb * tint;
	float rough = nr.b;
	// moss / snow on top faces
	float up = smoothstep(0.45, 0.85, n.y + (nr.a - 0.5) * 0.4);
	vec4 moss = texture(albedo_array, vec3(v_wpos.xz * scale * 1.7, float(moss_layer)));
	col = mix(col, moss.rgb * vec3(0.85, 1.0, 0.75), up * moss_amount);
	float snow = snow_amount * up + smoothstep(250.0, 290.0, v_wpos.y) * up;
	col = mix(col, vec3(0.9, 0.92, 0.96), clamp(snow, 0.0, 1.0));
	col *= mix(1.0, 0.6, wetness);
	ALBEDO = col;
	ROUGHNESS = mix(rough, 0.25, wetness * 0.8);
	vec2 t = nr.rg * 2.0 - 1.0;
	vec3 wn = normalize(n + vec3(t.x, 0.0, -t.y) * 0.6);
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
