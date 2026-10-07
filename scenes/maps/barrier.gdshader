shader_type canvas_item;
render_mode unshaded, blend_add;

// Energy barrier along a map edge, tinted per world (MapProfile.border_color). `across` runs from the playable side (0) to the outside (1);
// the boundary sits at `edge`. Glows up near characters and ripples when something hits it.

uniform vec4 color : source_color = vec4(0.62, 1.0, 0.72, 1.0);
// Hit ripples flash towards this warm white whatever the tint, so a hit still reads as one.
uniform vec4 hit_color : source_color = vec4(1.0, 0.9, 0.74, 1.0);
uniform float base_intensity = 0.09;
uniform float edge = 0.333;
uniform int axis = 0;
uniform bool flip = false;
uniform vec2 pushers[4];
uniform vec4 hit = vec4(0.0, 0.0, 10.0, 0.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hex(vec2 p) {
	p.x *= 1.1547;
	p.y += mod(floor(p.x), 2.0) * 0.5;
	p = abs(mod(p, 1.0) - 0.5);
	return abs(max(p.x * 1.5 + p.y, p.y * 2.0) - 1.0);
}

void fragment() {
	float across = axis == 0 ? UV.y : UV.x;
	if (flip) {
		across = 1.0 - across;
	}
	float d = across - edge;
	float line = exp(-abs(d) * 70.0);
	float inner_glow = d < 0.0 ? exp(d * 10.0) * 0.4 : 0.0;
	float outer = d > 0.0 ? exp(-d * 3.0) : 0.0;
	float pattern = smoothstep(0.1, 0.0, hex(world * 0.045 + vec2(0.0, TIME * 0.05))) * outer;

	float prox = 0.0;
	for (int i = 0; i < 4; i++) {
		float dist = length(world - pushers[i]);
		prox = max(prox, exp(-pow(dist / 150.0, 2.0)));
	}
	float scan = 0.5 + 0.5 * sin((world.x + world.y) * 0.03 - TIME * 3.0);
	float intensity = base_intensity * (0.55 + 0.45 * scan) + prox * 1.6;

	float hit_dist = length(world - hit.xy);
	float hit_front = hit.z * 520.0;
	float ripple = exp(-pow((hit_dist - hit_front) / 22.0, 2.0)) * hit.w * max(0.0, 1.0 - hit.z * 1.8);
	float hit_core = exp(-pow(hit_dist / 60.0, 2.0)) * hit.w * max(0.0, 1.0 - hit.z * 4.0);

	float glow = (line * 1.3 + inner_glow + pattern * 0.55) * intensity;
	float flash = (ripple + hit_core) * (line + outer + 0.2);
	float a = clamp(glow + flash, 0.0, 1.5);
	vec3 rgb = color.rgb * glow + mix(color.rgb, hit_color.rgb, 0.75) * flash;
	COLOR = vec4(rgb * (a / max(glow + flash, 0.0001)), a);
}
