shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, skip_vertex_transform;

// Rain streaks and splash droplets for GPU particles. Every quad is stretched
// along the particle's velocity (the particle basis Y axis, see
// ParticleProcessMaterial.particle_flag_align_y) and turned to face the camera
// around that axis, like a motion-blurred drop. Streaks never get thinner than
// about a pixel (their opacity drops instead, so distant rain stays a fine
// haze), fade out close to the lens and with distance, and pick up the colour
// of the fog / the glow of the sun when seen against it.

global uniform vec3 fog_color;
global uniform vec3 sun_color;
global uniform vec3 sun_dir;

uniform float streak_length = 0.55;
uniform float streak_width = 0.008;
uniform float opacity = 0.35;
uniform float min_pixels = 1.1;
uniform float near_fade = 1.4;
uniform float far_fade = 40.0;

varying float v_alpha;
varying vec3 v_tint;

float hash11(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

void vertex() {
	vec3 center = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[1].xyz;
	float al = length(axis);
	axis = al > 1e-5 ? axis / al : vec3(0.0, -1.0, 0.0);
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 to_cam = cam - center;
	float dist = max(length(to_cam), 1e-3);
	to_cam /= dist;
	vec3 side = cross(axis, to_cam);
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : vec3(1.0, 0.0, 0.0);
	float id = float(INSTANCE_ID);
	float r1 = hash11(id);
	float r2 = hash11(id + 3.7);
	float px = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y) * dist;
	float true_w = streak_width * (0.6 + 0.8 * r1);
	float w = max(true_w, px * min_pixels);
	float len = streak_length * (0.55 + 0.9 * r2);
	vec3 wp = center + side * VERTEX.x * w + axis * VERTEX.y * len;
	VERTEX = (VIEW_MATRIX * vec4(wp, 1.0)).xyz;
	NORMAL = vec3(0.0, 0.0, 1.0);

	float nearf = smoothstep(near_fade * 0.4, near_fade, dist);
	float farf = 1.0 - smoothstep(far_fade * 0.55, far_fade, dist);
	float coverage = clamp(true_w / w, 0.0, 1.0);
	v_alpha = opacity * nearf * farf * (0.5 + 0.5 * r2) * coverage * COLOR.a;

	// lit by the sky: fog colour, brighter when the sun shines through it
	vec3 vdir = -to_cam;
	float fs = pow(max(dot(vdir, sun_dir), 0.0), 5.0);
	v_tint = mix(fog_color, vec3(1.0), 0.4) * 0.95 + sun_color * fs * 0.5 + vec3(0.05, 0.06, 0.09);
}

void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	across = smoothstep(0.0, 0.9, across);
	// UV.y = 0 is the leading end (soft tip), the tail fades out slowly
	float along = smoothstep(0.0, 0.14, UV.y) * pow(clamp(1.0 - UV.y, 0.0, 1.0), 0.75);
	ALBEDO = v_tint;
	ALPHA = clamp(v_alpha * across * along, 0.0, 1.0);
}
