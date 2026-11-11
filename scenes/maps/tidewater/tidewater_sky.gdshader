shader_type canvas_item;
render_mode unshaded;

// Night over the drowned coast: a deep sea-green sky paling towards the horizon, a full moon with its
// halo, a few stars, and long cloud banks drifting in from the sea whose thin edges catch the moonlight.
// `storm` (0..1, raised by the weather as a tide comes in) closes the cloud cover and drains the colour;
// `flash` lights the clouds from inside for the sheet lightning of a spring tide.
// The rect's bottom edge is the horizon.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 zenith_color : source_color = vec4(0.015, 0.04, 0.075, 1.0);
uniform vec4 mid_color : source_color = vec4(0.045, 0.13, 0.19, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.27, 0.48, 0.47, 1.0);
uniform vec4 cloud_dark : source_color = vec4(0.03, 0.07, 0.095, 1.0);
uniform vec4 cloud_lit : source_color = vec4(0.56, 0.76, 0.76, 1.0);
uniform vec4 moon_color : source_color = vec4(0.93, 0.98, 0.93, 1.0);
uniform vec2 moon_px = vec2(2970.0, 495.0);
uniform float moon_radius = 26.0;
uniform float storm = 0.0;
uniform float flash = 0.0;
uniform float flash_x = 3400.0;

const float TILE_UNITS = 4.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec2 px = local_px;
	float v = UV.y;
	vec3 col = mix(zenith_color.rgb, mid_color.rgb, smoothstep(0.1, 0.72, v));
	col = mix(col, horizon_color.rgb, pow(smoothstep(0.55, 1.0, v), 1.6));
	vec3 slate = vec3(0.04, 0.07, 0.09) + horizon_color.rgb * 0.22 * smoothstep(0.6, 1.0, v);
	col = mix(col, slate, storm * 0.72);

	// Cloud banks: long and flat, three octaves of the baked noise drifting at different speeds.
	float dens = 0.0;
	float body = 0.0;
	if (v > 0.1) {
		vec2 cp = px * vec2(0.00052, 0.0021) / TILE_UNITS;
		// Far clouds: a few px a second on a calm night, about twice that as the storm front moves in.
		float drift = TIME * (0.0007 + storm * 0.0009);
		float c1 = texture(noise_tex, cp + vec2(drift, 0.0)).r;
		float c2 = texture(noise_tex, cp * 2.3 + vec2(drift * 1.7, 0.02)).g;
		float c3 = texture(noise_tex, cp * 5.1 + vec2(drift * 2.6, 0.0)).b;
		body = c1 * 0.55 + c2 * 0.3 + c3 * 0.15;
		float cover = mix(0.57, 0.36, storm);
		dens = smoothstep(cover, cover + 0.2, body) * smoothstep(0.1, 0.42, v);
	}

	// Stars: soft dots of uneven brightness, hidden by cloud and by the glow near the horizon.
	if (v < 0.82) {
		vec2 grid = px / 4.0;
		float h = hash(floor(grid));
		if (h < 0.0075) {
			float bright = fract(h * 7919.0);
			float dot_shape = 1.0 - smoothstep(0.12, 0.42 + bright * 0.2, length(fract(grid) - 0.5));
			float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + bright * 2.2) + h * 6000.0);
			col += vec3(0.8, 0.95, 0.92) * dot_shape * twinkle * (1.0 - smoothstep(0.45, 0.82, v)) * (0.25 + bright * bright * 0.9) * (1.0 - dens) * (1.0 - storm);
		}
	}

	// Moon: a soft disc with faint maria and a wide halo.
	vec2 md = px - moon_px;
	float dist = length(md);
	float disc = smoothstep(moon_radius + 1.0, moon_radius - 1.0, dist);
	float halo = exp(-dist / (moon_radius * 4.2));
	col += moon_color.rgb * halo * 0.26 * (1.0 - storm * 0.55);
	col += moon_color.rgb * exp(-dist / (moon_radius * 13.0)) * 0.07 * (1.0 - storm * 0.5);
	if (disc > 0.0) {
		float maria = texture(noise_tex, md * 0.0045 + vec2(0.31, 0.62)).r;
		vec3 moon = moon_color.rgb * (0.84 + 0.16 * smoothstep(0.35, 0.62, maria));
		col = mix(col, moon, disc * (1.0 - dens * 0.82));
	}

	// Clouds: dark bodies, moonlit where they thin out, a little horizon light from below.
	if (dens > 0.0) {
		float edge = dens * (1.0 - dens) * 4.0;
		float moonlit = exp(-dist / 560.0);
		vec3 ccol = mix(cloud_dark.rgb, cloud_lit.rgb, edge * (0.2 + 0.8 * moonlit) * (1.0 - storm * 0.45));
		ccol += horizon_color.rgb * 0.13 * smoothstep(0.55, 1.0, v);
		ccol += vec3(0.6, 0.76, 0.9) * flash * (0.35 + body) * exp(-abs(px.x - flash_x) / 620.0);
		col = mix(col, ccol, dens * 0.93);
	}
	col += vec3(0.25, 0.34, 0.42) * flash * 0.12;

	COLOR = vec4(col, 1.0);
}
