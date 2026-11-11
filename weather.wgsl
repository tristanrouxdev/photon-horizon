// ============================================================================
// Photon Horizon — Weather Stage (Rain & Snow Lighting)
// Ported from Photon Shaders include/lighting/colors/weather_color.glsl
// ============================================================================

fn weather(input: WeatherInput) -> vec4<f32> {
    if input.color.a <= 0.01 {
        return vec4<f32>(0.0);
    }

    let block_lm = clamp(input.light.x, 0.0, 1.0);
    let sky_lm = clamp(input.light.y, 0.0, 1.0);

    // Photon weather scattering color from sun + sky ambient + warm blocklight
    let weather_light = (sun_color() * 0.18 + ambient_color() * 0.95) * smoothstep(0.0, 0.9, sky_lm)
        + photon_blocklight_color() * get_blocklight_falloff(block_lm) * 0.75;

    let final_rgb = input.color.rgb * max(weather_light, vec3<f32>(0.04));
    let final_alpha = input.color.a * select(0.52, 0.75, input.snow);

    return vec4<f32>(final_rgb, final_alpha);
}
