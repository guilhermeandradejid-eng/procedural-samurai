shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// Crescent of cut air thrown by a sword swing (Devil May Cry style): a camera-facing
// quad rolled so its chord follows the swing. It bends the image behind it like heat haze
// and carries a thin, bright leading edge; `age` (0..1) fades and thins it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform vec4 tint : source_color = vec4(0.85, 0.95, 1.0, 1.0);
uniform float age = 0.0;
uniform float roll = 0.0;
uniform float bite = 0.34;        // thickness of the crescent at its middle
uniform float bend = 0.05;        // how far the haze pushes the image (screen uv)
uniform float energy = 3.0;

void vertex() {
	vec3 sc = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	float c = cos(roll);
	float s = sin(roll);
	vec3 v = VERTEX * sc;
	VERTEX = vec3(c * v.x - s * v.y, s * v.x + c * v.y, v.z);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// a crescent is an outer disc minus a copy of itself shifted backwards
	float outer = length(p);
	float inner = length(p - vec2(0.0, -bite * (1.0 - 0.55 * age)));
	float m = smoothstep(1.0, 0.93, outer) * smoothstep(1.0, 1.07, inner);
	float rim = smoothstep(0.80, 0.965, outer) * (1.0 - smoothstep(0.965, 1.0, outer));
	float fade = (1.0 - age) * (1.0 - age) * smoothstep(0.0, 0.06, age + 0.06);
	vec2 dir = normalize(p + vec2(1e-4));
	vec2 uv = SCREEN_UV + dir * bend * m * (1.0 - age);
	vec3 bg = texture(screen_tex, uv).rgb;
	vec3 col = mix(bg, tint.rgb * energy, clamp(rim * 0.95 + m * 0.12, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(m * fade * 1.15, 0.0, 1.0);
}
