// Shared bits for character materials (skin, cloth, armour): per-instance
// blood stains around the last hit, spatter that grows with damage, a hit
// flash and wetness. Positions are in the part's local (model) space.

instance uniform float blood_amount = 0.0;
instance uniform vec4 blood_hit = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float hit_flash = 0.0;
instance uniform vec4 flash_color = vec4(1.0, 0.35, 0.25, 1.0);

global uniform float wetness;

varying vec3 v_local;
varying vec3 v_local_n;

float hash31(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float noise3(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(i);
	float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
			mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

float blood_mask(vec3 p) {
	if (blood_amount <= 0.001 && blood_hit.w <= 0.001) {
		return 0.0;
	}
	float n = noise3(p * 16.0) * 0.6 + noise3(p * 47.0) * 0.4;
	float d = length(p - blood_hit.xyz);
	float near_hit = (1.0 - smoothstep(blood_hit.w * 0.25, blood_hit.w, d + (n - 0.5) * blood_hit.w * 0.9)) * step(0.001, blood_hit.w);
	// drips run downwards from the wound
	float drip = step(0.72, noise3(vec3(p.x * 60.0, 0.0, p.z * 60.0))) * smoothstep(blood_hit.w * 2.5, 0.0, abs(p.x - blood_hit.x) + abs(p.z - blood_hit.z) * 0.5)
			* step(p.y, blood_hit.y) * smoothstep(blood_hit.w * 4.0, 0.0, blood_hit.y - p.y) * step(0.001, blood_hit.w);
	float spatter = smoothstep(1.0 - blood_amount * 0.55, 1.0 - blood_amount * 0.55 + 0.06, n);
	return clamp(max(max(near_hit, drip * 0.9), spatter), 0.0, 1.0);
}

void apply_character_fx(inout vec3 albedo, inout float rough, inout vec3 emission) {
	float m = blood_mask(v_local);
	vec3 blood_col = mix(vec3(0.33, 0.015, 0.015), vec3(0.18, 0.01, 0.01), noise3(v_local * 30.0));
	albedo = mix(albedo, blood_col, m);
	rough = mix(rough, 0.22, m);
	albedo *= mix(1.0, 0.75, wetness);
	rough = mix(rough, rough * 0.5, wetness);
	emission += flash_color.rgb * hit_flash * 1.5;
}
