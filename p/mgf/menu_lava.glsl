uniform float uTime;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 4; i++) {
        v += a * noise(p);
        p *= 2.0;
        a *= 0.5;
    }
    return v;
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;

    float gridSize = 20.0;
    vec2 block = floor(uv * gridSize) / gridSize;

    float t = uTime * 0.12;
    float n = fbm(block * 3.0 + vec2(t, t * 0.5));

    n += (1.0 - uv.y) * 0.35;

    n = clamp(n, 0.0, 1.0);
    n = n * n;

    vec3 col1 = vec3(0.25, 0.03, 0.1);
    vec3 col2 = vec3(0.9, 0.2, 0.02);
    vec3 col3 = vec3(1.0, 0.55, 0.05);
    vec3 col4 = vec3(1.0, 0.8, 0.2);

    vec3 col;
    if (n < 0.25) {
        col = mix(col1, col2, n / 0.25);
    } else if (n < 0.5) {
        col = mix(col2, col3, (n - 0.25) / 0.25);
    } else {
        col = mix(col3, col4, (n - 0.5) / 0.5);
    }

    float glow = exp(-length(uv - vec2(0.5, 0.85)) * 2.0) * 0.4;
    col += vec3(1.0, 0.35, 0.0) * glow;

    float sparks = pow(noise(block * 50.0 + vec2(0.0, -t * 5.0)), 10.0) * 1.8;
    col += vec3(1.0, 0.85, 0.3) * sparks;

    float vignette = 1.0 - length(uv - 0.5) * 1.0;
    col *= vignette;

    col = pow(col, vec3(0.95));

    return vec4(col, 1.0);
}
