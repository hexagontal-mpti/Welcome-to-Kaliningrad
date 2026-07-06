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

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;

    float cols = 30.0;
    float rows = 20.0;

    vec2 block = floor(uv * vec2(cols, rows));
    vec2 blockUV = fract(uv * vec2(cols, rows));

    float colSeed = hash(vec2(block.x, 0.0));
    float speed = 0.3 + colSeed * 0.5;

    float streamY = uv.y + uTime * speed;
    float rowBlock = floor(streamY * rows);

    float headPos = hash(vec2(block.x, floor(rowBlock))) * rows;
    float dist = abs(mod(streamY * rows, rows) - headPos);

    float brightness = 0.0;

    float head = exp(-dist * 0.8) * 0.7;
    float body = exp(-dist * 0.3) * 0.25;
    brightness = head + body;

    float cellRand = hash(vec2(block.x, rowBlock));
    brightness *= step(0.15, cellRand);

    float flicker = 0.9 + 0.1 * sin(uTime * 3.0 + block.x * 2.0);
    brightness *= flicker;

    vec3 darkGreen = vec3(0.0, 0.05, 0.0);
    vec3 midGreen = vec3(0.0, 0.6, 0.1);
    vec3 brightGreen = vec3(0.2, 1.0, 0.3);
    vec3 whiteGreen = vec3(0.8, 1.0, 0.8);

    vec3 col;
    if (brightness < 0.3) {
        col = mix(darkGreen, midGreen, brightness / 0.3);
    } else if (brightness < 0.6) {
        col = mix(midGreen, brightGreen, (brightness - 0.3) / 0.3);
    } else {
        col = mix(brightGreen, whiteGreen, (brightness - 0.6) / 0.4);
    }

    float vignette = 1.0 - length(uv - 0.5) * 0.8;
    col *= vignette;

    return vec4(col, 1.0);
}
