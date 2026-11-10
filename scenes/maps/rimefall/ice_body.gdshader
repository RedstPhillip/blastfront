shader_type canvas_item;

// Glassy ice for Rimefall's ice surfaces (the lake, the floes, the arch), unmistakably different from the
// matte snow on rock. Read from the top down: a frosted white skin, a band of pale ice the moon shines
// into, then clear ice darkening to deep blue. Inside it: fracture planes that run steeply through the
// body, strings of bubbles frozen on their way up, faint growth layers, and a slow glint along the top.
// Vertex colour carries r = depth below the body's top (0..1), g = a per-body seed, b = body height / 1000.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 frost_color : source_color = vec4(0.86, 0.95, 1.0, 1.0);
uniform vec4 surface_color : source_color = vec4(0.5, 0.76, 0.95, 1.0);
uniform vec4 body_color : source_color = vec4(0.15, 0.35, 0.6, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.075, 0.2, 1.0);
uniform vec4 crack_color : source_color = vec4(0.88, 0.97, 1.0, 1.0);
uniform float glint_speed = 0.05;

varying vec2 world_pos;
varying vec3 body_data;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	body_data = COLOR.rgb;
}

void fragment() {
	float seed = body_data.g;
	float height = max(body_data.b * 1000.0, 1.0);
	float depth = clamp(body_data.r, 0.0, 1.0) * height;
	vec4 n_large = texture(noise_tex, world_pos * vec2(0.0042, 0.0016) + seed * 3.1);
	vec4 n_fine = texture(noise_tex, world_pos * 0.021 + seed * 1.7);

	// Body: pale under the surface, deep blue further down (thin floes never get that far).
	vec3 col = mix(surface_color.rgb, body_color.rgb, smoothstep(2.0, 46.0, depth));
	col = mix(col, deep_color.rgb, smoothstep(40.0, 230.0, depth));
	// Growth layers: faint level bands, a little uneven.
	float layer = sin((world_pos.y + n_large.g * 9.0) * 0.36);
	col *= 1.0 + smoothstep(0.75, 1.0, layer) * 0.07 - smoothstep(0.8, 1.0, -layer) * 0.05;
	// Moonlight sinking in from the top.
	col += surface_color.rgb * 0.16 * exp(-depth / 34.0);

	// Fracture planes: thin bright contours of a field stretched upright, each with a milky sheet on one
	// side; strongest near the top.
	float field = n_large.b + (n_fine.r - 0.5) * 0.05;
	float plane = 1.0 - smoothstep(0.0, 0.012, abs(field - 0.5));
	float sheet = smoothstep(0.5, 0.56, field) * (1.0 - smoothstep(0.56, 0.66, field));
	float reach = 1.0 - smoothstep(30.0, 240.0, depth) * 0.75;
	col = mix(col, crack_color.rgb, plane * 0.6 * reach * smoothstep(0.3, 0.5, n_large.r));
	col += crack_color.rgb * sheet * 0.055 * reach;
	// Hairline cracks.
	float hair = (1.0 - smoothstep(0.0, 0.02, abs(n_fine.g - 0.5))) * smoothstep(0.62, 0.8, n_large.g);
	col = mix(col, crack_color.rgb, hair * 0.28 * reach);

	// Bubble strings: every few px a column, each with beads at its own spacing, fading with depth.
	float column = floor(world_pos.x / 17.0);
	float ch = hash(vec2(column, floor(seed * 91.0)));
	if (ch > 0.62 && depth > 9.0) {
		float spacing = 7.0 + ch * 9.0;
		float cx = (column + 0.2 + hash(vec2(column, 3.0)) * 0.6) * 17.0;
		float bead_index = floor(world_pos.y / spacing);
		float bh = hash(vec2(column, bead_index));
		vec2 bead = vec2(cx + (bh - 0.5) * 3.0, (bead_index + 0.5) * spacing);
		float radius = 0.7 + bh * 1.5;
		float d = length(world_pos - bead);
		float ring = (1.0 - smoothstep(radius - 0.5, radius + 0.6, d)) * step(bh, 0.7);
		float top = hash(vec2(column, 11.0)) * height * 0.5;
		col = mix(col, crack_color.rgb, ring * 0.5 * smoothstep(top, top + 14.0, depth) * (1.0 - smoothstep(60.0, 200.0, depth)));
	}

	// The skin: frost on top, with snow dust blown into it.
	float frost = 1.0 - smoothstep(1.5, 6.0 + n_fine.b * 4.0, depth);
	col = mix(col, frost_color.rgb, frost * 0.85);
	// A glint sweeping slowly along the surface.
	float sweep = fract(world_pos.x * 0.0015 - world_pos.y * 0.0015 - TIME * glint_speed + seed);
	float glint = exp(-pow((sweep - 0.5) * 16.0, 2.0)) + 0.5 * exp(-pow((sweep - 0.57) * 60.0, 2.0));
	col += vec3(0.85, 0.95, 1.0) * glint * 0.22 * exp(-depth / 60.0);
	COLOR = vec4(col, 1.0);
}
