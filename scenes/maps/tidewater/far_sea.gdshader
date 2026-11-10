shader_type canvas_item;
render_mode unshaded;

// The open sea behind Tidewater, seen from the ruins: the rect's top edge is the horizon. Swell lines are
// laid out in perspective (long and thin far away, broad up close), the water pales into the haze at the
// horizon, and the moon lays a glittering path across it that widens towards the viewer. `storm` (0..1)
// darkens the water and breaks the glitter up.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 near_color : source_color = vec4(0.02, 0.09, 0.125, 1.0);
uniform vec4 far_color : source_color = vec4(0.11, 0.28, 0.31, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.27, 0.48, 0.47, 1.0);
uniform vec4 glint_color : source_color = vec4(0.86, 1.0, 0.94, 1.0);
uniform float moon_x = 2970.0;
uniform float center_x = 3400.0;
// Px below the horizon over which the perspective plays out; below that the water is simply near.
uniform float reach = 430.0;
uniform float storm = 0.0;

const float TILE_UNITS = 4.5;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	float v = clamp(local_px.y / reach, 0.0, 1.0);
	float z = 1.0 / (v + 0.15);
	vec3 col = mix(far_color.rgb, near_color.rgb, smoothstep(0.0, 0.8, v));
	col = mix(col, vec3(0.025, 0.06, 0.08), storm * 0.45 * smoothstep(0.0, 0.5, v));

	// Swell: two noise fields sliding over each other in sea-plane coordinates.
	vec2 wp = vec2((local_px.x - center_x) * z * 0.003, z * 7.5) / TILE_UNITS;
	float flow = TIME * (0.012 + storm * 0.01);
	float w1 = texture(noise_tex, wp + vec2(flow, flow * 0.6)).r;
	float w2 = texture(noise_tex, wp * 2.1 + vec2(-flow * 1.4, flow * 1.1)).g;
	float swell = w1 * 0.6 + w2 * 0.4;
	col *= 0.82 + 0.36 * swell;
	float crest = smoothstep(0.56, 0.74, swell);
	col += far_color.rgb * crest * (0.22 + storm * 0.2) * (0.35 + v);

	// The moon's path: sparkles where both fields peak, inside a column under the moon.
	float width = 22.0 + local_px.y * 0.52;
	float column = exp(-pow((local_px.x - moon_x) / width, 2.0));
	if (column > 0.01) {
		float s1 = texture(noise_tex, wp * 3.3 + vec2(TIME * 0.02, -TIME * 0.045)).g;
		float s2 = texture(noise_tex, wp * 2.4 - vec2(TIME * 0.016, TIME * 0.03)).b;
		float sparkle = smoothstep(0.2, 0.36, s1 * s2);
		float calm = 1.0 - storm * 0.85;
		col += glint_color.rgb * sparkle * column * (1.0 - v * 0.55) * 0.85 * calm;
		col += glint_color.rgb * column * 0.09 * exp(-v * 2.5) * calm;
	}

	// Haze: the far water takes the colour of the sky it meets.
	col = mix(col, mix(horizon_color.rgb, vec3(0.07, 0.11, 0.13), storm * 0.7), exp(-v * 22.0) * 0.8);
	COLOR = vec4(col, 1.0);
}
