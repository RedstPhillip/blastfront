shader_type canvas_item;

uniform vec4 color1 : source_color = vec4(0.9, 0.2, 0.4, 1.0); // Pink
uniform vec4 color2 : source_color = vec4(1.0, 0.5, 0.2, 1.0); // Orange
uniform float speed = 0.05;

// Basic noise function
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// Fractal Brownian Motion (stacks layers of noise)
float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 5; i++) {
        v += a * noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

void fragment() {
    vec2 uv = UV * 3.0; // Scale of the fractal
    float t = TIME * speed;
    
    // Create movement by warping the UVs with noise
    float n = fbm(uv + vec2(t, t * 0.5));
    n = fbm(uv + n); 
    
    // Blend between your two colors based on the fractal value
    COLOR = mix(color1, color2, n);
}
