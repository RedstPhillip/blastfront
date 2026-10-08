shader_type canvas_item;
render_mode unshaded, blend_add;

// The tide line: a glowing dashed mark across the ruins at the height the coming flood will reach, shown
// while it is announced and fading as the water arrives. The rect is centred on that height.

uniform vec4 line_color : source_color = vec4(0.45, 1.0, 0.92, 1.0);
uniform float strength = 0.0;

varying vec2 world_px;

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float d = abs(UV.y - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.1, 0.24, d);
	float glow = exp(-d * 3.0) * 0.55;
	float dash = step(0.38, fract(world_px.x / 26.0 - TIME * 0.6));
	float pulse = 0.75 + 0.25 * sin(TIME * 6.0);
	float a = (core * dash + glow) * strength * pulse;
	COLOR = vec4(line_color.rgb * a, a);
}
