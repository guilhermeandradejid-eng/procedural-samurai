shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

// Katana steel: mirror-polished body, cloudy wavy hamon along the edge
// (UV.x = 0 at the edge .. 1 at the spine, UV.y along the blade), a blood
// film that builds up with kills and is flicked off (chiburi), and a
// coloured glint used to telegraph special attacks.

uniform vec3 steel : source_color = vec3(0.78, 0.8, 0.83);
uniform float blood = 0.0;
uniform float glint = 0.0;
uniform vec4 glint_color : source_color = vec4(1.0, 0.2, 0.1, 1.0);
uniform float glint_pos = 0.5;

float h1(float x) {
	return fract(sin(x * 91.7) * 43758.5);
}

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float wave = 0.28 + 0.045 * sin(v * 70.0) + 0.02 * sin(v * 173.0 + 1.3);
	float hamon = smoothstep(wave + 0.03, wave - 0.03, u);
	vec3 c = steel;
	float rough = 0.12;
	c = mix(c, vec3(0.9, 0.92, 0.95), hamon * 0.5);
	rough = mix(rough, 0.3, hamon);
	// blood film: thicker near the edge and towards the tip
	float n = h1(floor(v * 120.0) + floor(u * 6.0) * 13.0);
	float bm = smoothstep(1.0 - blood, 1.0 - blood + 0.25, (1.0 - u) * 0.6 + v * 0.5 + n * 0.25);
	c = mix(c, vec3(0.3, 0.015, 0.015), bm * 0.95);
	rough = mix(rough, 0.2, bm);
	ALBEDO = c;
	METALLIC = mix(1.0, 0.1, bm);
	ROUGHNESS = rough;
	SPECULAR = 0.8;
	float g = glint * exp(-pow((v - glint_pos) * 6.0, 2.0));
	EMISSION = glint_color.rgb * (g * 12.0 + glint * 0.8);
}
