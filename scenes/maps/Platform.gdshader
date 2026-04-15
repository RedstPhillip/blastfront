shader_type canvas_item;

uniform vec4 color1 : source_color = vec4(0.9, 0.2, 0.4, 1.0);
uniform vec4 color2 : source_color = vec4(1.0, 0.5, 0.2, 1.0);

uniform float speed = 1.5;
uniform float scale = 2.5;
uniform float warp1 = 1.2;
uniform float warp2 = 2.0;



// Hash
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}



// Smooth noise
float noise(vec2 p) {

    vec2 i = floor(p);
    vec2 f = fract(p);

    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));

    vec2 u = f * f * (3.0 - 2.0 * f);

    return mix(a, b, u.x) +
           (c - a) * u.y * (1.0 - u.x) +
           (d - b) * u.x * u.y;
}



// Fractal Brownian Motion
float fbm(vec2 p) {

    float v = 0.0;
    float a = 0.5;

    for (int i = 0; i < 6; i++) {

        v += a * noise(p);

        p *= 2.0;
        a *= 0.5;
    }

    return v;
}



// Heavy domain warping (big visual improvement)
float warpedFbm(vec2 p, float t) {

    vec2 q;

    q.x = fbm(p + vec2(0.0, 0.0) + t);
    q.y = fbm(p + vec2(5.2, 1.3) - t);

    vec2 r;

    r.x = fbm(p + warp1 * q + vec2(1.7, 9.2) + t * 0.7);
    r.y = fbm(p + warp1 * q + vec2(8.3, 2.8) - t * 0.6);

    float f = fbm(p + warp2 * r);

    return f;
}



void fragment() {

    vec2 uv = SCREEN_UV;

    float t = TIME * speed;

    // Large coordinate space = less repetition
    vec2 p = uv * scale * 8.0;

    float n = warpedFbm(p, t);

    // Increase contrast → more abstract shapes
    n = smoothstep(0.25, 0.75, n);

    vec4 col = mix(color1, color2, n);

    float alpha = texture(TEXTURE, UV).a;

    COLOR = vec4(col.rgb, alpha);
}