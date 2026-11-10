shader_type canvas_item;
render_mode unshaded;

// Polar night over Rimefall: an indigo sky thick with stars and the pale band of the galaxy, a thin
// crescent moon, and the aurora: two curtains with a bright lower hem and rays fading upwards from green
// into violet, folding slowly along their length. The rect's bottom edge is the horizon.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 zenith_color : source_color = vec4(0.012, 0.02, 0.06, 1.0);
uniform vec4 mid_color : source_color = vec4(0.04, 0.075, 0.17, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.26, 0.34, 0.52, 1.0);
uniform vec4 aurora_low : source_color = vec4(0.25, 1.0, 0.58, 1.0);
uniform vec4 aurora_high : source_color = vec4(0.52, 0.3, 0.95, 1.0);
uniform vec4 moon_color : source_color = vec4(0.92, 0.95, 1.0, 1.0);
uniform vec2 moon_px = vec2(3780.0, 465.0);
uniform float moon_radius = 22.0;
uniform float aurora_strength = 0.55;

const float TILE_UNITS = 4.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

// One curtain: `hem` is its lower edge (in UV.y), light fades upwards from it over `reach`.
vec3 curtain(vec2 px, float v, float hem, float reach, float shift) {
	float above = hem - v;
	float fade = above > 0.0 ? exp(-above / reach) : exp(above / 0.006);
	if (fade < 0.01) {
		return vec3(0.0);
	}
	float rays = texture(noise_tex, vec2(px.x * 0.0058 + shift, TIME * 0.006 + shift) / TILE_UNITS * 4.0).r;
	rays = mix(rays, texture(noise_tex, vec2(px.x * 0.019 - shift, TIME * 0.009) / TILE_UNITS * 4.0).b, 0.4);
	float folds = texture(noise_tex, vec2(px.x * 0.0009 - TIME * 0.004, shift * 0.37) / TILE_UNITS * 2.0).g;
	float light = fade * (0.35 + 1.3 * rays * rays) * smoothstep(0.3, 0.62, folds);
	return mix(aurora_low.rgb, aurora_high.rgb, smoothstep(0.0, reach * 1.5, above)) * light;
}

void fragment() {
	vec2 px = local_px;
	float v = UV.y;
	vec3 col = mix(zenith_color.rgb, mid_color.rgb, smoothstep(0.1, 0.7, v));
	col = mix(col, horizon_color.rgb, pow(smoothstep(0.55, 1.0, v), 1.8));

	// The galaxy: a soft diagonal band, and more stars inside it.
	float band = exp(-pow((px.y - 250.0 - (px.x - 3400.0) * 0.16) / 150.0, 2.0));
	float dust = 0.0;
	if (band > 0.02 && v < 0.8) {
		dust = texture(noise_tex, px * vec2(0.0016, 0.0022) / TILE_UNITS * 3.0).b;
		col += vec3(0.1, 0.12, 0.2) * band * smoothstep(0.3, 0.75, dust) * (1.0 - smoothstep(0.5, 0.8, v));
	}
	if (v < 0.85) {
		vec2 grid = px / 3.6;
		float h = hash(floor(grid));
		if (h < 0.008 + band * 0.012) {
			float bright = fract(h * 7919.0);
			float dot_shape = 1.0 - smoothstep(0.1, 0.4 + bright * 0.22, length(fract(grid) - 0.5));
			float twinkle = 0.6 + 0.4 * sin(TIME * (1.0 + bright * 2.5) + h * 6000.0);
			vec3 tint = mix(vec3(0.75, 0.85, 1.0), vec3(1.0, 0.92, 0.8), step(0.8, fract(h * 331.0)));
			col += tint * dot_shape * twinkle * (1.0 - smoothstep(0.5, 0.85, v)) * (0.22 + bright * bright);
		}
	}

	// Crescent moon: a disc with a bite taken out, and a faint halo.
	vec2 md = px - moon_px;
	float dist = length(md);
	float disc = smoothstep(moon_radius + 1.0, moon_radius - 1.0, dist);
	float bite = smoothstep(moon_radius * 0.92 - 1.0, moon_radius * 0.92 + 1.0, length(md - vec2(-moon_radius * 0.42, -moon_radius * 0.16)));
	col += moon_color.rgb * exp(-dist / (moon_radius * 4.0)) * 0.2;
	col = mix(col, moon_color.rgb, disc * bite);
	col += moon_color.rgb * disc * (1.0 - bite) * 0.035;

	// Aurora, behind nothing but the stars.
	if (v > 0.08 && v < 0.82) {
		float wave_a = 0.05 * sin(px.x * 0.0019 + TIME * 0.045) + 0.022 * sin(px.x * 0.0051 - TIME * 0.07);
		float wave_b = 0.045 * sin(px.x * 0.0015 - TIME * 0.035 + 2.1) + 0.02 * sin(px.x * 0.0044 + TIME * 0.06);
		vec3 glow = curtain(px, v, 0.5 + wave_a, 0.17, 0.0) + curtain(px, v, 0.64 + wave_b, 0.13, 1.7) * 0.7;
		col += glow * aurora_strength;
	}

	COLOR = vec4(col, 1.0);
}
