shader_type canvas_item;

// Topsoil band that hugs every walkable top edge with the same depth everywhere: flat ledges, slopes,
// lower steps and chamfered corners alike. UV.x carries the distance (px) below the surface, so the
// band can end in an irregular, noise-driven lower edge with a soft contact shadow on the rock.
// From the surface down: a mat of turf (`turf_depth` px of top_color, ragged underneath), then earth
// (earth_color darkening to deep_color) with darker lenses of humus, fine roots hanging out of the turf
// and stones bedded in the lower half. Worlds without turf (dust, snow) set turf_depth and root_strength
// to 0 and get a plain graded band with stones.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 top_color : source_color = vec4(0.29, 0.47, 0.25, 1.0);
uniform vec4 earth_color : source_color = vec4(0.25, 0.22, 0.13, 1.0);
uniform vec4 deep_color : source_color = vec4(0.13, 0.19, 0.12, 1.0);
uniform vec4 fleck_color : source_color = vec4(0.42, 0.36, 0.24, 1.0);
uniform vec4 root_color : source_color = vec4(0.5, 0.45, 0.3, 1.0);
uniform float base_depth = 9.0;
uniform float depth_variation = 4.0;
uniform float turf_depth = 0.0;
uniform float root_strength = 0.0;
uniform float shadow_depth = 5.0;
uniform float shadow_strength = 0.32;

varying vec2 world_pos;
varying float surface_dist;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	surface_dist = UV.x;
}

void fragment() {
	vec4 n_wide = texture(noise_tex, world_pos * vec2(0.0045, 0.009));
	vec4 n_fine = texture(noise_tex, world_pos * 0.035);
	float depth = base_depth + (n_wide.g - 0.5) * 2.0 * depth_variation + (n_fine.r - 0.5) * 2.4;
	float aa = max(fwidth(surface_dist), 0.6);
	float inside = 1.0 - smoothstep(depth - aa, depth + aa, surface_dist);

	float t = clamp(surface_dist / max(depth, 1.0), 0.0, 1.0);
	vec3 col = mix(earth_color.rgb, deep_color.rgb, smoothstep(0.1, 1.0, t));
	col *= 0.84 + n_fine.b * 0.3;
	// Lenses of darker humus lying level in the earth.
	col *= 1.0 - smoothstep(0.55, 0.75, n_wide.r) * smoothstep(0.2, 0.5, t) * 0.18;

	// Stones bedded in the lower half: one per cell at most, each with a lit top.
	vec2 cell = floor(world_pos / 7.0);
	float stone_seed = hash(cell);
	if (stone_seed > 0.87) {
		vec2 center = (cell + 0.3 + 0.4 * vec2(hash(cell + 3.1), hash(cell + 9.7))) * 7.0;
		vec2 d = (world_pos - center) / vec2(0.9 + stone_seed * 1.3, 0.7 + stone_seed * 0.8);
		float stone = (1.0 - smoothstep(0.7, 1.0, length(d))) * smoothstep(0.3, 0.55, t);
		vec3 stone_col = fleck_color.rgb * (0.8 + 0.5 * hash(cell + 5.3)) * (1.0 - d.y * 0.22);
		col = mix(col, stone_col, stone * 0.8);
	}

	// Turf: a mat of top_color with a ragged underside, and fine roots hanging out of it.
	float turf_edge = turf_depth + (n_fine.g - 0.5) * 3.2;
	float turf = (1.0 - smoothstep(turf_edge - 0.8, turf_edge + 0.8, surface_dist)) * step(0.01, turf_depth);
	if (root_strength > 0.0) {
		float column = floor(world_pos.x / 4.0);
		float rh = hash(vec2(column, 1.0));
		float reach = turf_edge + rh * depth * 0.75;
		float wiggle = sin(surface_dist * 0.7 + rh * 30.0) * 0.9;
		float across = abs((fract(world_pos.x / 4.0) - 0.5) * 4.0 - wiggle);
		float root = (1.0 - smoothstep(0.2, 0.55, across)) * step(1.0 - root_strength * 0.3, rh);
		root *= smoothstep(turf_edge - 1.0, turf_edge + 1.0, surface_dist) * (1.0 - smoothstep(reach - 2.0, reach, surface_dist));
		col = mix(col, root_color.rgb, root * 0.4);
	}
	col = mix(col, top_color.rgb * (0.82 + n_fine.r * 0.34), turf);
	// The turf's own shadow on the earth right under it.
	col *= 1.0 - (1.0 - smoothstep(turf_edge, turf_edge + 2.5, surface_dist)) * (1.0 - turf) * 0.22 * step(0.01, turf_depth);

	// A darker seam right at the bottom edge so the soil reads as sitting on the rock.
	col *= 1.0 - smoothstep(depth - 3.0, depth, surface_dist) * 0.28;

	float shadow = (1.0 - smoothstep(depth, depth + shadow_depth, surface_dist)) * (1.0 - inside);
	COLOR = vec4(col * inside, max(inside, shadow * shadow_strength));
}
