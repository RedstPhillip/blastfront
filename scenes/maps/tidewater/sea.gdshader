shader_type canvas_item;
render_mode unshaded;

// The sea of Tidewater. The rect's top sits `surface_pad` px above the water line and moves with the tide;
// everything below the (gently waving) line is translucent water that darkens with depth, with rippling
// caustic light near the top and a bright broken foam edge on the surface. `surge` (0..1) churns it up
// while the tide is running.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 shallow_color : source_color = vec4(0.16, 0.5, 0.5, 1.0);
uniform vec4 deep_color : source_color = vec4(0.02, 0.12, 0.16, 1.0);
uniform vec4 foam_color : source_color = vec4(0.86, 1.0, 0.97, 1.0);
uniform float surface_pad = 16.0;
uniform float surge = 0.0;

const float TILE_UNITS = 4.5;

varying vec2 local_px;
varying vec2 world_px;

void vertex() {
	local_px = VERTEX;
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float x = world_px.x;
	float wave = sin(x * 0.024 + TIME * 2.1) * 1.5 + sin(x * 0.063 - TIME * 1.4) * 0.9;
	wave += sin(x * 0.011 - TIME * 0.7) * 1.6 * (0.4 + surge);
	float line_y = surface_pad + wave;
	float depth = local_px.y - line_y;
	if (depth < -1.5) {
		discard;
	}
	float aa = clamp(depth + 1.5, 0.0, 1.0);
	vec4 n = texture(noise_tex, vec2(x * 0.004, local_px.y * 0.008) / TILE_UNITS + vec2(TIME * 0.01, 0.0));
	vec3 col = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 160.0, depth));
	float alpha = mix(0.5, 0.86, smoothstep(0.0, 120.0, depth));
	// Caustics: two drifting noise layers folded into thin bright ridges.
	if (depth < 90.0) {
		vec2 cp = vec2(x, local_px.y) * 0.012 / TILE_UNITS;
		float c1 = texture(noise_tex, cp + vec2(TIME * 0.035, TIME * 0.02)).r;
		float c2 = texture(noise_tex, cp * 1.7 - vec2(TIME * 0.025, -TIME * 0.03)).g;
		float ridge = 1.0 - abs(c1 + c2 - 1.0) * 3.2;
		col += foam_color.rgb * clamp(ridge, 0.0, 1.0) * 0.22 * (1.0 - smoothstep(10.0, 90.0, depth));
	}
	// Foam: a bright line on the surface, broken up by noise, thicker and wilder in a surge.
	float foam_width = 2.2 + surge * 2.5 + n.b * 1.8;
	float foam = 1.0 - smoothstep(foam_width * 0.4, foam_width, depth);
	foam *= 0.7 + 0.3 * smoothstep(0.35, 0.6, n.r + surge * 0.3);
	col = mix(col, foam_color.rgb, foam * 0.9);
	alpha = mix(alpha, 0.95, foam);
	COLOR = vec4(col, alpha * aa);
}
