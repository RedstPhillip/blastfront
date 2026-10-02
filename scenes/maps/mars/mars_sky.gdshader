shader_type canvas_item;
render_mode unshaded;

// Martian dusk: rusty zenith fading to a butterscotch horizon, the small pale sun wrapped in the blue
// glow that real Martian sunsets have, drifting dust veils, faint stars high up, two tiny moons and the
// occasional meteor streak through the thin air.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 zenith_color : source_color = vec4(0.2, 0.1, 0.12, 1.0);
uniform vec4 cloud_color : source_color = vec4(0.8, 0.8, 0.88, 1.0);
uniform vec4 mid_color : source_color = vec4(0.55, 0.27, 0.16, 1.0);
uniform vec4 horizon_color : source_color = vec4(0.86, 0.58, 0.38, 1.0);
uniform vec4 halo_color : source_color = vec4(0.62, 0.78, 0.92, 1.0);
uniform vec2 sun_uv = vec2(0.62, 0.74);
uniform float sun_size = 0.012;
uniform vec2 phobos_uv = vec2(0.26, 0.26);
uniform vec2 deimos_uv = vec2(0.8, 0.16);
uniform float aspect = 6.5;
// 0 = clear evening, 1 = the sky choked with storm dust (raised by the weather).
uniform float dust = 0.0;
uniform float wind = 0.0;
uniform vec4 dust_color : source_color = vec4(0.62, 0.36, 0.22, 1.0);

const float TILE_UNITS = 4.5;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

varying vec2 local_px;

void vertex() {
	local_px = VERTEX;
}

void fragment() {
	vec2 uv = UV;
	vec3 col = mix(zenith_color.rgb, mid_color.rgb, smoothstep(0.15, 0.7, uv.y));
	col = mix(col, horizon_color.rgb, smoothstep(0.5, 1.0, uv.y));

	// Sun with its blue halo (distance measured in a squashed space so the halo stays round).
	vec2 d = (uv - sun_uv) * vec2(aspect, 1.0);
	float dist = length(d);
	float halo = exp(-dist * 5.5);
	col = mix(col, halo_color.rgb, halo * 0.55);
	col += vec3(1.0, 0.95, 0.88) * exp(-dist * 22.0) * 0.35;
	col = mix(col, vec3(1.0, 0.98, 0.94), smoothstep(sun_size, sun_size * 0.6, dist));

	// Dust veils drifting across the lower sky.
	vec2 p = local_px * vec2(0.0012, 0.004) / TILE_UNITS;
	float veil = texture(noise_tex, p + vec2(TIME * 0.004, 0.0)).r;
	float veil2 = texture(noise_tex, p * 2.1 - vec2(TIME * 0.007, 0.0)).g;
	float veils = smoothstep(0.45, 0.85, veil * 0.6 + veil2 * 0.5) * smoothstep(0.3, 0.75, uv.y);
	col = mix(col, horizon_color.rgb * 1.08, veils * 0.28);

	// High CO2-ice cirrus: thin bluish-white wisps stretched by the upper winds.
	vec2 cp = local_px * vec2(0.0007, 0.006) / TILE_UNITS;
	float wisp = texture(noise_tex, cp + vec2(TIME * 0.003, 0.0)).b;
	float wisp_detail = texture(noise_tex, cp * vec2(3.0, 1.5) - vec2(TIME * 0.005, 0.0)).r;
	float cirrus = smoothstep(0.55, 0.8, wisp * 0.7 + wisp_detail * 0.45) * smoothstep(0.28, 0.4, uv.y) * (1.0 - smoothstep(0.5, 0.66, uv.y));
	col = mix(col, cloud_color.rgb * mix(0.75, 1.0, halo), cirrus * 0.2);

	// Faint stars near the zenith.
	vec2 cell = floor(local_px / 3.0);
	float h = hash(cell);
	if (h < 0.0018) {
		float twinkle = 0.6 + 0.4 * sin(TIME * (1.2 + h * 800.0) + h * 5000.0);
		col += vec3(0.95, 0.9, 0.85) * twinkle * (1.0 - smoothstep(0.35, 0.6, uv.y)) * 0.5;
	}

	// Phobos (lumpy, larger) and Deimos (a bright point).
	vec2 pd = (uv - phobos_uv) * vec2(aspect, 1.0);
	float phobos = smoothstep(0.012, 0.009, length(pd * vec2(1.0, 1.35)) + texture(noise_tex, uv * 4.0).r * 0.004);
	float phobos_shade = smoothstep(-0.01, 0.012, pd.x + pd.y * 0.5);
	col = mix(col, mix(vec3(0.42, 0.36, 0.33), vec3(0.78, 0.7, 0.62), phobos_shade), phobos);
	vec2 dd = (uv - deimos_uv) * vec2(aspect, 1.0);
	col += vec3(0.95, 0.9, 0.85) * smoothstep(0.005, 0.0, length(dd)) * 0.9;

	// A meteor every few seconds somewhere in the upper sky.
	float slot = floor(TIME / 7.0);
	float t = fract(TIME / 7.0);
	vec2 start = vec2(0.2 + hash(vec2(slot, 1.0)) * 0.7, 0.3 + hash(vec2(slot, 2.0)) * 0.22);
	vec2 dir = normalize(vec2(-0.9, 0.35));
	float travel = t * 3.0;
	if (travel < 1.0) {
		vec2 head = start + dir * vec2(1.0 / aspect, 1.0) * travel * 0.9;
		vec2 rel = (uv - head) * vec2(aspect, 1.0);
		vec2 dn = normalize(dir * vec2(1.0, 1.0));
		float along = dot(rel, -dn);
		float across = abs(dot(rel, vec2(-dn.y, dn.x)));
		float streak = smoothstep(0.0025, 0.0, across) * smoothstep(0.12, 0.0, along) * step(0.0, along);
		col += vec3(1.0, 0.92, 0.8) * streak * (1.0 - travel) * 0.8;
	}

	// Storm: a churning brown pall rolls over everything, the sun fades to a smudge.
	if (dust > 0.001) {
		vec2 sp = local_px * vec2(0.0009, 0.0024) / TILE_UNITS;
		float churn = texture(noise_tex, sp + vec2(-TIME * 0.02 * wind, TIME * 0.003)).r;
		float churn2 = texture(noise_tex, sp * 2.6 + vec2(-TIME * 0.045 * wind, 0.0)).g;
		float body = mix(churn, churn2, 0.4);
		vec3 storm = dust_color.rgb * (0.72 + 0.5 * body) * mix(0.75, 1.15, smoothstep(0.1, 0.95, uv.y));
		storm += vec3(1.0, 0.8, 0.6) * exp(-dist * 9.0) * 0.18;
		col = mix(col, storm, clamp(dust * (0.75 + 0.35 * body), 0.0, 1.0));
	}

	COLOR = vec4(col, 1.0);
}
