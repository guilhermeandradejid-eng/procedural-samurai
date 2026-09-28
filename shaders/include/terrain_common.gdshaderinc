// Shared helpers for every shader that needs to know about the terrain.
// The world textures are bound once as global shader uniforms by WorldData.

global uniform sampler2D terrain_height;
global uniform sampler2D terrain_normal;
global uniform sampler2D terrain_splat;
global uniform sampler2D terrain_veg;
global uniform vec4 terrain_info; // x: samples per side, y: spacing (m), z: half extent (m), w: sea level

// Height with the same triangulation as the physics heightfield (and
// WorldData.get_height), so meshes, grass and particles sit exactly on the
// collision surface.
float terrain_height_at(vec2 xz) {
	float n = terrain_info.x;
	vec2 f = xz / terrain_info.y + vec2((n - 1.0) * 0.5);
	f = clamp(f, vec2(0.0), vec2(n - 1.001));
	ivec2 i = ivec2(floor(f));
	vec2 t = f - vec2(i);
	float a = texelFetch(terrain_height, i, 0).r;
	float b = texelFetch(terrain_height, i + ivec2(1, 0), 0).r;
	float c = texelFetch(terrain_height, i + ivec2(0, 1), 0).r;
	if (t.x + t.y <= 1.0) {
		return a + (b - a) * t.x + (c - a) * t.y;
	}
	float d = texelFetch(terrain_height, i + ivec2(1, 1), 0).r;
	return d + (c - d) * (1.0 - t.x) + (b - d) * (1.0 - t.y);
}

// UV that maps texel centres of the world maps to sample positions.
vec2 terrain_uv(vec2 xz) {
	float n = terrain_info.x;
	return (xz / terrain_info.y + vec2((n - 1.0) * 0.5) + 0.5) / n;
}

vec3 terrain_normal_at(vec2 xz) {
	vec3 e = textureLod(terrain_normal, terrain_uv(xz), 0.0).rgb;
	return normalize(vec3(e.r * 2.0 - 1.0, e.b, e.g * 2.0 - 1.0));
}

vec4 terrain_splat_at(vec2 xz) {
	return textureLod(terrain_splat, terrain_uv(xz), 0.0);
}

vec4 terrain_veg_at(vec2 xz) {
	return textureLod(terrain_veg, terrain_uv(xz), 0.0);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}
