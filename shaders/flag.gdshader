shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Banner cloth flapping in the global wind. UV.x = distance from the pole.

global uniform vec2 wind_dir;
global uniform float wind_strength;
global uniform float wind_time;
global uniform float wetness;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform float flap = 1.0;

void vertex() {
	float k = UV.x;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float w = wind_strength * flap;
	float wave = sin(wind_time * 3.0 + k * 6.0 + UV.y * 3.0 + wp.x * 0.3) * 0.12
			+ sin(TIME * 7.3 + k * 11.0 + UV.y * 5.0) * 0.04;
	VERTEX.z += wave * k * (0.4 + w);
	VERTEX.x -= abs(wave) * k * 0.2;
}

void fragment() {
	vec4 t = texture(albedo_tex, UV);
	ALBEDO = t.rgb * mix(1.0, 0.7, wetness);
	ROUGHNESS = 0.9;
	BACKLIGHT = t.rgb * 0.35;
}
