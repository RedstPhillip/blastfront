shader_type canvas_item;
render_mode unshaded;

// Snowfall over an arena, drawn in world space so it stays put when the camera moves: three depths of
// flakes (far ones small, slow and many; near ones large, fast and few), each drifting on its own little
// sway. `wind` (px/s) carries them sideways and breathes in slow gusts; `intensity` (0..1.5) thins the
// fall out or thickens it into a flurry. No textures.

uniform float intensity = 1.0;
uniform float wind = 26.0;
uniform vec4 snow_color : source_color = vec4(0.94, 0.97, 1.0, 1.0);

varying vec2 world_px;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float flakes(vec2 p, float cell, float fall, float size, float drift, float density) {
	// The gust is integrated analytically, so the flakes speed up and slow down without jumping.
	float carried = wind * drift * (0.65 * TIME - 1.6 * cos(TIME * 0.21));
	p -= vec2(carried, TIME * fall);
	vec2 id = floor(p / cell);
	float h = hash(id);
	if (h > density) {
		return 0.0;
	}
	vec2 center = vec2(hash(id + 1.3), hash(id + 7.7)) * 0.6 + 0.2;
	center.x += sin(TIME * (0.8 + h * 1.6) + h * 40.0) * 0.14;
	float d = length((fract(p / cell) - center) * cell);
	return (1.0 - smoothstep(size * 0.35, size, d)) * (0.55 + 0.45 * hash(id + 3.1));
}

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (intensity < 0.01) {
		discard;
	}
	float density = clamp(intensity, 0.0, 1.5);
	float far = flakes(world_px, 22.0, 26.0, 1.3, 0.6, 0.5 * density) * 0.42;
	float mid = flakes(world_px + vec2(71.0, 13.0), 38.0, 44.0, 2.0, 0.85, 0.42 * density) * 0.62;
	float near = flakes(world_px + vec2(19.0, 157.0), 84.0, 78.0, 3.4, 1.2, 0.3 * density) * 0.55;
	COLOR = vec4(snow_color.rgb, max(far, max(mid, near)));
}
