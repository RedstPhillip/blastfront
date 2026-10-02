shader_type canvas_item;
render_mode unshaded;

// Screen-space dust between the world and the HUD. A pocket of clearer air stays around the local player;
// beyond it the storm thickens with distance, and sheets of sand stream across in the wind direction.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 dust_color : source_color = vec4(0.72, 0.43, 0.27, 1.0);
uniform float density = 0.0;
uniform float pocket_density = 0.0;
uniform vec2 clear_center = vec2(640.0, 360.0);
uniform float clear_radius = 320.0;
uniform float softness = 260.0;
uniform float wind = 0.0;
uniform vec2 screen_size = vec2(1280.0, 720.0);
// The storm front: a churning wall that creeps in from the upwind screen edge while a storm builds
// (front 0..1 of its approach) and sweeps across when it hits (front > 1).
uniform float front = 0.0;
uniform float front_alpha = 0.0;
uniform float front_side = 1.0;

void fragment() {
	vec2 px = SCREEN_UV * screen_size;
	float d = distance(px, clear_center);
	float far = smoothstep(clear_radius, clear_radius + softness, d);
	vec2 uv = SCREEN_UV * vec2(screen_size.x / screen_size.y, 1.0);
	float drift = TIME * wind;
	float n1 = texture(noise_tex, uv * 1.3 + vec2(-drift * 0.22, TIME * 0.02)).r;
	float n2 = texture(noise_tex, uv * 3.1 + vec2(-drift * 0.5, -TIME * 0.015)).g;
	float turb = mix(n1, n2, 0.45);
	// Long horizontal sheets of sand racing past.
	float sheet = texture(noise_tex, vec2(uv.x * 0.35 - drift * 0.9, uv.y * 5.0 + n1 * 0.6)).b;
	sheet = smoothstep(0.58, 0.88, sheet) * abs(clamp(wind, -1.0, 1.0));
	float amount = mix(pocket_density, density, far) * (0.72 + 0.56 * turb) + sheet * 0.18 * max(density, pocket_density * 2.0);
	vec3 col = dust_color.rgb * (0.86 + 0.28 * turb);
	if (front_alpha > 0.001) {
		// Distance from the upwind edge, 0..1 across the screen.
		float from_edge = front_side > 0.0 ? SCREEN_UV.x : 1.0 - SCREEN_UV.x;
		float billow = texture(noise_tex, vec2(SCREEN_UV.y * 2.2 + TIME * 0.05, TIME * 0.04)).r * 0.22
			+ texture(noise_tex, vec2(SCREEN_UV.y * 5.0 - TIME * 0.09, 0.3)).g * 0.1;
		float edge = front * 0.62 + billow - 0.16;
		float wall = 1.0 - smoothstep(edge - 0.2, edge + 0.04, from_edge);
		float churn = 0.75 + 0.5 * texture(noise_tex, uv * 1.8 + vec2(-drift * 0.35, TIME * 0.05)).b;
		// Keep the local player readable inside the front as well.
		float front_amount = wall * front_alpha * churn * mix(0.4, 1.0, smoothstep(clear_radius * 0.35, clear_radius * 0.35 + 220.0, d));
		col = mix(col, dust_color.rgb * 0.62 * churn, clamp(front_amount * 1.2, 0.0, 1.0) * (1.0 - amount));
		amount = max(amount, front_amount);
	}
	COLOR = vec4(col, clamp(amount, 0.0, 0.94));
}
