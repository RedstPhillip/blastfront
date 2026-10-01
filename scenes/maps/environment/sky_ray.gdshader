shader_type canvas_item;
render_mode blend_add, unshaded;

// Soft light shaft; each ray slowly breathes and shimmers along its length.

varying float seed;

void vertex() {
	seed = dot(MODEL_MATRIX[0].xy, vec2(13.1, 7.7));
}

void fragment() {
	float breathe = 0.65 + 0.35 * sin(TIME * 0.23 + seed * 3.0);
	float shimmer = 0.85 + 0.15 * sin(UV.y * 9.0 - TIME * 0.6 + seed);
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(COLOR.rgb, tex.a * COLOR.a * breathe * shimmer);
}
