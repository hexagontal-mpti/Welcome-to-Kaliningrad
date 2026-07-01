uniform float uTime;

float rand(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;
    float noise = rand(vec2(floor(uv.x * 300.0), floor(uv.y * 300.0 + uTime * 5.0)));
    if (noise > 0.97) {
        uv.x += (rand(vec2(uTime, uv.y)) - 0.5) * 0.05;
    }
    vec4 pixel = Texel(tex, uv);
    float glitch = step(0.98, rand(vec2(floor(uv.y * 50.0), floor(uTime * 4.0))));
    pixel.r = mix(pixel.r, Texel(tex, uv + vec2(glitch * 0.02, 0.0)).r, 0.8);
    pixel.b = mix(pixel.b, Texel(tex, uv - vec2(glitch * 0.02, 0.0)).b, 0.8);
    float grain = rand(uv + vec2(uTime)) * 0.08;
    pixel.rgb += grain - 0.04;
    return pixel;
}
