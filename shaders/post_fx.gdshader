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
// combat juice: zoom blur towards a point, speed streaks, and the thin "cut" across the screen
uniform float radial_blur = 0.0;
uniform vec2 radial_center = vec2(0.5, 0.5);
uniform float speed_lines = 0.0;
uniform vec4 slash_line = vec4(0.5, 0.5, 0.0, 0.0);   // xy centre (uv), z angle, w strength

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Droplets on the lens: xy = refraction offset, z = drop mask. Drops swell, then run down the glass
// leaving a trail above them; `slip` speeds the slide (blood runs faster). `wear` (0..1) shrinks the
// drops away and `cluster` (0..1) makes the coverage patchy, with lumpy outlines and a small
// satellite drop, the way a splash lands.
vec3 lens_drops(vec2 uv, float aspect, float t, float seed, float cells, float size, float slip, float wear, float cluster) {
	vec2 p = uv * vec2(aspect, 1.0) * cells;
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	float h1 = hash(id + seed);
	float h2 = hash(id * 1.7 + seed + 4.3);
	float h3 = hash(id * 2.3 + seed + 9.1);
	float pat = mix(1.0, smoothstep(0.3, 0.7, vnoise(id * 0.45 + seed * 3.1)), cluster);
	float w = smoothstep(0.0, 0.5, wear * pat);
	float life = fract(t * (0.02 + 0.03 * h2) * slip + h1);
	// screen y grows downwards: the drop runs down and its trail stays above it
	float run = smoothstep(0.55, 1.0, life) * 0.28;
	vec2 c = vec2((h1 - 0.5) * 0.4, (h2 - 0.5) * 0.2 - 0.12 + run);
	float r = size * (0.22 + 0.4 * h3) * (0.4 + 0.6 * smoothstep(0.0, 0.25, life)) * (1.0 - smoothstep(0.88, 1.0, life)) * w;
	float keep = step(h3, mix(0.7, 0.5, cluster));
	vec2 q = (f - c) * vec2(1.0, 0.85);
	float lump = 1.0;
	if (cluster > 0.0) {
		float ang = atan(q.y, q.x);
		lump += cluster * (0.2 * sin(3.0 * ang + h1 * 6.283) + 0.12 * sin(5.0 * ang + h2 * 6.283) + 0.07 * sin(9.0 * ang + h3 * 6.283));
	}
	float m = smoothstep(r, r * 0.55, length(q) / lump) * keep * step(0.004, r);
	float trail = smoothstep(r * 0.3, 0.0, abs(f.x - c.x)) * step(f.y, c.y) * step(c.y - run, f.y) * smoothstep(c.y - run - 0.002, c.y, f.y) * 0.4 * keep;
	vec2 off = -(q / max(r, 1e-3)) * m;
	if (cluster > 0.0) {
		vec2 c2 = c + (vec2(h2, h1) - 0.5) * 0.5;
		float r2 = r * 0.42;
		vec2 q2 = f - c2;
		float m2 = smoothstep(r2, r2 * 0.55, length(q2)) * keep * step(0.004, r2);
		m = max(m, m2);
		off -= (q2 / max(r2, 1e-3)) * m2;
	}
	return vec3(off, clamp(m + trail, 0.0, 1.0));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec3 wet = vec3(0.0);
	vec3 gore = vec3(0.0);
	if (lens_rain > 0.01) {
		wet = lens_drops(uv, aspect, TIME, 1.0, 9.0, 0.36, 1.0, 1.0, 0.0) * lens_rain;
		wet += lens_drops(uv, aspect, TIME, 7.0, 5.5, 0.42, 0.7, 1.0, 0.0) * lens_rain * 0.7;
	}
	if (lens_blood > 0.01) {
		// big splatters and a finer spray, patchy rather than even; they shrink away as the blood wears off
		gore = lens_drops(uv, aspect, TIME, 3.0, 4.5, 0.6, 2.2, lens_blood, 1.0);
		gore += lens_drops(uv, aspect, TIME, 11.0, 9.0, 0.5, 1.6, lens_blood, 1.0) * 0.8;
		gore.z = smoothstep(0.25, 0.6, gore.z);
	}
	uv += (wet.xy + gore.xy) * 0.03;
	// a dimensional cut: the picture is pushed apart along a line through the target
	float cut_dist = 1.0;
	if (slash_line.w > 0.001) {
		vec2 d = uv - slash_line.xy;
		d.x *= aspect;
		vec2 dirv = vec2(cos(slash_line.z), sin(slash_line.z));
		vec2 nrm = vec2(-dirv.y, dirv.x);
		float sd = dot(d, nrm);
		cut_dist = abs(sd);
		uv += vec2(nrm.x / aspect, nrm.y) * sign(sd) * slash_line.w * 0.016 * smoothstep(0.4, 0.0, cut_dist);
	}
	vec2 dc = uv - 0.5;
	float r2 = dot(dc, dc);
	vec3 col;
	float ab = aberration + focus * 0.004;
	if (radial_blur > 0.001) {
		// zoom blur: average the picture along the way to the centre
		vec2 dirb = (radial_center - uv) * radial_blur;
		vec3 acc = vec3(0.0);
		for (int i = 0; i < 9; i++) {
			acc += texture(screen_tex, uv + dirb * (float(i) / 8.0)).rgb;
		}
		col = acc / 9.0;
	} else if (ab > 0.0005) {
		vec2 off = dc * ab * (0.5 + r2 * 2.0);
		col.r = texture(screen_tex, uv + off).r;
		col.g = texture(screen_tex, uv).g;
		col.b = texture(screen_tex, uv - off).b;
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	// lens water brightens at the edges; blood tints and darkens what is behind
	col += vec3(0.9, 0.95, 1.0) * clamp(wet.z, 0.0, 1.0) * 0.06;
	// blood: darker at the heart of a drop, lighter where the glass thins out at its rim
	float rim = clamp(length(gore.xy), 0.0, 1.0);
	col = mix(col, lens_tint * (0.5 + 0.5 * col) * mix(0.7, 1.3, rim * rim), clamp(gore.z, 0.0, 1.0) * 0.88);
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
	// speed streaks radiating from the centre (sprints, lunges)
	if (speed_lines > 0.01) {
		vec2 q = (uv - 0.5) * vec2(aspect, 1.0);
		float sector = floor(atan(q.y, q.x) * 34.0 + hash(vec2(floor(TIME * 18.0), 1.0)) * 6.0);
		float rnd = hash(vec2(sector, floor(TIME * 20.0)));
		float line = smoothstep(0.86, 1.0, rnd) * smoothstep(0.3, 0.9, length(q));
		col += vec3(line * speed_lines * 0.17);
	}
	// the cut itself: a hairline of light that widens and fades as the picture closes again
	if (slash_line.w > 0.001) {
		float wl = 0.0018 + (1.0 - slash_line.w) * 0.008;
		float core = smoothstep(wl, 0.0, cut_dist);
		float glow = smoothstep(0.05, 0.0, cut_dist) * 0.3;
		col += vec3(1.0, 0.97, 0.9) * (core * 1.5 + glow) * slash_line.w;
	}
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
