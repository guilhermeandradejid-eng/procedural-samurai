shader_type canvas_item;
render_mode unshaded;

// Full-screen grade on top of the 3D image: vignette, film grain, impact
// chromatic aberration, damage flash, low-health desaturation, slow-motion
// focus and the black & white "Kurosawa mode" with heavy grain and scratches.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float vignette = 0.32;
uniform float grain = 0.025;
uniform float aberration = 0.0;
uniform float damage = 0.0;
uniform float low_health = 0.0;
uniform float kurosawa = 0.0;
uniform float focus = 0.0;
uniform float fade = 0.0;
uniform vec3 fade_color : source_color = vec3(0.0);
uniform float letterbox = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dc = uv - 0.5;
	float r2 = dot(dc, dc);
	vec3 col;
	float ab = aberration + focus * 0.004;
	if (ab > 0.0005) {
		vec2 off = dc * ab * (0.5 + r2 * 2.0);
		col.r = texture(screen_tex, uv + off).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - off).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	// low health / slow motion drain the colour (keeps the reds a bit)
	float drain = max(low_health * 0.55, focus * 0.4);
	vec3 grey = vec3(l);
	float redness = clamp((col.r - max(col.g, col.b)) * 3.0, 0.0, 1.0);
	col = mix(col, mix(grey, col, redness * 0.8), drain);
	// Kurosawa: high-contrast black and white film
	if (kurosawa > 0.001) {
		float k = smoothstep(0.03, 0.85, l);
		k = k * k * (3.0 - 2.0 * k);
		float flicker = 1.0 + (hash(vec2(floor(TIME * 24.0), 3.1)) - 0.5) * 0.06;
		float scratch = step(0.9985, hash(vec2(floor(uv.x * 900.0), floor(TIME * 24.0)))) * 0.25;
		col = mix(col, vec3(k * flicker + scratch), kurosawa);
	}
	// damage: blood-red pulse creeping in from the edges
	float edge = smoothstep(0.08, 0.42, r2 * 1.8);
	col = mix(col, vec3(0.42, 0.01, 0.01), damage * edge * 0.85);
	col = mix(col, col * vec3(1.0, 0.75, 0.75), low_health * edge * 0.6);
	// vignette
	col *= 1.0 - (vignette + low_health * 0.25 + focus * 0.2) * smoothstep(0.12, 0.75, r2 * 1.7);
	// grain
	float g = hash(uv * 1000.0 + fract(TIME * 7.3) * 100.0) - 0.5;
	col += g * (grain + kurosawa * 0.07);
	// letterbox for cinematic moments
	float bars = step(uv.y, letterbox * 0.12) + step(1.0 - letterbox * 0.12, uv.y);
	col = mix(col, vec3(0.0), clamp(bars, 0.0, 1.0));
	col = mix(col, fade_color, fade);
	COLOR = vec4(col, 1.0);
}
