shader_type sky;
render_mode use_debanding;

// Painterly physically-inspired sky: altitude gradients driven by the sun
// elevation, sunset band towards the sun, Mie halo, sun & moon discs, stars
// and two layers of animated clouds lit by the sun (silver linings, dark
// bellies). LIGHT0 = sun, LIGHT1 = moon.

uniform vec3 day_zenith : source_color = vec3(0.19, 0.38, 0.72);
uniform vec3 day_horizon : source_color = vec3(0.66, 0.78, 0.9);
uniform vec3 sunset_zenith : source_color = vec3(0.25, 0.3, 0.52);
uniform vec3 sunset_horizon : source_color = vec3(1.0, 0.56, 0.3);
uniform vec3 sunset_glow : source_color = vec3(1.0, 0.36, 0.14);
uniform vec3 night_zenith : source_color = vec3(0.012, 0.018, 0.045);
uniform vec3 night_horizon : source_color = vec3(0.05, 0.07, 0.12);
uniform vec3 ground_color : source_color = vec3(0.16, 0.15, 0.14);
uniform float sky_energy = 1.0;
uniform float sun_disc_size = 0.9994;
uniform float sun_disc_energy = 38.0;
uniform float mie_strength = 0.35;

uniform sampler2D cloud_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D cloud_detail : filter_linear_mipmap, repeat_enable;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.45;
uniform float cloud_density : hint_range(0.0, 2.0) = 1.0;
uniform float cloud_scale = 0.16;
uniform float cloud_speed = 0.004;
uniform vec3 cloud_lit_tint : source_color = vec3(1.0, 0.97, 0.93);
uniform vec3 cloud_shadow_tint : source_color = vec3(0.42, 0.46, 0.55);
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform float lightning = 0.0;
uniform float star_intensity = 1.0;

global uniform vec2 wind_dir;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float cloud_field(vec2 uv, float coverage) {
	float n = texture(cloud_noise, uv).r * 0.62;
	n += texture(cloud_noise, uv * 2.3 + vec2(0.31, 0.17)).r * 0.26;
	n += texture(cloud_detail, uv * 5.1 + vec2(0.7, 0.2)).r * 0.12;
	return smoothstep(1.0 - coverage, 1.0 - coverage + 0.32, n);
}

void sky() {
	vec3 dir = EYEDIR;
	vec3 sun = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, -1.0, 0.0);
	float sun_y = sun.y;
	float day = smoothstep(-0.12, 0.22, sun_y);
	float sunset = clamp(1.0 - abs(sun_y - 0.02) / 0.3, 0.0, 1.0);
	sunset = sunset * sunset * (3.0 - 2.0 * sunset);
	float night = 1.0 - smoothstep(-0.22, 0.02, sun_y);

	vec3 zen = mix(night_zenith, day_zenith, day);
	vec3 hor = mix(night_horizon, day_horizon, day);
	zen = mix(zen, sunset_zenith, sunset * 0.55);
	hor = mix(hor, sunset_horizon, sunset * 0.85);

	float up = max(dir.y, 0.0);
	float grad = pow(1.0 - up, 3.2);
	vec3 col = mix(zen, hor, grad);

	// sunset glow concentrated on the sun's side of the sky
	vec2 dh = normalize(dir.xz + vec2(1e-5));
	vec2 sh = normalize(sun.xz + vec2(1e-5));
	float toward = max(dot(dh, sh), 0.0);
	float band = exp(-up * 7.0);
	col += sunset_glow * pow(toward, 3.0) * band * sunset * 0.9;
	col += sunset_horizon * pow(toward, 8.0) * band * sunset * 0.6;

	// Mie halo around the sun
	float cosang = dot(dir, sun);
	float mie = pow(max(cosang, 0.0), 12.0) * 0.5 + pow(max(cosang, 0.0), 180.0) * 2.0;
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0);
	col += sun_col * mie * mie_strength * (0.4 + 0.6 * day) * step(-0.25, sun_y);

	// below the horizon: fade to a dim ground colour
	float below = smoothstep(0.0, -0.08, dir.y);
	col = mix(col, ground_color * (0.25 + 0.75 * day) + hor * 0.3, below);

	// storm darkening
	col = mix(col, vec3(dot(col, vec3(0.33))) * vec3(0.55, 0.58, 0.62), storm * 0.75);

	// stars and moon
	if (night > 0.0 && dir.y > 0.0) {
		vec3 sd = dir * 260.0;
		vec3 cell = floor(sd);
		float h = hash13(cell);
		float star = step(0.9975, h) * smoothstep(0.5, 0.0, length(fract(sd) - 0.5));
		float twinkle = 0.6 + 0.4 * sin(TIME * (2.0 + h * 5.0) + h * 40.0);
		col += vec3(0.9, 0.93, 1.0) * star * twinkle * night * star_intensity * 3.0 * (1.0 - storm);
		// faint milky band
		float milky = exp(-pow(dot(dir, normalize(vec3(0.3, 0.2, 1.0))) * 3.5, 2.0));
		col += vec3(0.05, 0.06, 0.09) * milky * night * (1.0 - storm) * 0.6;
	}
	if (LIGHT1_ENABLED) {
		float mc = dot(dir, LIGHT1_DIRECTION);
		float disc = smoothstep(0.99955, 0.9997, mc);
		col += vec3(0.85, 0.88, 1.0) * disc * 4.0 * night;
		col += vec3(0.35, 0.4, 0.55) * pow(max(mc, 0.0), 60.0) * 0.4 * night;
	}

	// sun disc (hidden by clouds below)
	float disc = smoothstep(sun_disc_size, sun_disc_size + 0.00025, cosang);
	vec3 sun_disc = sun_col * disc * sun_disc_energy * smoothstep(-0.03, 0.02, sun_y);

	// clouds on a curved plane
	float cloud_a = 0.0;
	vec3 cloud_col = vec3(0.0);
	if (dir.y > 0.005) {
		vec2 drift = wind_dir * TIME * cloud_speed;
		float t = 1.0 / (dir.y + 0.12);
		vec2 uv = dir.xz * t * cloud_scale + drift;
		float cov = clamp(cloud_coverage + storm * 0.45, 0.0, 1.0);
		float d = cloud_field(uv, cov);
		float d2 = cloud_field(uv * 0.55 + vec2(0.4, 0.8) - drift * 0.3, cov * 0.8);
		d = max(d, d2 * 0.85);
		// light marching one step towards the sun: thicker = darker
		vec2 to_sun = normalize(sun.xz + vec2(1e-4)) * 0.03;
		float ds = cloud_field(uv + to_sun, cov);
		float lit = clamp(1.0 - (ds - d * 0.5) * 1.4, 0.0, 1.0);
		float silver = pow(max(cosang, 0.0), 6.0) * (1.0 - d) * 2.5;
		vec3 lit_col = sun_col * cloud_lit_tint * (0.35 + 1.1 * day) + sunset_glow * sunset * 0.6 * pow(toward, 2.0);
		vec3 shade_col = mix(hor, zen, 0.4) * cloud_shadow_tint * (0.5 + 0.5 * day) + vec3(0.02, 0.025, 0.04) * night;
		cloud_col = mix(shade_col, lit_col, lit) + sun_col * silver * day;
		cloud_col = mix(cloud_col, cloud_col * 0.35, storm);
		cloud_col += vec3(0.8, 0.85, 1.0) * lightning * d * 4.0;
		float horizon_fade = smoothstep(0.005, 0.14, dir.y);
		cloud_a = clamp(d * cloud_density, 0.0, 1.0) * horizon_fade;
	}
	col = mix(col + sun_disc, cloud_col, cloud_a);
	col += vec3(0.7, 0.75, 0.9) * lightning * 0.35;

	COLOR = col * sky_energy;
}
