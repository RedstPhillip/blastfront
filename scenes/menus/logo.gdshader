shader_type canvas_item;

// Title text: vertical metal gradient with a periodic diagonal shine sweep.

uniform vec4 top_color : source_color = vec4(1.0, 0.96, 0.86, 1.0);
uniform vec4 bottom_color : source_color = vec4(1.0, 0.66, 0.24, 1.0);
uniform float text_top = 0.0;
uniform float text_bottom = 110.0;
uniform float shine_period = 4.5;
uniform float shine_width = 46.0;

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float t = clamp((local.y - text_top) / max(text_bottom - text_top, 1.0), 0.0, 1.0);
	vec3 col = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.35, 1.0, t));
	float sweep = mod(TIME, shine_period) / shine_period;
	float band_x = mix(-200.0, 1100.0, sweep);
	float d = abs((local.x + local.y * 0.45) - band_x);
	float shine = 1.0 - smoothstep(0.0, shine_width, d);
	col = mix(col, vec3(1.0), shine * 0.75);
	COLOR = vec4(col, tex.a * COLOR.a);
}
