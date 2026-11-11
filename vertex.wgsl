// ============================================================================
// Photon Horizon — Wind & Foliage Vertex Displacement
// Ported from Photon Shaders waving foliage & plants
// Note: `vertex` returns the new camera-relative position (`input.position + offset`).
// ============================================================================

override waving_plants: bool = true;
override wind_strength: f32 = 1.0;

fn vertex(input: VertexInput) -> vec3<f32> {
    if !waving_plants || input.material == 0u || wind_strength <= 0.001 {
        return input.position;
    }

    let pos = input.position + frame.camera_position;
    let weather_boost = 1.0 + frame.rain * 0.55 + frame.thunder * 0.65;
    let speed = frame.time * (2.1 + frame.rain * 0.85);
    let amp = 0.032 * wind_strength * weather_boost;

    let gust = 0.65 + 0.35 * sin(pos.x * 0.18 + pos.z * 0.14 + frame.time * 0.75);
    let phase = pos.x * 1.65 + pos.z * 1.35 + pos.y * 0.85;
    let wave_x = sin(speed + phase) + 0.42 * cos(speed * 1.47 + phase * 1.9);
    let wave_z = cos(speed * 0.88 + phase * 1.2) + 0.38 * sin(speed * 1.33 - phase * 1.6);

    let frac_y = fract(pos.y);

    if input.material == MAT_LEAVES {
        let leaf_ripple = sin(speed * 2.3 + dot(pos, vec3<f32>(3.1, 2.7, 2.9))) * 0.28;
        let offset = vec3<f32>(wave_x + leaf_ripple, leaf_ripple * 0.45, wave_z) * (amp * 0.65 * gust);
        return input.position + offset;
    }

    if input.material == MAT_PLANT {
        let weight = clamp(frac_y * 1.25, 0.0, 1.0);
        let offset = vec3<f32>(wave_x, 0.0, wave_z) * (amp * 1.15 * gust * weight);
        return input.position + offset;
    }

    if input.material == MAT_TALL_LOWER {
        let weight = clamp(frac_y, 0.0, 1.0) * 0.55;
        let offset = vec3<f32>(wave_x, 0.0, wave_z) * (amp * 1.25 * gust * weight);
        return input.position + offset;
    }

    if input.material == MAT_TALL_UPPER {
        let weight = 0.55 + clamp(frac_y, 0.0, 1.0) * 0.65;
        let offset = vec3<f32>(wave_x, 0.0, wave_z) * (amp * 1.25 * gust * weight);
        return input.position + offset;
    }

    if input.material == MAT_VINE {
        let offset = vec3<f32>(wave_x, 0.0, wave_z) * (amp * 0.75 * gust);
        return input.position + offset;
    }

    return input.position;
}
