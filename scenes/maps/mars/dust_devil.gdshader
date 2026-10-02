shader_type canvas_item;
render_mode unshaded;

// A whirling dust column: narrow at the ground, flaring and thinning towards the top, with spiralling
// streaks scrolling around it and a dust skirt where it touches the ground.

uniform sampler2D noise_tex : repeat_enable, filter_linear_mipmap;
uniform vec4 dust_color : source_color = vec4(0.82, 0.52, 0.33, 1.0);
uniform float strength = 0.55;
uniform float spin = 1.6;

void fragment() {
	float t = 1.0 - UV.y;
	float u = UV.x - 0.5;
	float lean = sin(t * 3.0 + TIME * 0.7) * 0.05 * t;
	float width = mix(0.07, 0.46, pow(t, 1.3));
	float x = (u - lean) / width;
	float body = 1.0 - smoothstep(0.55, 1.0, abs(x));
	vec2 p = vec2(x * 0.35 + TIME * spin * 0.25 + t * 1.8, t * 1.4 - TIME * 0.45);
	float streaks = texture(noise_tex, p * 0.5).r * 0.7 + texture(noise_tex, p * vec2(1.3, 0.6) + 0.37).g * 0.5;
	float density = body * smoothstep(0.25, 0.85, streaks);
	density *= smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.65, 1.0, t));
	float skirt = exp(-pow(t * 9.0, 2.0)) * (1.0 - smoothstep(0.2, 0.5, abs(u))) * texture(noise_tex, vec2(u * 2.0 + TIME * 0.2, TIME * 0.1)).b;
	float alpha = clamp(density * strength + skirt * strength * 0.8, 0.0, 1.0) * COLOR.a;
	COLOR = vec4(dust_color.rgb * mix(0.85, 1.12, t), alpha);
}
