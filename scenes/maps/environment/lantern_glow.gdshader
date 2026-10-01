shader_type canvas_item;
render_mode blend_add, unshaded;

// Warm lantern halo: candle-like flicker driven entirely on the GPU. Each lantern's world position
// offsets its phase, so neighbours never pulse in sync.

varying float phase;

void vertex() {
	vec2 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
	phase = origin.x * 0.37 + origin.y * 0.11;
}

void fragment() {
	float t = TIME + phase;
	float flicker = 0.86 + 0.08 * sin(t * 7.3) + 0.05 * sin(t * 13.1 + 1.7) + 0.03 * sin(t * 23.0 + 0.4);
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(tex.rgb * COLOR.rgb, tex.a * COLOR.a * flicker);
}
