// ============================================================================
// Photon Horizon — Post Pass 1: IterationT End Sky + Photon Atmosphere, GTAO & God Rays
// - In The End (frame.dimension == 1):
//   Renders IterationT's Giant Ringed Planet (PlanetEnd2), Gravitational-Lensed
//   Black Hole + Relativistic Accretion Disc, Procedural Starfield, and End Fog!
// - In Overworld (0) & Nether (-1):
//   Renders Screen-Space GTAO, Underwater Caustics, Volumetric God Rays, and Fog.
// ============================================================================

override end_planet_enabled: bool = true;
override end_blackhole_enabled: bool = true;
override end_planet_cycle: f32 = 1.0;
override end_planet_angle: f32 = 28.0;
override end_doppler: bool = true;

override god_rays: f32 = 0.8;
override fog_density: f32 = 1.0;
override gtao_strength: f32 = 0.75;
override underwater_caustics: bool = true;

// Evaluate full IterationT End Sky along world-space ray `ray_dir`
fn render_iteration_end_sky(ray_dir: vec3<f32>, tf: f32, pixel: vec2<f32>) -> vec3<f32> {
    let nebula = fbm3(ray_dir * 2.4 + vec3<f32>(0.3, -0.5, 0.8));
    var sky_col = mix(
        vec3<f32>(0.010, 0.007, 0.020),
        vec3<f32>(0.036, 0.022, 0.058),
        nebula * smoothstep(-0.45, 0.65, ray_dir.y)
    );

    let ldir = end_light_dir();
    let dither = interleaved_gradient_noise(pixel);

    // 1. IterationT Gravitational-Lensed Black Hole + Accretion Disc + Stars
    if end_blackhole_enabled {
        sky_col = it_black_hole_accretion_disc(sky_col, ray_dir, ldir, dither, end_doppler, true);
    } else {
        sky_col += it_calculate_stars(ray_dir);
    }

    // 2. IterationT Giant Ringed Planet + Ring Shadow + Chandrasekhar Atmosphere (PlanetEnd2)
    if end_planet_enabled {
        sky_col = it_planet_end2(sky_col, frame.camera_position, ray_dir, ldir, tf);
    }

    // 3. Atmospheric End Horizon Glow (EndFog at infinity)
    sky_col += it_end_fog(512.0, ray_dir, tf);

    return max(sky_col, vec3<f32>(0.0));
}

// Screen-space Ground Truth Ambient Occlusion (ported from Photon gtao.glsl)
fn compute_photon_gtao(uv: vec2<f32>, pixel: vec2<f32>, center_vpos: vec3<f32>, center_dist: f32) -> f32 {
    if gtao_strength <= 0.01 || center_dist > 160.0 {
        return 1.0;
    }
    let surf = surface_at(vec2<i32>(pixel));
    if !surf.present {
        return 1.0;
    }
    let n = surf.normal;

    let texel = 1.0 / max(frame.resolution, vec2<f32>(1.0));
    let radius_px = clamp(18.0 / max(center_dist * 0.18, 1.0), 2.0, 14.0);
    let jitter = interleaved_gradient_noise(pixel);

    var occlusion = 0.0;
    let dirs = 4;
    for (var i = 0; i < dirs; i++) {
        let angle = (f32(i) + jitter) * (PI * 0.5);
        let dir = vec2<f32>(cos(angle), sin(angle)) * texel * radius_px;

        let uv1 = clamp(uv + dir, vec2<f32>(0.001), vec2<f32>(0.999));
        let uv2 = clamp(uv - dir * 0.65, vec2<f32>(0.001), vec2<f32>(0.999));

        let d1 = depth_at(uv1);
        let d2 = depth_at(uv2);

        if d1 > 0.0001 {
            let vp1 = view_position(uv1, d1) - center_vpos;
            let len1 = length(vp1);
            if len1 > 0.02 && len1 < 3.5 {
                let h1 = max(0.0, dot(n, vp1 / len1) - 0.12);
                occlusion += h1 * (1.0 - len1 / 3.5);
            }
        }
        if d2 > 0.0001 {
            let vp2 = view_position(uv2, d2) - center_vpos;
            let len2 = length(vp2);
            if len2 > 0.02 && len2 < 3.5 {
                let h2 = max(0.0, dot(n, vp2 / len2) - 0.12);
                occlusion += h2 * (1.0 - len2 / 3.5);
            }
        }
    }

    let ao = clamp(1.0 - (occlusion / f32(dirs * 2)) * 1.45 * gtao_strength, 0.25, 1.0);
    let dist_fade = 1.0 - smoothstep(90.0, 160.0, center_dist);
    return mix(1.0, ao, dist_fade);
}

// Screen-space Crepuscular God Rays (Overworld Sun/Moon or End Black Hole)
fn compute_god_rays(uv: vec2<f32>, pixel: vec2<f32>, light_world_dir: vec3<f32>, ray_dir: vec3<f32>, light_col: vec3<f32>) -> vec3<f32> {
    if god_rays <= 0.01 {
        return vec3<f32>(0.0);
    }
    let cos_theta = dot(ray_dir, light_world_dir);
    if cos_theta <= 0.05 {
        return vec3<f32>(0.0);
    }

    let clip = frame.projection * (frame.view * vec4<f32>(light_world_dir * 1000.0, 1.0));
    if clip.w <= 0.0 {
        return vec3<f32>(0.0);
    }
    let ndc = clip.xy / clip.w;
    let light_uv = vec2<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);

    let delta = (light_uv - uv) * (1.0 / 8.0);
    let jitter = interleaved_gradient_noise(pixel);
    var sample_uv = uv + delta * jitter;
    var shaft = 0.0;

    for (var i = 0; i < 8; i++) {
        let clamped_uv = clamp(sample_uv, vec2<f32>(0.002), vec2<f32>(0.998));
        let d = depth_at(clamped_uv);
        if d <= 0.00002 {
            shaft += 1.0;
        }
        sample_uv += delta;
    }

    let phase = pow(max(0.0, cos_theta), 4.0) * 0.75 + henyey_greenstein(cos_theta, 0.65) * 0.15;
    return light_col * (shaft / 8.0) * phase * 0.24 * god_rays * fog_density;
}

// Underwater Caustics pattern
fn underwater_caustic_pattern(world_pos: vec3<f32>) -> f32 {
    let t = frame.time * 1.2;
    let p1 = world_pos.xz * 0.55 + vec2<f32>(t * 0.4, -t * 0.3);
    let p2 = world_pos.xz * 0.58 + vec2<f32>(-t * 0.35, t * 0.45);
    let c1 = abs(noise2(p1) * 2.0 - 1.0);
    let c2 = abs(noise2(p2) * 2.0 - 1.0);
    return pow(1.0 - min(c1, c2), 4.0);
}

fn post(input: PostInput) -> vec4<f32> {
    var col = input.color.rgb;
    let depth = input.depth;
    let is_sky = depth <= 0.00001;

    let sample_depth = select(depth, 0.0001, is_sky);
    let vpos = view_position(input.uv, sample_depth);
    let dist = length(vpos);
    let ray_dir = vpos / max(dist, 1e-4);
    let world_pos = frame.camera_position + vpos;

    // ========================================================================
    // THE END (frame.dimension == 1) — IterationT End Sky & Volumetric End Fog
    // ========================================================================
    if frame.dimension == 1 {
        let tf = end_time_factor(end_planet_cycle, end_planet_angle);
        let end_sky = render_iteration_end_sky(ray_dir, tf, input.pixel);

        if is_sky {
            return vec4<f32>(end_sky, 1.0);
        }

        // Terrain pixel in The End: apply GTAO, IterationT EndFog, and render-distance horizon blend
        let ao = compute_photon_gtao(input.uv, input.pixel, vpos, dist);
        col *= ao;

        let vol_fog = it_end_fog(dist, ray_dir, tf) * fog_density;
        let fog_trans = exp(-dist * 0.0022 * fog_density);
        col = col * fog_trans + vol_fog;

        let bh_dir = end_light_dir();
        col += compute_god_rays(input.uv, input.pixel, bh_dir, ray_dir, vec3<f32>(0.95, 0.62, 0.38));

        let border_fade = smoothstep(frame.render_distance * 0.78, frame.render_distance * 0.98, dist);
        col = mix(col, end_sky, border_fade);

        return vec4<f32>(max(col, vec3<f32>(0.0)), 1.0);
    }

    // ========================================================================
    // OVERWORLD (0) & NETHER (-1) — GTAO, Caustics, God Rays & Atmospheric Fog
    // ========================================================================
    let sdir = normalize(frame.sun_direction);
    let scol = sun_color();

    if !is_sky {
        let ao = compute_photon_gtao(input.uv, input.pixel, vpos, dist);
        col *= ao;

        if underwater_caustics && frame.eye_in == 1u {
            let caustic = underwater_caustic_pattern(world_pos);
            col += col * caustic * vec3<f32>(0.25, 0.75, 0.95) * exp(-dist * 0.06) * 0.85;
            let uw_fog = vec3<f32>(0.03, 0.16, 0.24) * max(luminance(ambient_color()), 0.08);
            col = mix(uw_fog, col, exp(-dist * 0.055));
        } else if frame.dimension == 0 {
            let height_density = exp(-max(world_pos.y - 60.0, 0.0) * 0.022);
            let rain_boost = 1.0 + frame.rain * 2.4;
            let opt_depth = dist * 0.0018 * fog_density * height_density * rain_boost;
            let fog_factor = 1.0 - exp(-opt_depth);

            let sky_fog_col = photon_sky_atmosphere(vec3<f32>(ray_dir.x, max(ray_dir.y, 0.01), ray_dir.z));
            col = mix(col, sky_fog_col, clamp(fog_factor, 0.0, 0.88));

            let border_fade = smoothstep(frame.render_distance * 0.82, frame.render_distance * 0.99, dist);
            col = mix(col, sky_fog_col, border_fade);
        } else {
            let nether_fog = 1.0 - exp(-dist * 0.0085 * fog_density);
            col = mix(col, frame.fog_color, clamp(nether_fog, 0.0, 0.95));
        }
    }

    if frame.dimension == 0 && frame.eye_in == 0u && sdir.y > -0.05 {
        col += compute_god_rays(input.uv, input.pixel, sdir, ray_dir, scol) * (1.0 - frame.rain * 0.85);
    }

    return vec4<f32>(max(col, vec3<f32>(0.0)), 1.0);
}
