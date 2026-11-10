shader_type canvas_item;

// Grass blades, stalks, fronds and hanging vines. UV.y is 0 at the root and 1 at the free end.
// Wind sways the free ends (bending more towards the tip, so blades curve rather than tilt) and runs
// through the grass in slow waves of light; nearby characters push blades aside.

uniform float wind_strength = 2.6;
uniform float wind_speed = 1.7;
uniform vec2 pushers[4];
uniform float push_radius = 34.0;
uniform float push_strength = 10.0;

varying float free_end;
varying float gust_light;

void vertex() {
	vec2 world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	float t = UV.y;
	float bend = t * (0.45 + 0.55 * t);
	float gust = 0.6 + 0.4 * sin(TIME * 0.37 + world.x * 0.002);
	// A wave of wind crossing the map every few seconds.
	float wave = pow(0.5 + 0.5 * sin(world.x * 0.011 - TIME * 1.15), 3.0);
	float sway = sin(TIME * wind_speed + world.x * 0.035) * 0.65 + sin(TIME * wind_speed * 2.3 + world.x * 0.11) * 0.35;
	VERTEX.x += (sway * gust + wave * 1.1) * wind_strength * bend;
	VERTEX.y += wave * wind_strength * 0.25 * bend;
	for (int i = 0; i < 4; i++) {
		vec2 d = world - pushers[i];
		float dist = length(d);
		float k = 1.0 - clamp(dist / push_radius, 0.0, 1.0);
		k = k * k;
		VERTEX.x += (d.x >= 0.0 ? 1.0 : -1.0) * k * push_strength * bend;
		VERTEX.y += k * push_strength * 0.4 * bend;
	}
	free_end = t;
	gust_light = wave;
}

void fragment() {
	COLOR.rgb *= mix(0.8, 1.12, free_end) * (1.0 + gust_light * 0.14 * free_end);
}
