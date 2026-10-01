shader_type canvas_item;

// Rock body for level geometry, shared by every platform so they batch together.
// Per-platform data rides in the vertex colour: r = depth below the platform's top (0..1),
// g = random variation seed, b = platform height / 1000.
// Layers: moss rim along the top, weathered rock with organic cracks, pebbles and strata,
// darkening with depth. Overall tone follows world height so platforms always contrast with
// the backdrop (dark against the bright sky, lighter against the dark lowlands).

uniform float map_top_y = 150.0;
uniform float map_bottom_y = 650.0;
uniform vec4 high_color : source_color = vec4(0.11, 0.17, 0.155, 1.0);
uniform vec4 low_color : source_color = vec4(0.27, 0.39, 0.25, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.08, 0.07, 1.0);
uniform vec4 moss_color : source_color = vec4(0.25, 0.42, 0.22, 1.0);
uniform vec4 rock_tint : source_color = vec4(0.39, 0.38, 0.33, 1.0);
uniform vec4 warm_light : source_color = vec4(1.0, 0.78, 0.5, 1.0);
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec2 world_pos;
varying vec3 platform_data;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	platform_data = COLOR.rgb;
}

void fragment() {
	float depth = clamp(platform_data.r, 0.0, 1.0);
	float seed = platform_data.g;
	float height_px = max(platform_data.b * 1000.0, 1.0);
	float from_top = depth * height_px;

	float altitude = clamp((world_pos.y - map_top_y) / (map_bottom_y - map_top_y), 0.0, 1.0);
	vec3 base = mix(high_color.rgb, low_color.rgb, smoothstep(0.1, 0.95, altitude));
	// Weathered rock: pull the body a little towards a neutral stone tone, varied per platform.
	float stone_lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 stone = mix(vec3(stone_lum), rock_tint.rgb * (stone_lum / 0.37), 0.75);
	base = mix(base, stone, 0.5 + seed * 0.15);

	vec4 n_large = texture(noise_tex, world_pos * vec2(0.0028, 0.0055) + seed * 3.7);
	vec4 n_small = texture(noise_tex, world_pos * 0.012 + seed * 1.3);

	// Moss: a soft band hugging the top with an irregular lower edge.
	float moss_depth = 9.0 + n_large.g * 14.0;
	float moss = 1.0 - smoothstep(moss_depth - 6.0, moss_depth, from_top);
	vec3 moss_col = moss_color.rgb * (0.85 + n_small.r * 0.35);

	// Darken with depth, keep a lighter lip right under the moss.
	base = mix(base, deep_color.rgb, smoothstep(0.1, 1.0, depth) * 0.62);
	base *= 1.0 + (1.0 - smoothstep(0.0, 0.14, depth)) * 0.16;

	// Sedimentary strata.
	float strata = fract(world_pos.y * 0.052 + n_large.r * 1.7 + world_pos.x * 0.0035);
	float strata_line = smoothstep(0.86, 0.92, strata) * (1.0 - smoothstep(0.92, 1.0, strata));
	base *= 1.0 - strata_line * 0.15 * (0.4 + depth);

	// Organic cracks: thin contour lines of the noise field.
	float crack_field = n_large.b;
	float crack = 1.0 - smoothstep(0.0, 0.018, abs(crack_field - 0.5));
	crack *= smoothstep(0.35, 0.65, n_small.g);
	base *= 1.0 - crack * 0.38;

	// Pebbles and speckles.
	float pebble = smoothstep(0.79, 0.82, n_small.b) * smoothstep(0.45, 0.6, n_large.g);
	base = mix(base, base * 1.3 + vec3(0.012), pebble * 0.45);
	base *= 0.9 + n_large.r * 0.16 + (n_small.r - 0.5) * 0.08;

	// A faint warm bounce from the sunset on upper faces.
	base += warm_light.rgb * 0.035 * (1.0 - smoothstep(0.0, 0.3, depth));

	vec3 col = mix(base, moss_col, moss * 0.9);
	COLOR = vec4(col, 1.0);
}
