uniform vec4 uColor;
uniform float uLife;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords - vec2(0.5);
    float dist = length(uv);
    float alpha = smoothstep(0.5, 0.0, dist) * uLife;
    vec4 finalColor = uColor;
    finalColor.a = alpha;
    return finalColor;
}
