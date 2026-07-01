uniform float uTime;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    float pixels = 120.0 + sin(uTime * 0.5) * 20.0;
    float aspect = 640.0 / 480.0;
    vec2 dxy = vec2(1.0 / pixels, 1.0 / pixels / aspect);
    vec2 coord = dxy * floor(texture_coords / dxy);
    vec4 pixel = Texel(tex, coord);
    float edge = 0.0;
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            if (i == 0 && j == 0) continue;
            vec2 offset = vec2(float(i), float(j)) * dxy;
            vec4 neighbor = Texel(tex, coord + offset);
            edge += length(pixel.rgb - neighbor.rgb);
        }
    }
    edge /= 8.0;
    pixel.rgb += edge * 0.5;
    return pixel;
}
