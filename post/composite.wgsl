// ============================================================================
// Photon Horizon — Post Pass 4: Composite, Bloom, Purkinje Shift & Tonemapping
// Ported from Photon Shaders tonemap_operators.glsl & color_grading.glsl
// ============================================================================

override tonemap_operator: u32 = 0u;
override exposure: f32 = 1.0;
override bloom_strength: f32 = 0.35;
override end_bloom_boost: f32 = 1.2;
override contrast: f32 = 1.05;
override saturation: f32 = 1.08;
override purkinje_shift: bool = true;
override vignette: bool = true;

fn post(input: PostInput) -> vec4<f32> {
    let uv = input.uv;
    var hdr = input.color.rgb;

    // Add wide + tight dual-scale bloom (`bloom_a` and `bloom_b`)
    let bloom_tight = textureSampleLevel(bloom_a, linear_sampler, uv, 0.0).rgb;
    let bloom_wide = textureSampleLevel(bloom_b, linear_sampler, uv, 0.0).rgb;
    let bloom_col = mix(bloom_tight, bloom_wide, 0.72);
    let bloom_mult = select(bloom_strength * 0.45, bloom_strength * 0.45 * end_bloom_boost, frame.dimension == 1);
    hdr += bloom_col * bloom_mult;

    // Apply Exposure
    hdr *= exposure;

    // Photon Purkinje Mesopic Vision Shift (subtle blue-cyan rod response in low light)
    if purkinje_shift && frame.dimension == 0 {
        let lum = luminance(hdr);
        let scotopic = exp(-lum * 16.0) * night_factor() * 0.38;
        let rod_tint = vec3<f32>(0.62, 0.84, 1.32) * lum;
        hdr = mix(hdr, rod_tint, scotopic);
    }

    // Photon Tonemap Operator (0: ACES Fit, 1: Hejl-Burgess, 2: Lottes, 3: Ozius)
    var ldr = photon_tonemap(hdr, tonemap_operator);

    // Contrast & Saturation Grading (Photon color_grading.glsl)
    ldr = clamp((ldr - 0.5) * contrast + 0.5, vec3<f32>(0.0), vec3<f32>(1.0));
    let luma = luminance(ldr);
    ldr = clamp(mix(vec3<f32>(luma), ldr, saturation), vec3<f32>(0.0), vec3<f32>(1.0));

    // Subtle cinematic vignette
    if vignette {
        let centered = uv * 2.0 - 1.0;
        let vig = 1.0 - dot(centered, centered) * 0.14;
        ldr *= clamp(vig, 0.72, 1.0);
    }

    return vec4<f32>(ldr, 1.0);
}
