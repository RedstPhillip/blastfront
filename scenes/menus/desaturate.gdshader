shader_type canvas_item;

// Pulls a painted backdrop towards the UI's neutral palette: partly desaturated, slightly warm, a touch darker.

uniform float amount : hint_range(0.0, 1.0) = 0.65;
uniform vec4 tint : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform float brightness = 0.9;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	vec3 grey = vec3(luma) * tint.rgb;
	COLOR = vec4(mix(c.rgb, grey, amount) * brightness, c.a);
}
