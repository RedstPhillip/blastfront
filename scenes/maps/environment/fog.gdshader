shader_type canvas_item;
render_mode unshaded, blend_mix;

// Drifting fog band. Soft vertical falloff at both edges; two scrolling layers of a baked, tileable
// fbm texture give the slow billowing motion at the cost of two texture reads per pixel.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 fog_color : source_color = vec4(0.72, 0.86, 0.76, 1.0);
uniform float density = 0.22;
uniform float speed = 0.012;
uniform float scale = 1.0;
uniform float top_softness = 0.45;
uniform float bottom_softness = 0.2;

const float TILE_UNITS = 4.5;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec2 p = local_px * 0.004 * scale / TILE_UNITS;
	float drift = TIME * speed / TILE_UNITS;
	float n = texture(noise_tex, p + vec2(drift * 10.0, 0.0)).r;
	float n2 = texture(noise_tex, p * 1.7 - vec2(drift * 6.0, drift * 2.0)).g;
	float vertical = smoothstep(0.0, top_softness, UV.y) * (1.0 - smoothstep(1.0 - bottom_softness, 1.0, UV.y));
	float alpha = clamp((n * 0.65 + n2 * 0.55) - 0.25, 0.0, 1.0) * vertical * density;
	COLOR = vec4(fog_color.rgb, alpha);
}
