shader_type canvas_item;

// Topsoil band that hugs every walkable top edge with the same depth everywhere: flat ledges, slopes,
// lower steps and chamfered corners alike. UV.x carries the distance (px) below the surface, so the
// band can end in an irregular, noise-driven lower edge with a soft contact shadow on the rock.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 top_color : source_color = vec4(0.29, 0.47, 0.25, 1.0);
uniform vec4 deep_color : source_color = vec4(0.13, 0.19, 0.12, 1.0);
uniform vec4 fleck_color : source_color = vec4(0.42, 0.36, 0.24, 1.0);
uniform float base_depth = 9.0;
uniform float depth_variation = 4.0;
uniform float shadow_depth = 5.0;
uniform float shadow_strength = 0.32;

varying vec2 world_pos;
varying float surface_dist;

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
	vec3 col = mix(top_color.rgb, deep_color.rgb, smoothstep(0.1, 1.0, t));
	col *= 0.86 + n_fine.b * 0.26;
	// Small stones and roots peeking out of the lower half.
	float fleck = smoothstep(0.8, 0.84, n_fine.g) * smoothstep(0.35, 0.75, t);
	col = mix(col, fleck_color.rgb, fleck * 0.55);
	// A darker seam right at the bottom edge so the soil reads as sitting on the rock.
	col *= 1.0 - smoothstep(depth - 3.0, depth, surface_dist) * 0.28;

	float shadow = (1.0 - smoothstep(depth, depth + shadow_depth, surface_dist)) * (1.0 - inside);
	COLOR = vec4(col * inside, max(inside, shadow * shadow_strength));
}
