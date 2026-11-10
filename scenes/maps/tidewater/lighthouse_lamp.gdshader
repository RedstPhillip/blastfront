shader_type canvas_item;
render_mode blend_add, unshaded;

// The lamp of the far lighthouse: a steady ember that flares wide each time the beam swings past.

uniform float period = 7.0;

varying float sweep;

void vertex() {
	float turn = sin(TIME * TAU / period);
	sweep = pow(max(turn, 0.0), 14.0);
	VERTEX.x *= 1.0 + sweep * 4.5;
	VERTEX.y *= 1.0 + sweep * 0.5;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	COLOR = vec4(COLOR.rgb * tex.rgb, tex.a * COLOR.a * (0.3 + sweep * 0.7));
}
