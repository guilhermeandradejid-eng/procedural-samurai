shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled, fog_disabled;

// Overlay for the sword-swing ribbon: instead of adding light it shimmers the picture
// behind the swing, as if the blade were tearing the air open. UV.x runs along the
// ribbon, UV.y from the inner edge (0) to the blade tip (1); vertex alpha fades it.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float bend = 0.022;

void fragment() {
	float a = COLOR.a * smoothstep(0.0, 0.35, UV.y);
	vec2 wob = vec2(sin(UV.x * 38.0 - TIME * 34.0), cos(UV.x * 27.0 + TIME * 29.0));
	vec2 off = (wob * 0.6 + vec2(0.0, UV.y - 0.6)) * bend * a;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = clamp(a * 1.5, 0.0, 0.9);
}
