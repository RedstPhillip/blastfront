shader_type canvas_item;

// Grass blades and hanging vines. UV.y is 0 at the root and 1 at the free end.
// Wind sways the free ends; nearby characters push blades aside.

uniform float wind_strength = 2.6;
uniform float wind_speed = 1.7;
uniform vec2 pushers[4];
uniform float push_radius = 34.0;
uniform float push_strength = 10.0;

varying float free_end;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float t = UV.y;
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + world.x * 0.002);
	float sway = sin(TIME * wind_speed + world.x * 0.035) * 0.65 + sin(TIME * wind_speed * 2.3 + world.x * 0.11) * 0.35;
	VERTEX.x += sway * wind_strength * gust * t;
	for (int i = 0; i < 4; i++) {
		vec2 d = world - pushers[i];
		float dist = length(d);
		float k = 1.0 - clamp(dist / push_radius, 0.0, 1.0);
		k = k * k;
		VERTEX.x += (d.x >= 0.0 ? 1.0 : -1.0) * k * push_strength * t;
		VERTEX.y += k * push_strength * 0.4 * t;
	}
	free_end = t;
}

void fragment() {
	COLOR.rgb *= mix(0.72, 1.18, free_end);
}
