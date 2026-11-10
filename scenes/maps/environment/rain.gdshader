shader_type canvas_item;
render_mode unshaded;

// Rain over an arena, drawn in world space so it stays put when the camera moves: three depths of slanted
// streaks (near ones long, fast and sparse; far ones short, slow and dense). No textures. `intensity`
// (0..1) thins it out to a drizzle, `slant` leans it with the wind, and nothing falls below `floor_y` (the
// water line).

uniform float intensity = 0.0;
uniform float slant = 0.22;
uniform float floor_y = 100000.0;
uniform vec4 rain_color : source_color = vec4(0.72, 0.9, 0.92, 1.0);

varying vec2 world_px;

float hash(float n) {
	return fract(sin(n * 127.1) * 43758.5453);
}

float layer(vec2 p, float column_width, float streak, float speed, float density) {
	p.x += p.y * slant;
	float column = floor(p.x / column_width);
	float h = hash(column);
	if (h > density) {
		return 0.0;
	}
	float h2 = hash(column + 17.3);
	// Each column carries one streak falling through a tall cell, at its own pace and phase.
	float cell = streak * (3.0 + h2 * 3.0);
	float y = fract(p.y / cell - TIME * speed * (0.8 + 0.4 * h2) / cell + h * 31.0);
	float along = smoothstep(0.0, 0.04, y) * (1.0 - smoothstep(streak / cell * 0.6, streak / cell, y));
	float across = 1.0 - smoothstep(0.0, 0.5, abs(fract(p.x / column_width) - 0.3 - h2 * 0.4) * column_width);
	return along * across;
}

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	if (intensity < 0.01 || world_px.y > floor_y) {
		discard;
	}
	float far = layer(world_px, 5.0, 16.0, 520.0, intensity * 0.5) * 0.3;
	float mid = layer(world_px + vec2(131.0, 57.0), 9.0, 26.0, 760.0, intensity * 0.42) * 0.45;
	float near = layer(world_px + vec2(47.0, 211.0), 17.0, 44.0, 1050.0, intensity * 0.3) * 0.6;
	float a = max(far, max(mid, near)) * (0.35 + intensity * 0.4);
	// Fade out into the last few px above the floor.
	a *= clamp((floor_y - world_px.y) / 6.0, 0.0, 1.0);
	COLOR = vec4(rain_color.rgb, a);
}
