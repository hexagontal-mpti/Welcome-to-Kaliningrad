uniform float uTime;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;
    float amount = 0.004 + sin(uTime * 1.5) * 0.002;
    vec4 r = Texel(tex, uv + vec2(amount, 0.0));
    vec4 g = Texel(tex, uv);
    vec4 b = Texel(tex, uv - vec2(amount, 0.0));
    vec4 pixel = vec4(r.r, g.g, b.b, g.a);
    float wave = sin(uv.y * 100.0 + uTime * 5.0) * 0.001;
    vec4 shifted = Texel(tex, uv + vec2(wave, 0.0));
    pixel.rgb = mix(pixel.rgb, shifted.rgb, 0.3);
    return pixel;
}
