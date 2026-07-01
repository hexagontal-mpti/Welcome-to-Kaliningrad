uniform float uTime;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;
    uv.y += sin(uv.x * 40.0 + uTime * 2.0) * 0.003;
    vec4 pixel = Texel(tex, uv);
    float scanline = sin(screen_coords.y * 1.5 + uTime * 3.0) * 0.04;
    pixel.rgb -= scanline;
    float vignette = 1.0 - length(texture_coords - 0.5) * 0.8;
    pixel.rgb *= vignette;
    return pixel;
}
