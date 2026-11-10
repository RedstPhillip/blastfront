shader_type canvas_item;

// Rock body for level geometry, shared by every platform so they batch together.
// Per-platform data rides in the vertex colour: r = depth below the platform's top (0..1),
// g = random variation seed, b = platform height / 1000.
// The rock lies in uneven beds: each bed has its own tone, a dark seam along its top with a lit lip under
// it, and is broken by upright joints into blocks that differ a little from their neighbours. Over that:
// organic cracks, embedded stones, grain, and growth creeping down from the top (moss on Verdant, dust on
// Mars, rime on Rimefall: `growth_color`, its alpha is the strength). The topsoil on walkable edges is a
// separate band (soil.gdshader) so it has the same depth on every ledge. Overall tone follows world
// height so platforms always contrast with the backdrop (dark against the bright sky, lighter against the
// dark lowlands).

uniform float map_top_y = 150.0;
uniform float map_bottom_y = 650.0;
uniform vec4 high_color : source_color = vec4(0.11, 0.17, 0.155, 1.0);
uniform vec4 low_color : source_color = vec4(0.27, 0.39, 0.25, 1.0);
uniform vec4 deep_color : source_color = vec4(0.05, 0.08, 0.07, 1.0);
uniform vec4 rock_tint : source_color = vec4(0.39, 0.38, 0.33, 1.0);
uniform vec4 warm_light : source_color = vec4(1.0, 0.78, 0.5, 1.0);
uniform vec4 growth_color : source_color = vec4(0.2, 0.36, 0.19, 0.42);
uniform float strata_strength = 0.15;
uniform float layer_contrast = 0.0;
uniform float warm_strength = 0.035;
uniform float crack_strength = 0.38;
uniform float bed_height = 31.0;
uniform float bed_contrast = 0.2;
uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;

varying vec2 world_pos;
varying vec3 platform_data;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	platform_data = COLOR.rgb;
}

void fragment() {
	float depth = clamp(platform_data.r, 0.0, 1.0);
	float seed = platform_data.g;
	float depth_px = depth * max(platform_data.b * 1000.0, 1.0);

	float altitude = clamp((world_pos.y - map_top_y) / (map_bottom_y - map_top_y), 0.0, 1.0);
	vec3 base = mix(high_color.rgb, low_color.rgb, smoothstep(0.1, 0.95, altitude));
	// Weathered rock: pull the body a little towards a neutral stone tone, varied per platform.
	float stone_lum = dot(base, vec3(0.299, 0.587, 0.114));
	vec3 stone = mix(vec3(stone_lum), rock_tint.rgb * (stone_lum / 0.37), 0.75);
	base = mix(base, stone, 0.5 + seed * 0.15);

	vec4 n_large = texture(noise_tex, world_pos * vec2(0.0028, 0.0055) + seed * 3.7);
	vec4 n_small = texture(noise_tex, world_pos * 0.012 + seed * 1.3);
	vec4 n_fine = texture(noise_tex, world_pos * 0.047 + seed * 0.7);

	// Darken with depth.
	base = mix(base, deep_color.rgb, smoothstep(0.1, 1.0, depth) * 0.62);

	// Beds: warped level layers of differing thickness and tone.
	float warp = n_large.r * 30.0 + sin(world_pos.x * 0.0061 + seed * 9.0) * 8.0;
	float bed_pos = (world_pos.y + warp) / bed_height;
	float bed = floor(bed_pos);
	float in_bed = fract(bed_pos);
	float bed_tone = hash(vec2(bed, floor(seed * 57.0)));
	base *= 1.0 + (bed_tone - 0.5) * bed_contrast;
	float seam = 1.0 - smoothstep(0.0, 0.06 + n_small.r * 0.05, in_bed);
	float lip = smoothstep(0.08, 0.14, in_bed) * (1.0 - smoothstep(0.14, 0.36, in_bed));
	base *= 1.0 - seam * strata_strength * 2.0 * (0.55 + depth * 0.45);
	base *= 1.0 + lip * 0.07;
	// Joints: each bed is broken upright into blocks of its own length, every block a shade apart.
	float block_pos = (world_pos.x + n_small.g * 7.0) / (bed_height * (1.8 + bed_tone * 2.6)) + bed_tone * 13.0;
	float block = hash(vec2(floor(block_pos), bed));
	float to_joint = abs(fract(block_pos) - 0.5) * 2.0;
	float joint = smoothstep(0.955, 0.985, to_joint) * step(0.3, block) * (1.0 - seam);
	base *= 1.0 + (block - 0.5) * bed_contrast * 0.55;
	base *= 1.0 - joint * strata_strength * 1.5;
	// Broad sediment layers (used by desert rock; zero on the mossy world).
	float layers = sin(world_pos.y * 0.085 + n_large.r * 2.4 + sin(world_pos.x * 0.004) * 1.5) * 0.5 + 0.5;
	base *= 1.0 + (layers - 0.5) * layer_contrast;

	// Organic cracks: thin contour lines of the noise field, with a faint lit edge beside each.
	float crack_field = n_large.b;
	float crack_mask = smoothstep(0.35, 0.65, n_small.g);
	float crack = (1.0 - smoothstep(0.0, 0.018, abs(crack_field - 0.5))) * crack_mask;
	float crack_edge = (1.0 - smoothstep(0.0, 0.02, abs(crack_field - 0.53))) * crack_mask;
	base *= 1.0 - crack * crack_strength;
	base *= 1.0 + crack_edge * crack_strength * 0.16;

	// Embedded stones with a lit crown, and the grain of the rock.
	float pebble = smoothstep(0.79, 0.82, n_small.b) * smoothstep(0.45, 0.6, n_large.g);
	float crown = smoothstep(0.82, 0.9, n_small.b) * smoothstep(0.45, 0.6, n_large.g);
	base = mix(base, base * 1.3 + vec3(0.012), pebble * 0.45);
	base *= 1.0 + crown * 0.12;
	base *= 0.88 + n_large.r * 0.17 + (n_small.r - 0.5) * 0.1 + (n_fine.r - 0.5) * 0.11;
	// Pits: small dark specks where the surface has spalled.
	base *= 1.0 - smoothstep(0.8, 0.86, n_fine.g) * smoothstep(0.5, 0.7, n_small.r) * 0.2;

	// Growth creeping down from the top and settling into the seams near it.
	float near_top = 1.0 - smoothstep(6.0, 64.0, depth_px);
	float growth = smoothstep(0.5, 0.78, n_large.g * 0.6 + n_small.g * 0.4 + near_top * 0.3 + seam * 0.14) * near_top;
	base = mix(base, growth_color.rgb * (0.75 + n_fine.b * 0.5), growth * growth_color.a);

	// A faint warm bounce from the sky on upper faces.
	base += warm_light.rgb * warm_strength * (1.0 - smoothstep(0.0, 0.3, depth));

	COLOR = vec4(base, 1.0);
}
