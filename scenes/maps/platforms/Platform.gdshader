shader_type canvas_item;

uniform float speed = 0.00005;
uniform float scale = 1.2;

uniform vec4 sky_top    : source_color = vec4(0.28, 0.38, 0.34, 1.0);
uniform vec4 sky_bottom : source_color = vec4(0.14, 0.20, 0.18, 1.0);

uniform vec4 layer1 : source_color = vec4(0.28, 0.40, 0.26, 1.0);
uniform vec4 layer2 : source_color = vec4(0.20, 0.30, 0.20, 1.0);
uniform vec4 layer3 : source_color = vec4(0.12, 0.18, 0.12, 1.0);
uniform vec4 layer4 : source_color = vec4(0.08, 0.12, 0.08, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float small_detail(vec2 p) {
	return noise(p * 6.0) * 0.08;
}

void fragment() {
	vec2 uv = SCREEN_UV;

	// MUCH slower animation
	float t = TIME * speed * 0.02;

	vec2 p = uv * scale;

	float n = small_detail(p + vec2(t, 0.0));
	float h = uv.y + n;

	float m1 = step(0.72, h);
	float m2 = step(0.52, h) - m1;
	float m3 = step(0.34, h) - m2 - m1;
	float m4 = 1.0 - m1 - m2 - m3;

	float d = noise(p * 3.0);

	vec3 col =
		layer1.rgb * m1 +
		layer2.rgb * m2 +
		layer3.rgb * m3 +
		layer4.rgb * m4;

	col += d * 0.03;
	col *= 1.05;

	float alpha = texture(TEXTURE, UV).a;
	COLOR = vec4(col, alpha);
}