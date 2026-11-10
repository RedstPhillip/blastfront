shader_type canvas_item;

// Temple masonry for Tidewater's terrain, shared by every body so they batch: courses of dressed stone
// blocks with worn joints, each block its own tone, a few cracked or sunken ones, weathering streaks and
// cracks across them. The sea has left its marks: below the flood line the stone is stained green with
// algae and crusted with barnacles along the line itself, a fainter mark sits at the spring-tide line,
// and whatever the water covered last (`wet_line`, set by the skin) stays dark and glistening.
// Vertex colour carries r = depth below the body's top (0..1) and g = a per-body seed.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 stone_color : source_color = vec4(0.4, 0.47, 0.46, 1.0);
uniform vec4 stone_dark : source_color = vec4(0.17, 0.225, 0.24, 1.0);
uniform vec4 deep_color : source_color = vec4(0.03, 0.06, 0.07, 1.0);
uniform vec4 algae_color : source_color = vec4(0.1, 0.27, 0.2, 1.0);
uniform vec4 crust_color : source_color = vec4(0.62, 0.72, 0.66, 1.0);
uniform vec4 moon_color : source_color = vec4(0.7, 0.92, 1.0, 1.0);
uniform float course_height = 27.0;
uniform float block_width = 62.0;
uniform float flood_y = 600.0;
uniform float spring_y = 506.0;
uniform float wet_line = 100000.0;

varying vec2 world_pos;
varying vec2 body_data;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	body_data = COLOR.rg;
}

void fragment() {
	float depth = clamp(body_data.r, 0.0, 1.0);
	float seed = body_data.g;
	vec4 n_large = texture(noise_tex, world_pos * vec2(0.003, 0.0052) + seed * 3.7);
	vec4 n_small = texture(noise_tex, world_pos * 0.013 + seed * 1.3);

	// Courses run level through the whole map; block lengths differ from course to course and every other
	// course is shifted half a block.
	float row = floor(world_pos.y / course_height);
	float row_seed = hash(vec2(row, 5.0));
	float width = block_width * (0.75 + 0.6 * row_seed);
	float along = world_pos.x / width + row_seed * 7.0 + mod(row, 2.0) * 0.5;
	float column = floor(along);
	float block = hash(vec2(column, row));
	float fx = fract(along) * width;
	float fy = fract(world_pos.y / course_height) * course_height;
	float edge = min(min(fx, width - fx), min(fy, course_height - fy));
	// Worn joints: wider and more ragged where the noise says the stone has crumbled.
	float joint = 1.0 - smoothstep(0.5, 1.7 + n_small.r * 1.4, edge);

	vec3 base = mix(stone_dark.rgb, stone_color.rgb, 0.3 + block * 0.55);
	base *= 0.84 + n_large.r * 0.24 + (n_small.r - 0.5) * 0.12;
	// A few blocks have sunk back or lost their face.
	base *= 1.0 - step(0.88, block) * 0.2;
	// Chisel light: the upper edge of each block catches the moon, the lower edge sits in shadow.
	base += moon_color.rgb * 0.045 * (1.0 - smoothstep(1.0, 4.5, fy)) * (1.0 - joint);
	base *= 1.0 - (1.0 - smoothstep(1.0, 5.0, course_height - fy)) * 0.14;
	// Rain streaks running down from the joints and hairline cracks across the blocks.
	float streak = texture(noise_tex, vec2(world_pos.x * 0.035, world_pos.y * 0.0035) + seed).g;
	base *= 1.0 - smoothstep(0.58, 0.8, streak) * 0.16;
	float crack = (1.0 - smoothstep(0.0, 0.013, abs(n_large.b - 0.5))) * smoothstep(0.5, 0.72, n_small.g);
	base *= 1.0 - crack * 0.34;
	base = mix(base, stone_dark.rgb * 0.42, joint * 0.85);
	// Moss creeping out of the joints high on the walls.
	float moss = joint * smoothstep(0.45, 0.7, n_large.g) * (1.0 - smoothstep(0.0, 0.5, depth));
	base = mix(base, algae_color.rgb * 1.5, moss * 0.6);

	base = mix(base, deep_color.rgb, smoothstep(0.12, 1.0, depth) * 0.58);
	base += moon_color.rgb * 0.03 * (1.0 - smoothstep(0.0, 0.25, depth));

	// What the sea left: algae below the flood line, barnacles along it, a faint second mark higher up.
	float ragged = (n_small.g - 0.5) * 14.0 + (n_large.r - 0.5) * 10.0;
	float stained = smoothstep(flood_y - 6.0, flood_y + 22.0, world_pos.y + ragged);
	base = mix(base, base * 0.62 + algae_color.rgb * 0.5, stained * 0.62);
	float crust = exp(-pow((world_pos.y + ragged * 0.5 - flood_y) / 6.0, 2.0)) * smoothstep(0.62, 0.74, n_small.b);
	base = mix(base, crust_color.rgb, crust * 0.5);
	float spring_mark = exp(-pow((world_pos.y + ragged * 0.4 - spring_y) / 4.0, 2.0));
	base = mix(base, base * 0.8 + algae_color.rgb * 0.16, spring_mark * 0.5);

	// Wet stone: darker, cooler, with glints that crawl as the film of water runs off.
	float wet = smoothstep(wet_line - 2.0, wet_line + 7.0, world_pos.y);
	if (wet > 0.0) {
		float glint = texture(noise_tex, world_pos * 0.02 + vec2(0.0, -TIME * 0.02)).b;
		base = mix(base, base * vec3(0.6, 0.68, 0.72), wet);
		base += moon_color.rgb * smoothstep(0.7, 0.82, glint) * 0.1 * wet * (1.0 - joint);
	}

	COLOR = vec4(base, 1.0);
}
