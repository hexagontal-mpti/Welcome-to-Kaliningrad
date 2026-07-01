uniform sampler2D uPalette;
uniform bool uEnabled;

vec3 palette[8];

void readPalette() {
    for (int i = 0; i < 8; i++) {
        float u = (float(i) + 0.5) / 8.0;
        palette[i] = Texel(uPalette, vec2(u, 0.5)).rgb;
    }
}

vec3 findClosest(vec3 col) {
    float minDist = 1000.0;
    vec3 closest = palette[0];
    for (int i = 0; i < 8; i++) {
        vec3 diff = col - palette[i];
        float d = dot(diff, diff);
        if (d < minDist) {
            minDist = d;
            closest = palette[i];
        }
    }
    return closest;
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec4 pixel = Texel(tex, texture_coords);
    if (!uEnabled) return pixel;

    readPalette();
    vec3 mapped = findClosest(pixel.rgb);
    return vec4(mapped, pixel.a);
}
