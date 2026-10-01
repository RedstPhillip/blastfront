shader_type canvas_item;
render_mode unshaded;

// Frosted-glass backdrop for overlays: blurred, darkened and slightly desaturated scene.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec4 tint : source_color = vec4(0.02, 0.05, 0.055, 1.0);

void fragment() {
	vec3 sharp = texture(screen_tex, SCREEN_UV).rgb;
	vec3 blurred = textureLod(screen_tex, SCREEN_UV, 3.0).rgb * 0.5 + textureLod(screen_tex, SCREEN_UV, 4.5).rgb * 0.5;
	vec3 col = mix(sharp, blurred, amount);
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(luma), 0.35 * amount);
	col = mix(col, tint.rgb, 0.58 * amount);
	COLOR = vec4(col, 1.0);
}
