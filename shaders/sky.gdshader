shader_type sky;
render_mode use_debanding;

// Painterly sky inspired by Ghost of Tsushima: altitude gradients driven by
// the sun, a warm sunset band, Mie halo and god-ray fans, sun and cratered
// moon, stars with a dusty milky way, shooting stars and faint aurora, and
// three cloud decks - towering cumulus lit through several steps towards the
// sun (silver rims, dark powdered bellies), altocumulus and wind-combed
// cirrus - plus rain curtains under storm clouds.
// LIGHT0 = sun, LIGHT1 = moon.

uniform vec3 day_zenith : source_color = vec3(0.16, 0.34, 0.74);
uniform vec3 day_horizon : source_color = vec3(0.68, 0.8, 0.93);
uniform vec3 sunset_zenith : source_color = vec3(0.24, 0.27, 0.5);
uniform vec3 sunset_horizon : source_color = vec3(1.0, 0.56, 0.3);
uniform vec3 sunset_glow : source_color = vec3(1.0, 0.36, 0.14);
uniform vec3 night_zenith : source_color = vec3(0.008, 0.014, 0.04);
uniform vec3 night_horizon : source_color = vec3(0.045, 0.065, 0.12);
uniform vec3 ground_color : source_color = vec3(0.16, 0.15, 0.14);
uniform float sky_energy = 1.0;
uniform float sun_disc_size = 0.9994;
uniform float sun_disc_energy = 38.0;
uniform float mie_strength = 0.4;

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
uniform float moon_phase : hint_range(-1.0, 1.0) = 0.35;

global uniform vec2 wind_dir;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float cloud_field(vec2 uv, float coverage) {
	float n = texture(cloud_noise, uv).r * 0.6;
	n += texture(cloud_noise, uv * 2.3 + vec2(0.31, 0.17)).r * 0.26;
	n += texture(cloud_detail, uv * 5.1 + vec2(0.7, 0.2)).r * 0.14;
	return smoothstep(1.0 - coverage, 1.0 - coverage + 0.3, n);
}

// thin wind-combed cirrus: noise stretched along the wind direction
float cirrus_field(vec2 uv, vec2 wd, float cover) {
	vec2 along = vec2(dot(uv, wd), dot(uv, vec2(-wd.y, wd.x)));
	along.x *= 0.22;
	along.y *= 1.8;
	float n = texture(cloud_detail, along * 0.9 + vec2(0.13, 0.4)).r * 0.6 + texture(cloud_noise, along * 0.7).r * 0.4;
	return smoothstep(1.0 - cover, 1.0 - cover + 0.35, n);
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
	float grad = pow(1.0 - up, 3.0);
	vec3 col = mix(zen, hor, grad);
	// deeper, richer blue overhead on clear days
	col = mix(col, col * vec3(0.86, 0.92, 1.05), smoothstep(0.35, 1.0, up) * day * (1.0 - storm));

	// sunset glow concentrated on the sun's side of the sky
	vec2 dh = normalize(dir.xz + vec2(1e-5));
	vec2 sh = normalize(sun.xz + vec2(1e-5));
	float toward = max(dot(dh, sh), 0.0);
	float band = exp(-up * 7.0);
	col += sunset_glow * pow(toward, 3.0) * band * sunset * 0.9;
	col += sunset_horizon * pow(toward, 8.0) * band * sunset * 0.6;
	// the opposite horizon turns lilac (Belt of Venus)
	float anti = max(-dot(dh, sh), 0.0);
	col = mix(col, col + vec3(0.32, 0.2, 0.36) * exp(-up * 9.0) * anti * anti, sunset * 0.7);

	// Mie halo around the sun + sun shafts fanning through the haze
	float cosang = dot(dir, sun);
	float mie = pow(max(cosang, 0.0), 12.0) * 0.5 + pow(max(cosang, 0.0), 180.0) * 2.0;
	vec3 sun_col = LIGHT0_ENABLED ? LIGHT0_COLOR : vec3(1.0);
	col += sun_col * mie * mie_strength * (0.4 + 0.6 * day) * step(-0.25, sun_y);
	{
		vec3 rx = normalize(cross(sun, vec3(0.0, 1.0, 0.001)));
		vec3 ry = cross(rx, sun);
		float ang = atan(dot(dir, ry), dot(dir, rx));
		float rays = texture(cloud_detail, vec2(ang * 1.4 + TIME * 0.004, 0.3)).r;
		rays = smoothstep(0.42, 0.9, rays) * pow(max(cosang, 0.0), 5.0);
		col += sun_col * rays * 0.22 * (0.3 + sunset) * step(-0.05, sun_y) * (1.0 - storm * 0.6);
	}

	// below the horizon: fade to a dim ground colour
	float below = smoothstep(0.0, -0.08, dir.y);
	col = mix(col, ground_color * (0.25 + 0.75 * day) + hor * 0.3, below);

	// storm darkening
	col = mix(col, vec3(dot(col, vec3(0.33))) * vec3(0.5, 0.53, 0.58), storm * 0.8);

	// stars, milky way, shooting stars, aurora and moon
	if (night > 0.0 && dir.y > -0.02) {
		float clear = night * (1.0 - storm);
		for (int layer = 0; layer < 2; layer++) {
			float sc = layer == 0 ? 260.0 : 120.0;
			vec3 sd = dir * sc;
			vec3 cell = floor(sd);
			float h = hash13(cell + float(layer) * 17.0);
			float thr = layer == 0 ? 0.9968 : 0.9986;
			float star = step(thr, h) * smoothstep(0.5, 0.0, length(fract(sd) - 0.5));
			float twinkle = 0.6 + 0.4 * sin(TIME * (2.0 + h * 5.0) + h * 40.0);
			vec3 tint = mix(vec3(1.0, 0.85, 0.7), vec3(0.75, 0.85, 1.0), fract(h * 91.0));
			col += tint * star * twinkle * clear * star_intensity * (layer == 0 ? 3.0 : 5.0);
		}
		// milky way: a bright dusty band with dark lanes
		vec3 mw_n = normalize(vec3(0.3, 0.2, 1.0));
		float mw = exp(-pow(dot(dir, mw_n) * 3.2, 2.0));
		vec2 mw_uv = vec2(atan(dir.x, dir.z) * 0.9, dir.y * 2.5);
		float dust = texture(cloud_noise, mw_uv * 1.3).r;
		float lane = smoothstep(0.55, 0.75, texture(cloud_detail, mw_uv * 3.0).r);
		col += vec3(0.07, 0.075, 0.11) * mw * (0.35 + dust) * (1.0 - lane * 0.7) * clear * star_intensity;
		// shooting star every ~11 s
		float st = TIME / 11.0;
		float sid = floor(st);
		float sf = fract(st) * 3.0;
		if (sf < 1.0) {
			vec3 p0 = normalize(vec3(hash11(sid) - 0.5, 0.5 + hash11(sid + 3.0) * 0.5, hash11(sid + 7.0) - 0.5));
			vec3 v = normalize(cross(p0, vec3(hash11(sid + 11.0) - 0.5, 1.0, hash11(sid + 13.0) - 0.5)));
			for (int k = 0; k < 6; k++) {
				float tk = sf - float(k) * 0.025;
				vec3 pk = normalize(p0 + v * tk * 0.35);
				float dd = dot(dir, pk);
				col += vec3(1.0, 0.95, 0.85) * smoothstep(0.99996 - float(k) * 0.00002, 1.0, dd) * (1.0 - float(k) / 6.0) * clear * 6.0 * (1.0 - sf);
			}
		}
		// aurora curtains low in the north
		float az = atan(dir.x, dir.z);
		float curtain = sin(az * 5.0 + TIME * 0.15 + texture(cloud_noise, vec2(az * 0.6, TIME * 0.004)).r * 4.0) * 0.5 + 0.5;
		float ay = smoothstep(0.08, 0.22, dir.y) * smoothstep(0.62, 0.3, dir.y);
		float aur = curtain * curtain * ay * smoothstep(-0.2, 0.9, -dir.z);
		col += mix(vec3(0.1, 0.9, 0.5), vec3(0.5, 0.25, 0.9), smoothstep(0.25, 0.55, dir.y)) * aur * clear * 0.16;
	}
	if (LIGHT1_ENABLED) {
		vec3 md = LIGHT1_DIRECTION;
		float mc = dot(dir, md);
		float disc = smoothstep(0.99955, 0.9997, mc);
		if (disc > 0.0) {
			vec3 mr = normalize(cross(md, vec3(0.0, 1.0, 0.001)));
			vec3 mu = cross(mr, md);
			vec2 mp = vec2(dot(dir, mr), dot(dir, mu)) / 0.0245;
			float craters = texture(cloud_detail, mp * 0.45 + 0.5).r;
			float maria = smoothstep(0.35, 0.65, texture(cloud_noise, mp * 0.25 + 0.5).r);
			float lit = smoothstep(moon_phase - 0.25, moon_phase + 0.25, mp.x);
			vec3 mcol = mix(vec3(0.95, 0.96, 1.0), vec3(0.55, 0.58, 0.68), maria * 0.7) * (0.75 + craters * 0.35);
			col += mcol * disc * 4.2 * night * mix(0.06, 1.0, lit);
		}
		col += vec3(0.35, 0.4, 0.55) * pow(max(mc, 0.0), 60.0) * 0.45 * night;
		col += vec3(0.2, 0.25, 0.4) * pow(max(mc, 0.0), 9.0) * 0.12 * night;
	}

	// sun disc (hidden by clouds below)
	float disc = smoothstep(sun_disc_size, sun_disc_size + 0.00025, cosang);
	vec3 sun_disc = sun_col * disc * sun_disc_energy * smoothstep(-0.03, 0.02, sun_y);

	// ---------------------------------------------------------------- clouds
	vec3 cloud_col = vec3(0.0);
	float cloud_a = 0.0;
	if (dir.y > 0.005) {
		vec2 drift = wind_dir * TIME * cloud_speed;
		float t = 1.0 / (dir.y + 0.12);
		vec2 uv = dir.xz * t * cloud_scale + drift;
		float cov = clamp(cloud_coverage + storm * 0.45, 0.0, 1.0);
		float d = cloud_field(uv, cov);
		float d2 = cloud_field(uv * 0.55 + vec2(0.4, 0.8) - drift * 0.3, cov * 0.8);
		float dens = max(d, d2 * 0.85);
		// optical depth towards the sun over three steps (self shadowing)
		vec2 to_sun = normalize(sun.xz + vec2(1e-4)) * (0.018 + 0.03 * clamp(1.0 - sun.y, 0.0, 1.0));
		float tau = cloud_field(uv + to_sun, cov) + cloud_field(uv + to_sun * 2.2, cov) * 0.8 + cloud_field(uv + to_sun * 4.0, cov) * 0.6;
		float lit = exp(-tau * 0.85 * (0.6 + dens));
		float powder = 1.0 - exp(-dens * 3.0);
		float silver = pow(max(cosang, 0.0), 5.0) * (1.0 - dens * 0.7) * 2.2;
		vec3 lit_col = sun_col * cloud_lit_tint * (0.3 + 1.2 * day) + sunset_glow * sunset * 0.7 * pow(toward, 2.0);
		vec3 shade_col = mix(hor, zen, 0.45) * cloud_shadow_tint * (0.45 + 0.55 * day) + vec3(0.018, 0.022, 0.04) * night;
		// sunset paints the undersides with the horizon colour
		shade_col = mix(shade_col, sunset_horizon * 0.55, sunset * 0.45 * (1.0 - up));
		cloud_col = mix(shade_col, lit_col, lit * (0.5 + 0.5 * powder));
		cloud_col += sun_col * silver * day * lit;
		cloud_col = mix(cloud_col, cloud_col * vec3(0.32, 0.34, 0.38), storm);
		cloud_col += vec3(0.8, 0.85, 1.0) * lightning * dens * 4.5;
		float horizon_fade = smoothstep(0.005, 0.14, dir.y);
		cloud_a = clamp(dens * cloud_density, 0.0, 1.0) * horizon_fade;

		// high cirrus deck, streaked by the wind, blushing at sunset
		float ci = cirrus_field(dir.xz / (dir.y + 0.35) * 0.55 + drift * 2.5, normalize(wind_dir + vec2(1e-4)), 0.5 * (1.0 - storm)) * smoothstep(0.03, 0.4, dir.y);
		vec3 ci_col = mix(vec3(0.85, 0.9, 1.0) * (0.4 + 0.8 * day), sunset_horizon * 1.3, sunset * pow(toward, 1.5)) + sun_col * silver * 0.08 * day;
		ci_col += vec3(0.02, 0.03, 0.06) * night;
		float ci_a = ci * 0.4 * (1.0 - cloud_a * 0.7);
		cloud_col = mix(cloud_col, ci_col, ci_a / max(ci_a + cloud_a, 1e-3) * step(cloud_a, 0.999));
		cloud_a = clamp(cloud_a + ci_a, 0.0, 1.0);
	}
	col = mix(col + sun_disc, cloud_col, cloud_a);

	// rain curtains hanging under the storm cloud base near the horizon
	if (storm > 0.25) {
		float az2 = atan(dir.x, dir.z);
		float streak = texture(cloud_noise, vec2(az2 * 0.35 + TIME * 0.004, dir.y * 0.05 - TIME * 0.006)).r;
		float curt = smoothstep(0.3, 0.02, dir.y) * smoothstep(-0.02, 0.05, dir.y) * smoothstep(0.5, 0.8, streak) * 0.7;
		col = mix(col, vec3(0.32, 0.35, 0.4) * (0.4 + 0.6 * day), curt * (storm - 0.25) * 0.75);
	}
	col += vec3(0.7, 0.75, 0.9) * lightning * 0.35;

	COLOR = col * sky_energy;
}
