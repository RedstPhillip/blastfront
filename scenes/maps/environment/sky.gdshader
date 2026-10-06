shader_type canvas_item;
render_mode unshaded;

// Night sky above the painted backdrop: vertical gradient, twinkling stars and faint drifting aurora.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 top_color : source_color = vec4(0.055, 0.14, 0.15, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.149, 0.306, 0.275, 1.0);
uniform float star_density = 0.0035;
uniform float aurora_strength = 0.12;
uniform vec4 aurora_color : source_color = vec4(0.45, 1.0, 0.75, 1.0);

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
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, UV.y));

	vec2 cell = floor(px / 3.0);
	float h = hash(cell);
	if (h < star_density) {
		float twinkle = 0.55 + 0.45 * sin(TIME * (1.5 + h * 900.0) + h * 6000.0);
		float fade = 1.0 - smoothstep(0.55, 0.95, UV.y);
		col += vec3(0.8, 0.95, 0.9) * twinkle * fade * (0.35 + fract(h * 7919.0) * 0.65);
	}

	// The aurora only lives in a band of the sky; skip its texture reads everywhere else (coherent per row).
	if (UV.y > 0.15 && UV.y < 0.85) {
		float band = texture(noise_tex, vec2(px.x * 0.0016 + TIME * 0.015, px.y * 0.004) / TILE_UNITS).r;
		float curtain = texture(noise_tex, vec2(px.x * 0.008 - TIME * 0.03, 3.0) / TILE_UNITS).g;
		float aurora = smoothstep(0.42, 0.8, band) * (0.5 + 0.5 * curtain) * smoothstep(0.15, 0.45, UV.y) * (1.0 - smoothstep(0.55, 0.85, UV.y));
		col += aurora_color.rgb * aurora * aurora_strength;
	}

	COLOR = vec4(col, 1.0);
}
