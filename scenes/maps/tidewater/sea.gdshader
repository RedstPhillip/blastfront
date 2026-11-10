shader_type canvas_item;
render_mode unshaded;

// The sea of Tidewater. The rect's top sits `surface_pad` px above the water line and moves with the tide.
// Everything under the (gently waving) line is seen through the water: the picture behind it wobbles with
// the swell, takes the water's colour and sinks into the dark with depth. Moonlight scatters in a pale
// band under the surface, falls through it in slanted shafts and ripples as caustics; the surface itself
// is a bright broken line of foam. `surge` (0..1) churns it up while the tide is running, `rain` (0..1)
// peppers the surface with the rings of falling drops.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform vec4 shallow_color : source_color = vec4(0.12, 0.44, 0.45, 1.0);
uniform vec4 deep_color : source_color = vec4(0.012, 0.085, 0.125, 1.0);
uniform vec4 foam_color : source_color = vec4(0.86, 1.0, 0.97, 1.0);
uniform vec4 light_color : source_color = vec4(0.62, 0.95, 0.9, 1.0);
uniform float surface_pad = 16.0;
uniform float surge = 0.0;
uniform float rain = 0.0;

const float TILE_UNITS = 4.5;

varying vec2 local_px;
varying vec2 world_px;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

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
	if (depth < -4.0) {
		discard;
	}
	float under = clamp(depth + 1.5, 0.0, 1.0);
	vec4 n = texture(noise_tex, vec2(x * 0.004, local_px.y * 0.008) / TILE_UNITS + vec2(TIME * 0.01, 0.0));

	// What lies behind the water, bent sideways by the swell (never upwards, so nothing above the surface
	// leaks in); the bend grows over the first few px of depth.
	float bend = (n.g - 0.5) * 5.0 + sin(local_px.y * 0.085 + TIME * 2.3 + x * 0.01) * 1.1;
	bend *= smoothstep(0.0, 26.0, depth) * (1.0 + surge * 1.2);
	vec3 behind = texture(screen_tex, SCREEN_UV + vec2(bend * SCREEN_PIXEL_SIZE.x, 0.0)).rgb;

	vec3 tint = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, 170.0, depth));
	float opacity = mix(0.4, 0.9, smoothstep(0.0, 150.0, depth));
	vec3 col = mix(behind, tint, opacity);

	// Moonlight scattered just under the surface, and shafts of it slanting down.
	col += shallow_color.rgb * 0.2 * exp(-max(depth, 0.0) / 15.0);
	if (depth < 230.0) {
		float lane = texture(noise_tex, vec2((x - depth * 0.42) * 0.0038 + TIME * 0.02, TIME * 0.012) / TILE_UNITS).r;
		float shaft = smoothstep(0.48, 0.7, lane) * exp(-depth / 120.0) * smoothstep(3.0, 26.0, depth);
		col += light_color.rgb * shaft * 0.085;
	}
	// Caustics: two drifting noise layers folded into thin bright ridges.
	if (depth < 100.0) {
		vec2 cp = vec2(x, local_px.y) * 0.012 / TILE_UNITS;
		float c1 = texture(noise_tex, cp + vec2(TIME * 0.035, TIME * 0.02)).r;
		float c2 = texture(noise_tex, cp * 1.7 - vec2(TIME * 0.025, -TIME * 0.03)).g;
		float ridge = 1.0 - abs(c1 + c2 - 1.0) * 3.2;
		col += foam_color.rgb * clamp(ridge, 0.0, 1.0) * 0.2 * (1.0 - smoothstep(8.0, 100.0, depth));
	}
	// The surface: a shadow line under a bright edge of foam, broken up by noise, thicker and wilder in a
	// surge.
	col *= 1.0 - 0.22 * exp(-pow((depth - 6.0) / 3.0, 2.0));
	float foam_width = 2.2 + surge * 2.5 + n.b * 1.8;
	float foam = (1.0 - smoothstep(foam_width * 0.4, foam_width, depth)) * under;
	foam *= 0.7 + 0.3 * smoothstep(0.35, 0.6, n.r + surge * 0.3);
	col = mix(col, foam_color.rgb, foam * 0.9);
	float alpha = under;

	// Rain: every drop that lands throws up a speck on the line and a short-lived ring.
	if (rain > 0.01 && depth < 5.0) {
		float cell = floor(x / 9.0);
		float beat = TIME * 7.0 + hash(vec2(cell, 3.0)) * 10.0;
		float life = fract(beat);
		float drop = step(1.0 - rain * 0.55, hash(vec2(cell, floor(beat))));
		float offset = abs(fract(x / 9.0) - 0.5) * 9.0;
		float ring = (1.0 - smoothstep(0.0, 1.2, abs(offset - life * 4.5))) * (1.0 - life);
		float crown = (1.0 - smoothstep(0.6, 1.6, offset)) * (1.0 - smoothstep(0.0, 0.35, life)) * step(depth, 0.5) * step(-3.5 * (1.0 - life), depth);
		float speck = drop * max(ring * step(-1.0, depth) * step(depth, 1.5), crown);
		col = mix(col, foam_color.rgb, speck * 0.85);
		alpha = max(alpha, speck);
	}
	COLOR = vec4(col, alpha);
}
