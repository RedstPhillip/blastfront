shader_type canvas_item;

// Glassy ice for Rimefall's ice surfaces (the lake, the floes, the arch), unmistakably different from the
// matte snow on rock: clear blue body that deepens towards the bottom, white fracture lines and trapped
// bubbles inside, a bright polished top edge, and a slow glint that sweeps along the surface.
// Vertex colour carries r = depth below the body's top (0..1) and g = a per-body seed.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 surface_color : source_color = vec4(0.78, 0.93, 1.0, 1.0);
uniform vec4 body_color : source_color = vec4(0.36, 0.62, 0.86, 1.0);
uniform vec4 deep_color : source_color = vec4(0.1, 0.2, 0.42, 1.0);
uniform vec4 crack_color : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform float glint_speed = 0.06;

varying vec2 world_pos;
varying vec2 body_data;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	body_data = COLOR.rg;
}

void fragment() {
	float depth = clamp(body_data.r, 0.0, 1.0);
	float seed = body_data.g;
	vec4 n_large = texture(noise_tex, world_pos * vec2(0.003, 0.006) + seed * 3.1);
	vec4 n_fine = texture(noise_tex, world_pos * 0.02 + seed * 1.7);
	vec3 col = mix(surface_color.rgb, body_color.rgb, smoothstep(0.0, 0.35, depth));
	col = mix(col, deep_color.rgb, smoothstep(0.35, 1.0, depth));
	// Layers of clear and milky ice.
	col *= 0.92 + 0.12 * sin(world_pos.y * 0.21 + n_large.r * 5.0);
	// Fracture lines: thin contours of the noise field, brightest just under the surface.
	float crack = 1.0 - smoothstep(0.0, 0.016, abs(n_large.b - 0.5));
	crack *= smoothstep(0.4, 0.62, n_fine.g);
	col = mix(col, crack_color.rgb, crack * 0.55 * (1.0 - depth * 0.5));
	// Trapped bubbles.
	float bubble = smoothstep(0.83, 0.86, n_fine.b) * smoothstep(0.2, 0.5, depth);
	col = mix(col, crack_color.rgb, bubble * 0.35);
	// A glint sweeping slowly along the ice: diagonal bands of light, one wide and one narrow.
	float sweep = fract(world_pos.x * 0.0016 - world_pos.y * 0.0016 - TIME * glint_speed + seed);
	float glint = exp(-pow((sweep - 0.5) * 18.0, 2.0)) + 0.5 * exp(-pow((sweep - 0.56) * 60.0, 2.0));
	col += vec3(0.85, 0.95, 1.0) * glint * 0.32 * (1.0 - depth * 0.6);
	COLOR = vec4(col, 1.0);
}
