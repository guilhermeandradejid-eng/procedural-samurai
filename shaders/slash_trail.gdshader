shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// Additive sword trail. Vertex colour alpha fades along the ribbon; the
// texture gives a bright core toward the blade tip.

uniform sampler2D trail_tex : filter_linear;
uniform vec4 tint : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform float energy = 2.2;

void fragment() {
	vec4 t = texture(trail_tex, vec2(UV.x, UV.y));
	float edge = smoothstep(0.0, 0.35, UV.y);
	float a = COLOR.a * edge * (0.35 + 0.65 * UV.y);
	ALBEDO = tint.rgb * COLOR.rgb * energy * a;
	ALPHA = a;
}
