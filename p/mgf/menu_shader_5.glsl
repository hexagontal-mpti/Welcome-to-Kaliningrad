uniform float uTime;

float bayer2x2(vec2 a) {
    a = floor(a);
    return fract(dot(a, vec2(2.0, 4.0)) / 4.0);
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords;
    vec4 pixel = Texel(tex, uv);
    float d = bayer2x2(screen_coords * 0.5);
    float threshold = 0.5 + sin(uTime * 0.8) * 0.15;
    vec3 palette[4];
    palette[0] = vec3(0.05, 0.05, 0.1);
    palette[1] = vec3(0.2, 0.3, 0.6);
    palette[2] = vec3(0.7, 0.4, 0.3);
    palette[3] = vec3(0.95, 0.9, 0.8);
    float luminance = dot(pixel.rgb, vec3(0.299, 0.587, 0.114));
    float quantized = floor((luminance + d * 0.15) * 3.0) / 3.0;
    vec3 mapped;
    if (quantized < 0.33) mapped = palette[0];
    else if (quantized < 0.66) mapped = palette[1];
    else if (quantized < 0.9) mapped = palette[2];
    else mapped = palette[3];
    float shift = sin(uv.y * 200.0 + uTime * 3.0) * 0.002;
    vec4 pixel2 = Texel(tex, uv + vec2(shift, 0.0));
    float lum2 = dot(pixel2.rgb, vec3(0.299, 0.587, 0.114));
    mapped += vec3(lum2 * 0.05, 0.0, lum2 * 0.08);
    return vec4(mapped, pixel.a);
}
