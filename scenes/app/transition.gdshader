shader_type canvas_item;
render_mode unshaded;

// Full-screen diagonal wipe with a bright leading edge. progress 0 = clear, 1 = fully covered.
// direction flips which side the wipe travels towards.

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float direction = 1.0;
uniform float slant = 0.35;
uniform vec4 cover_color : source_color = vec4(0.03, 0.055, 0.06, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.71, 0.28, 1.0);
uniform float aspect = 1.7777;

void fragment() {
	vec2 uv = UV;
	float x = direction > 0.0 ? uv.x : 1.0 - uv.x;
	float coordinate = x * aspect + (1.0 - uv.y) * slant * aspect;
	float span = aspect * (1.0 + slant) + 0.3;
	float front = progress * span - 0.15;
	float covered = step(coordinate, front);
	float edge = smoothstep(0.0, 0.018, front - coordinate) * (1.0 - smoothstep(0.018, 0.045, front - coordinate));
	float stripe = step(0.5, fract((coordinate - front) * 9.0)) * (1.0 - smoothstep(0.0, 0.25, coordinate - front)) * step(front, coordinate);
	vec3 col = cover_color.rgb;
	float alpha = covered;
	col = mix(col, edge_color.rgb, edge);
	alpha = max(alpha, edge);
	col = mix(col, edge_color.rgb * 0.6, stripe * 0.5);
	alpha = max(alpha, stripe * 0.35 * step(0.001, progress) * step(progress, 0.999));
	COLOR = vec4(col, alpha);
}
