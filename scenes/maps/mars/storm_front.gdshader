shader_type canvas_item;
render_mode unshaded;

// A distant dust storm rolling along the horizon: a churning wall with a billowing, sun-lit top edge
// that thins out towards its leading side. `intensity` is raised by the weather during gusts.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 body_color : source_color = vec4(0.3, 0.13, 0.09, 1.0);
uniform vec4 lit_color : source_color = vec4(0.95, 0.66, 0.46, 1.0);
uniform float intensity = 1.0;
uniform float aspect = 4.8;

void fragment() {
	vec2 uv = UV;
	float churn = TIME * 0.012;
	float billow = texture(noise_tex, vec2(uv.x * 1.4 * aspect * 0.25 - churn, 0.3)).r * 0.6
		+ texture(noise_tex, vec2(uv.x * 3.1 * aspect * 0.25 + churn * 1.7, 0.7)).g * 0.4;
	// Lower towards the leading (right) edge, piled up on the left.
	float top = mix(0.12, 0.6, smoothstep(0.1, 1.0, uv.x)) + (billow - 0.5) * 0.28;
	float edge = smoothstep(top, top + 0.12, uv.y);
	float detail = texture(noise_tex, uv * vec2(aspect, 1.0) * 0.9 + vec2(-churn * 2.0, churn)).b;
	float body = edge * (0.9 + detail * 0.3);
	float fade_x = 1.0 - smoothstep(0.72, 1.0, uv.x);
	fade_x *= smoothstep(0.0, 0.08, uv.x);
	float fade_y = 1.0 - smoothstep(0.88, 1.0, uv.y);
	float rim = smoothstep(top, top + 0.05, uv.y) * (1.0 - smoothstep(top + 0.05, top + 0.2, uv.y));
	vec3 col = mix(body_color.rgb, lit_color.rgb, rim * 0.55 + (1.0 - uv.y) * 0.15);
	col *= 0.9 + detail * 0.2;
	float alpha = clamp(body * fade_x * fade_y * (0.62 + 0.38 * intensity), 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
