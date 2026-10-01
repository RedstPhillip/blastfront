shader_type canvas_item;
render_mode unshaded;

// Full-screen post process: shockwave distortion, chromatic aberration, mip-chain bloom,
// colour grading, vignette, low-health danger tint, flash and film grain.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float intensity = 1.0;
uniform float aspect = 1.7777;

uniform float vignette = 0.38;
uniform vec3 vignette_color : source_color = vec3(0.012, 0.03, 0.035);
uniform float base_aberration = 0.25;
uniform float aberration = 0.0;
uniform float grain = 0.032;
uniform float saturation = 1.1;
uniform float contrast = 1.07;
uniform vec3 shadow_tint : source_color = vec3(0.0, 0.035, 0.05);
uniform vec3 highlight_tint : source_color = vec3(1.05, 1.0, 0.92);
uniform float bloom = 0.42;
uniform float bloom_threshold = 0.68;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount = 0.0;
uniform float danger = 0.0;
uniform float desaturate = 0.0;
uniform vec4 waves[4];

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	for (int i = 0; i < 4; i++) {
		vec4 w = waves[i];
		if (w.w <= 0.0) {
			continue;
		}
		vec2 d = uv - w.xy;
		d.x *= aspect;
		float dist = length(d);
		float band = 1.0 - clamp(abs(dist - w.z) / 0.05, 0.0, 1.0);
		band = band * band * (3.0 - 2.0 * band);
		vec2 dir = d / max(dist, 0.0001);
		dir.x /= aspect;
		uv -= dir * band * w.w * 0.02;
	}

	vec2 from_center = uv - 0.5;
	float ca = (base_aberration + aberration) * intensity;
	vec2 offset = from_center * ca * 0.007;
	vec3 col;
	col.r = texture(screen_tex, uv + offset).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - offset).b;

	vec3 b1 = textureLod(screen_tex, uv, 2.0).rgb;
	vec3 b2 = textureLod(screen_tex, uv, 3.5).rgb;
	vec3 b3 = textureLod(screen_tex, uv, 5.0).rgb;
	vec3 blur = b1 * 0.35 + b2 * 0.4 + b3 * 0.25;
	vec3 bright = max(blur - vec3(bloom_threshold), vec3(0.0)) / (1.0 - bloom_threshold);
	col += bright * bright * bloom * intensity;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, mix(1.0, saturation, intensity));
	col = mix(col, vec3(luma) * vec3(0.95, 1.0, 1.02), clamp(desaturate, 0.0, 1.0));
	col = (col - 0.5) * mix(1.0, contrast, intensity) + 0.5;
	col += shadow_tint * (1.0 - smoothstep(0.0, 0.45, luma)) * intensity;
	col *= mix(vec3(1.0), highlight_tint, smoothstep(0.4, 1.0, luma) * intensity);

	vec2 vig_uv = (SCREEN_UV - 0.5) * vec2(1.0, 0.9);
	float vig = smoothstep(0.82, 0.22, length(vig_uv) * 1.18);
	col = mix(vignette_color, col, mix(1.0, vig, vignette * intensity));

	float edge = 1.0 - smoothstep(0.75, 0.15, length(vig_uv) * 1.25);
	float pulse = 0.75 + 0.25 * sin(TIME * 7.0);
	col = mix(col, vec3(0.62, 0.02, 0.05), clamp(danger * edge * pulse, 0.0, 0.85));

	col = mix(col, flash_color.rgb, clamp(flash_amount, 0.0, 1.0));
	col += (hash(SCREEN_UV * vec2(1931.0, 1117.0) + fract(TIME) * 17.0) - 0.5) * grain * intensity;

	COLOR = vec4(col, 1.0);
}
