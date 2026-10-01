shader_type canvas_item;
render_mode unshaded;

// Bottomless gorge below the arena: darkens towards the bottom with a slowly churning mist layer on top.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 abyss_color : source_color = vec4(0.03, 0.065, 0.055, 1.0);
uniform vec4 mist_color : source_color = vec4(0.42, 0.6, 0.52, 1.0);
uniform float mist_strength = 0.32;

const float TILE_UNITS = 4.5;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	float depth = UV.y;
	float body = smoothstep(0.06, 0.3, depth);
	vec2 p = local_px * vec2(0.006, 0.012) / TILE_UNITS;
	float mist = texture(noise_tex, p + vec2(TIME * 0.06 / TILE_UNITS, 0.0)).r * 0.6
		+ texture(noise_tex, p * 2.3 - vec2(TIME * 0.09, TIME * 0.02) / TILE_UNITS).b * 0.4;
	float mist_band = exp(-pow((depth - 0.16) * 6.0, 2.0));
	vec3 col = mix(abyss_color.rgb, mist_color.rgb, mist * mist_band * mist_strength);
	float alpha = clamp(body + mist * mist_band * 0.55, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
