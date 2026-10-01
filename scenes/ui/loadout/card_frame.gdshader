shader_type canvas_item;

// Item card / slot frame: rounded rect with a bright border, diagonal body gradient, corner glows,
// a soft light sweep and a vignette. Replaces per-pixel generated textures so cards cost nothing to
// build and hover instantly.

uniform vec4 base_color : source_color = vec4(0.27, 0.31, 0.35, 1.0);
uniform float alpha = 0.82;
uniform float highlighted = 0.0;
uniform vec2 rect_size = vec2(54.0, 54.0);
uniform float radius = 8.0;

float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 uv = UV;
	vec2 px = uv * rect_size;
	vec2 center = rect_size * 0.5;
	float d = rounded_box(px - center, center - vec2(0.5), radius);
	float aa = max(fwidth(d), 0.5);
	float shape = 1.0 - smoothstep(-aa, aa, d);

	float boost = mix(1.0, 1.08, highlighted);
	float a = min(alpha * boost, 1.0);
	vec3 base = base_color.rgb;
	vec3 low = base * 0.26;
	vec3 mid = base * 0.76;
	vec3 high = min(base + vec3(mix(0.24, 0.34, highlighted)), vec3(1.0));
	vec3 accent = min(base * 0.65 + vec3(0.18), vec3(1.0));
	vec3 border = min(base + vec3(mix(0.34, 0.52, highlighted)), vec3(1.0));

	float diagonal = smoothstep(0.0, 1.0, (uv.x * 0.72 + (1.0 - uv.y) * 0.92) * 0.62);
	float top_glow = smoothstep(0.0, 1.0, max(0.0, 1.0 - distance(uv, vec2(0.76, 0.16)) * 1.48));
	float lower_glow = smoothstep(0.0, 1.0, max(0.0, 1.0 - distance(uv, vec2(0.24, 0.78)) * 1.72));
	float sweep = smoothstep(0.0, 0.18, 0.18 - abs((uv.x * 0.82 + uv.y * 0.42) - 0.56));
	float vignette = smoothstep(0.18, 0.88, distance(uv, vec2(0.5)));

	vec3 col = mix(low, mid, diagonal);
	col = mix(col, accent, lower_glow * 0.24);
	col = mix(col, high, top_glow * mix(0.26, 0.34, highlighted));
	col = mix(col, vec3(1.0), sweep * mix(0.08, 0.13, highlighted));
	col *= 1.0 - vignette * 0.2;

	float border_width = mix(2.25, 3.25, highlighted);
	float on_border = smoothstep(-aa, aa, d + border_width);
	float border_mix = on_border * mix(0.86, 0.94, highlighted);
	col = mix(col, border, border_mix);
	float out_alpha = mix(a, mix(0.9, 1.0, highlighted), border_mix);
	COLOR = vec4(col, out_alpha * shape);
}
