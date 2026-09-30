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
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float lens_rain = 0.0;
uniform float lens_blood = 0.0;
uniform vec3 lens_tint : source_color = vec3(0.5, 0.02, 0.02);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Droplets on the lens: xy = refraction offset, z = drop mask. Drops swell
// and slowly slide down; `slip` speeds the slide (blood runs faster).
vec3 lens_drops(vec2 uv, float aspect, float t, float seed, float cells, float size, float slip) {
	vec2 p = uv * vec2(aspect, 1.0) * cells;
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	float h1 = hash(id + seed);
	float h2 = hash(id * 1.7 + seed + 4.3);
	float h3 = hash(id * 2.3 + seed + 9.1);
	float life = fract(t * (0.02 + 0.03 * h2) * slip + h1);
	float y_off = -smoothstep(0.55, 1.0, life) * 0.45;
	vec2 c = vec2((h1 - 0.5) * 0.5, (h2 - 0.5) * 0.35 + y_off);
	float r = size * (0.22 + 0.4 * h3) * (0.4 + 0.6 * smoothstep(0.0, 0.25, life));
	vec2 q = (f - c) * vec2(1.0, 0.85);
	float d = length(q);
	float m = smoothstep(r, r * 0.55, d) * step(h3, 0.7);
	// a thin streak above the drop while it slides
	float streak = smoothstep(r * 0.35, 0.0, abs(f.x - c.x)) * step(c.y, f.y) * step(f.y, c.y + 0.35 * smoothstep(0.55, 0.8, life)) * 0.35 * step(h3, 0.7);
	vec2 off = -(q / max(r, 1e-3)) * m;
	return vec3(off, clamp(m + streak, 0.0, 1.0));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec3 wet = vec3(0.0);
	vec3 gore = vec3(0.0);
	if (lens_rain > 0.01) {
		wet = lens_drops(uv, aspect, TIME, 1.0, 9.0, 0.36, 1.0) * lens_rain;
		wet += lens_drops(uv, aspect, TIME, 7.0, 5.5, 0.42, 0.7) * lens_rain * 0.7;
	}
	if (lens_blood > 0.01) {
		gore = lens_drops(uv, aspect, TIME, 3.0, 4.0, 0.55, 2.2) * lens_blood;
		gore += lens_drops(uv, aspect, TIME, 11.0, 7.0, 0.4, 1.6) * lens_blood * 0.8;
	}
	uv += (wet.xy + gore.xy) * 0.03;
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
	// lens water brightens at the edges; blood tints and darkens what is behind
	col += vec3(0.9, 0.95, 1.0) * clamp(wet.z, 0.0, 1.0) * 0.06;
	col = mix(col, lens_tint * (0.5 + 0.5 * col), clamp(gore.z, 0.0, 1.0) * 0.85);
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
	col = mix(col, flash_color.rgb, clamp(flash_color.a, 0.0, 1.0) * (1.0 - r2 * 0.6));
	COLOR = vec4(col, 1.0);
}
