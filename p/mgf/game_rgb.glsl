uniform float uTime;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 pixel = Texel(tex, texture_coords);
    float t = uTime * 0.3;
    float r = pixel.r * (0.8 + 0.2 * sin(t + screen_coords.y * 0.005));
    float g = pixel.g * (0.8 + 0.2 * sin(t + 2.094 + screen_coords.x * 0.004));
    float b = pixel.b * (0.8 + 0.2 * sin(t + 4.189 + screen_coords.y * 0.003 + screen_coords.x * 0.002));
    r += sin(screen_coords.x * 0.003 + t * 2.0) * 0.04;
    g += sin(screen_coords.y * 0.004 + t * 1.7) * 0.04;
    b += sin((screen_coords.x + screen_coords.y) * 0.002 + t * 2.3) * 0.04;
    return vec4(r, g, b, pixel.a);
}
