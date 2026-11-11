// ============================================================================
// Photon Horizon — Post Pass 5: FXAA + Contrast Adaptive Sharpening (CAS)
// Ported from Photon Shaders fxaa.glsl & cas.glsl
// ============================================================================

override fxaa_cas: bool = true;

fn sample_prev(uv: vec2<f32>) -> vec3<f32> {
    return textureSampleLevel(previous, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
}

fn post(input: PostInput) -> vec4<f32> {
    let uv = input.uv;
    let c = input.color.rgb;
    if !fxaa_cas {
        return vec4<f32>(c, 1.0);
    }

    let texel = 1.0 / max(frame.resolution, vec2<f32>(1.0));
    let n = sample_prev(uv + vec2<f32>( 0.0, -texel.y));
    let s = sample_prev(uv + vec2<f32>( 0.0,  texel.y));
    let e = sample_prev(uv + vec2<f32>( texel.x,  0.0));
    let w = sample_prev(uv + vec2<f32>(-texel.x,  0.0));

    let lc = luminance(c);
    let ln = luminance(n);
    let ls = luminance(s);
    let le = luminance(e);
    let lw = luminance(w);

    let l_min = min(lc, min(min(ln, ls), min(le, lw)));
    let l_max = max(lc, max(max(ln, ls), max(le, lw)));
    let l_range = l_max - l_min;

    // High-contrast silhouette edge -> FXAA directional smoothing
    if l_range > max(0.06, l_max * 0.14) {
        let dir = clamp(vec2<f32>(-((ln + lw) - (ls + le)), (ln + le) - (ls + lw)) * 2.5, vec2<f32>(-2.0), vec2<f32>(2.0)) * texel;
        let f1 = sample_prev(uv + dir * (1.0 / 3.0 - 0.5));
        let f2 = sample_prev(uv + dir * (2.0 / 3.0 - 0.5));
        let fxaa_col = (f1 + f2) * 0.5;
        return vec4<f32>(mix(c, fxaa_col, 0.65), 1.0);
    }

    // Interior detail -> AMD FidelityFX Contrast Adaptive Sharpening (CAS)
    let min_rgb = min(c, min(min(n, s), min(e, w)));
    let max_rgb = max(c, max(max(n, s), max(e, w)));
    let amp = clamp(min(min_rgb, 1.0 - max_rgb) / max(max_rgb, vec3<f32>(1e-4)), vec3<f32>(0.0), vec3<f32>(1.0));
    let w_cas = -sqrt(amp) * 0.12;
    let sharpened = clamp((c + (n + s + e + w) * w_cas) / (1.0 + 4.0 * w_cas), vec3<f32>(0.0), vec3<f32>(1.0));

    return vec4<f32>(sharpened, 1.0);
}
