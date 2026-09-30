shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

// Ghost of a moving character (afterimage): a soft coloured silhouette that is
// brightest at the rim, so a dash leaves a trail of translucent copies.

uniform vec4 tint : source_color = vec4(0.55, 0.8, 1.0, 1.0);
uniform float alpha = 0.6;

void fragment() {
	float fres = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.0);
	ALBEDO = tint.rgb * (0.35 + 1.6 * fres);
	ALPHA = alpha * (0.3 + 0.7 * fres);
}
