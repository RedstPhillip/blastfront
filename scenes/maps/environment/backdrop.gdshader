shader_type canvas_item;
render_mode unshaded;

// Painted backdrop: fades its top edge into the sky and adds gentle animated light haze near the horizon.

uniform vec4 sky_color : source_color = vec4(0.149, 0.306, 0.275, 1.0);
uniform float top_fade = 0.12;
uniform float haze_strength = 0.1;
uniform float horizon = 0.42;

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float fade = smoothstep(0.0, top_fade, UV.y);
	vec3 col = mix(sky_color.rgb, tex.rgb, fade);
	float haze = exp(-pow((UV.y - horizon) * 7.0, 2.0));
	haze *= 0.75 + 0.25 * sin(TIME * 0.35 + UV.x * 6.0);
	col += vec3(0.75, 0.95, 0.8) * haze * haze_strength;
	COLOR = vec4(col, tex.a);
}
