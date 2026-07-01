uniform vec4 uColor;
uniform float uTime;

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 screen_coords) {
    vec2 uv = texture_coords - vec2(0.5);
    float dist = length(uv);

    float pulse = 1.0 + sin(uTime * 12.0) * 0.15;
    float core = smoothstep(0.45 * pulse, 0.05, dist);
    float glow = exp(-dist * 3.5) * 0.7;
    float aura = exp(-dist * 2.0) * 0.3;
    float ring = smoothstep(0.35, 0.3, dist) - smoothstep(0.3, 0.25, dist);
    ring *= (sin(uTime * 8.0 + dist * 10.0) * 0.5 + 0.5);

    vec4 finalColor = uColor * (core + glow + aura + ring * 0.4);
    finalColor.a = max(core, max(glow * 0.6, aura * 0.3));
    finalColor.rgb += vec3(sin(uTime * 6.0) * 0.05);
    return finalColor;
}
