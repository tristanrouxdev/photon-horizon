// ============================================================================
// Photon Horizon — Post Pass 3: Dual-Ring 13-Tap Wide Gaussian Bloom Blur
// Reads `bloom_a` and writes wide soft bloom to `bloom_b`
// ============================================================================

fn tap_bloom(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(bloom_a, linear_sampler, clamp(uv, vec2<f32>(0.002), vec2<f32>(0.998)), 0.0).rgb;
}

fn post(input: PostInput) -> vec4<f32> {
    let uv = input.uv;
    let t = 4.0 / max(frame.resolution, vec2<f32>(1.0));

    var acc = tap_bloom(uv) * 0.22;

    let r1 = t * 1.5;
    acc += tap_bloom(uv + vec2<f32>( r1.x,  0.0 )) * 0.11;
    acc += tap_bloom(uv + vec2<f32>(-r1.x,  0.0 )) * 0.11;
    acc += tap_bloom(uv + vec2<f32>( 0.0,   r1.y)) * 0.11;
    acc += tap_bloom(uv + vec2<f32>( 0.0,  -r1.y)) * 0.11;

    let r2 = t * 2.8;
    acc += tap_bloom(uv + vec2<f32>( r2.x,  r2.y)) * 0.055;
    acc += tap_bloom(uv + vec2<f32>(-r2.x,  r2.y)) * 0.055;
    acc += tap_bloom(uv + vec2<f32>( r2.x, -r2.y)) * 0.055;
    acc += tap_bloom(uv + vec2<f32>(-r2.x, -r2.y)) * 0.055;

    let r3 = t * 5.2;
    acc += tap_bloom(uv + vec2<f32>( r3.x,  0.0 )) * 0.03;
    acc += tap_bloom(uv + vec2<f32>(-r3.x,  0.0 )) * 0.03;
    acc += tap_bloom(uv + vec2<f32>( 0.0,   r3.y)) * 0.03;
    acc += tap_bloom(uv + vec2<f32>( 0.0,  -r3.y)) * 0.03;

    return vec4<f32>(acc, 1.0);
}
