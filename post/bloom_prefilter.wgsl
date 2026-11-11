// ============================================================================
// Photon Horizon — Post Pass 2: Quarter-Resolution Karis-Average Bloom Prefilter
// Extracts bright highlights (sun, emissive blocks, IterationT Black Hole & Planet)
// ============================================================================

override end_bloom_boost: f32 = 1.2;

fn sample_karis(uv: vec2<f32>) -> vec3<f32> {
    let clamped_uv = clamp(uv, vec2<f32>(0.001), vec2<f32>(0.999));
    let c = max(textureSampleLevel(previous, linear_sampler, clamped_uv, 0.0).rgb, vec3<f32>(0.0));
    let surf = surface_at(vec2<i32>(clamped_uv * frame.resolution));
    // `surf.data` stores the material stage's `emissive`
    let boosted = c * (1.0 + surf.data * 1.65);
    let lum = luminance(boosted);
    let threshold = select(0.75, 0.45, frame.dimension == 1);
    let soft_knee = smoothstep(threshold * 0.5, threshold * 1.6, lum);
    let weight = 1.0 / (1.0 + lum * 0.18);
    return boosted * soft_knee * weight;
}

fn post(input: PostInput) -> vec4<f32> {
    let texel = 1.0 / max(frame.resolution, vec2<f32>(1.0));
    let uv = input.uv;

    let c0 = sample_karis(uv);
    let c1 = sample_karis(uv + vec2<f32>(-texel.x, -texel.y));
    let c2 = sample_karis(uv + vec2<f32>( texel.x, -texel.y));
    let c3 = sample_karis(uv + vec2<f32>(-texel.x,  texel.y));
    let c4 = sample_karis(uv + vec2<f32>( texel.x,  texel.y));

    var bloom = (c0 * 2.0 + c1 + c2 + c3 + c4) / 6.0;
    if frame.dimension == 1 {
        bloom *= end_bloom_boost;
    }

    return vec4<f32>(bloom, 1.0);
}
