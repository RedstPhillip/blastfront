shader_type canvas_item;
render_mode unshaded;

// Bottomless gorge below the arena. The rect's top edge sits `fade_height` px above the map's bottom border:
// terrain and backdrop fade into the abyss colour over that band, with a slowly churning mist layer, and
// everything is gone exactly at the border line (the camera never looks further down).

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 abyss_color : source_color = vec4(0.03, 0.065, 0.055, 1.0);
uniform vec4 mist_color : source_color = vec4(0.42, 0.6, 0.52, 1.0);
uniform float mist_strength = 0.32;
uniform float fade_height = 48.0;

const float TILE_UNITS = 4.5;

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	float depth = local_px.y / fade_height;
	float body = smoothstep(0.0, 1.0, depth);
	float mist_band = exp(-pow((depth - 0.6) * 2.2, 2.0)) * (1.0 - step(1.0, depth));
	float mist = 0.0;
	if (mist_band > 0.002) {
		vec2 p = local_px * vec2(0.006, 0.012) / TILE_UNITS;
		mist = texture(noise_tex, p + vec2(TIME * 0.06 / TILE_UNITS, 0.0)).r * 0.6
			+ texture(noise_tex, p * 2.3 - vec2(TIME * 0.09, TIME * 0.02) / TILE_UNITS).b * 0.4;
	}
	vec3 col = mix(abyss_color.rgb, mist_color.rgb, mist * mist_band * mist_strength);
	float alpha = clamp(body + mist * mist_band * 0.45, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
