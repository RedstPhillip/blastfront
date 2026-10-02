shader_type canvas_item;
render_mode blend_add, unshaded;

// Survey beacon light: short bright pulse with a soft afterglow, phase-shifted per beacon by position so
// they never blink in sync.

uniform float period = 1.8;
uniform float duty = 0.12;

varying float phase_seed;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	phase_seed = fract(sin(dot(floor(world), vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float phase = fract(TIME / period + phase_seed);
	float pulse = 1.0 - smoothstep(0.0, duty, phase);
	float glow = 0.12 + pulse * 0.88;
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(COLOR.rgb * tex.rgb, tex.a * COLOR.a * glow);
}
