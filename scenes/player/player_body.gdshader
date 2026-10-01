shader_type canvas_item;

// Ball body: soft spherical shading with a moonlit top rim, status tint and hit flash.

uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform vec4 status_tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float status_amount : hint_range(0.0, 1.0) = 0.0;
uniform float rim_strength = 0.28;
uniform vec4 rim_color : source_color = vec4(0.85, 1.0, 0.92, 1.0);

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec4 base = tex * COLOR;
	vec2 c = UV - 0.5;
	float shade = clamp(-c.y * 1.6, -1.0, 1.0);
	vec3 col = base.rgb * (1.0 + shade * 0.14);
	float radius = length(c) * 2.0;
	float rim = smoothstep(0.7, 0.86, radius) * (1.0 - smoothstep(0.86, 0.96, radius)) * smoothstep(0.15, -0.35, c.y);
	col += rim_color.rgb * rim * rim_strength;
	col = mix(col, status_tint.rgb * (0.6 + 0.4 * dot(col, vec3(0.333))), status_amount);
	col = mix(col, flash_color.rgb, flash);
	COLOR = vec4(col, base.a);
}
