// ============================================================================
// Photon Horizon — Overworld Sky, Sun, Aurora Borealis & Volumetric Clouds
// Ported from Photon Shaders by SixthSurge (sky.glsl, clouds.glsl, aurora.glsl)
// ============================================================================

override volumetric_clouds: bool = true;
override cloud_coverage: f32 = 1.0;
override aurora_enabled: bool = true;
override galaxy_enabled: bool = true;

// Limb-darkened solar disc with corona glow (Photon sky.glsl)
fn draw_photon_sun(d: vec3<f32>, sun_dir: vec3<f32>, sun_col: vec3<f32>) -> vec3<f32> {
    let nu = dot(d, sun_dir);
    let r = sqrt(max(0.0, 2.0 - 2.0 * nu));
    let sun_radius = 0.042;
    let mu_limb = sqrt(max(0.0, 1.0 - sqr(r / max(sun_radius, 0.001))));
    let darkening = 1.0 - 0.58 * (1.0 - mu_limb);
    let disc = (1.0 - smoothstep(sun_radius * 0.86, sun_radius, r)) * darkening * 36.0;
    let corona = exp(-r * 24.0) * 1.45 + exp(-r * 5.5) * 0.16 + pow(max(0.0, nu), 192.0) * 1.8;
    return sun_col * (disc + corona) * clamp(sun_dir.y * 8.0 + 0.35, 0.0, 1.0);
}

// Atmospheric lunar corona halo around the moon (Horizon draws the vanilla moon sprite on top)
fn draw_photon_moon_halo(d: vec3<f32>, moon_dir: vec3<f32>) -> vec3<f32> {
    let nu = dot(d, moon_dir);
    let r = sqrt(max(0.0, 2.0 - 2.0 * nu));
    let glow = exp(-r * 26.0) * 0.36 + exp(-r * 6.5) * 0.065;
    return moon_color() * glow * clamp(moon_dir.y * 6.0 + 0.25, 0.0, 1.0);
}

// Milky Way galaxy band at night (Photon sky.glsl)
fn draw_photon_galaxy(d: vec3<f32>, night: f32) -> vec3<f32> {
    if !galaxy_enabled || night <= 0.005 || d.y <= 0.0 {
        return vec3<f32>(0.0);
    }
    let rot_d = vec3<f32>(
        d.x * 0.82 - d.y * 0.57,
        d.x * 0.57 + d.y * 0.82,
        d.z
    );
    let band = exp(-abs(rot_d.x) * 4.8);
    let dust_uv = rot_d.yz * 3.4 + vec2<f32>(0.7, 1.9);
    let clouds = fbm2(dust_uv);
    let dark_lane = smoothstep(0.35, 0.62, fbm2(dust_uv * 2.1 + vec2<f32>(4.2, -1.5)));
    let horizon_fade = smoothstep(0.02, 0.30, d.y);
    let core_col = mix(vec3<f32>(0.16, 0.24, 0.48), vec3<f32>(0.55, 0.42, 0.72), clouds);
    return core_col * band * clouds * (1.0 - 0.58 * dark_lane) * horizon_fade * night * 0.22;
}

// Photon Northern Aurora Borealis (ported from Photon world0/aurora.glsl)
fn aurora_colour_stops(h: f32) -> vec3<f32> {
    let green = vec3<f32>(0.08, 0.95, 0.42);
    let cyan  = vec3<f32>(0.06, 0.62, 0.88);
    let violet = vec3<f32>(0.58, 0.18, 0.86);
    let c0 = mix(green, cyan, smoothstep(0.0, 0.48, h));
    return mix(c0, violet, smoothstep(0.42, 0.95, h));
}

fn draw_photon_aurora(d: vec3<f32>, night: f32) -> vec3<f32> {
    if !aurora_enabled || night <= 0.01 || d.y <= 0.03 {
        return vec3<f32>(0.0);
    }
    let t = frame.time * 0.035;
    let inv_y = 1.0 / max(d.y, 0.06);
    var acc = vec3<f32>(0.0);
    let steps = 8;
    for (var i = 0; i < steps; i++) {
        let fi = (f32(i) + 0.5) / f32(steps);
        let alt = mix(1.0, 2.2, fi);
        let p = d.xz * inv_y * alt * 0.55;
        let warp = vec2<f32>(
            noise2(p * 1.4 + vec2<f32>(t * 0.6, -t * 0.4)),
            noise2(p * 1.4 + vec2<f32>(-t * 0.5, t * 0.7))
        ) * 0.45;
        let uv = p + warp;
        let curtain_wave = sin(uv.x * 3.8 + sin(uv.y * 2.4 + t * 1.3) * 1.8 + t * 0.8);
        let ribbon = exp(-abs(curtain_wave) * 5.2) * smoothstep(0.25, 0.78, fbm2(uv * 2.1 + vec2<f32>(0.0, t)));
        let weight = sin(fi * PI) * exp(-fi * 1.1);
        acc += aurora_colour_stops(fi) * ribbon * weight;
    }
    let horizon_fade = smoothstep(0.03, 0.24, d.y) * exp(-length(d.xz / max(d.y, 0.08)) * 0.16);
    return acc * (2.2 / f32(steps)) * horizon_fade * night * (1.0 - frame.rain * 0.85);
}

// Photon Volumetric Cumulus + Cirrus Clouds (ported from Photon include/sky/clouds.glsl)
fn sample_photon_clouds(d: vec3<f32>, sky_bg: vec3<f32>, sun_dir: vec3<f32>, sun_col: vec3<f32>, amb_col: vec3<f32>) -> vec3<f32> {
    if !volumetric_clouds || d.y <= 0.015 {
        return sky_bg;
    }

    let wind = vec2<f32>(frame.time * 0.012, frame.time * 0.005);
    let inv_y = 1.0 / (d.y + 0.08);
    let nu = dot(d, sun_dir);
    let phase = mix(henyey_greenstein(nu, 0.58), henyey_greenstein(nu, -0.25), 0.30) + pow(max(0.0, nu), 18.0) * 0.35;

    // 1. High-altitude planar cirrus layer
    let cirrus_uv = d.xz * (1.8 / (d.y + 0.14)) + wind * 0.45;
    let cirrus_warp = vec2<f32>(
        fbm2(cirrus_uv * 1.6),
        fbm2(cirrus_uv * 1.6 + vec2<f32>(5.2, 1.3))
    );
    let cirrus_density = smoothstep(0.54 - 0.12 * cloud_coverage, 0.88, fbm2(cirrus_uv * 2.4 + cirrus_warp * 0.65))
        * smoothstep(0.02, 0.18, d.y) * 0.38;
    let cirrus_light = sun_col * (0.65 + 1.15 * phase) + amb_col * 0.75;
    var result = mix(sky_bg, cirrus_light, cirrus_density * exp(-1.2 / max(d.y, 0.05) * 0.08));

    // 2. Raymarched 3D Cumulus layer (8 steps with multi-scattering powder approximation)
    let cov = clamp(0.48 * cloud_coverage + frame.rain * 0.34, 0.15, 0.92);
    var transmittance = 1.0;
    var scattered_light = vec3<f32>(0.0);
    let light_step = sun_dir.xz * 0.14;

    let steps = 8;
    for (var i = 0; i < steps; i++) {
        let h = (f32(i) + 0.5) / f32(steps);
        let alt_scale = mix(0.85, 1.35, h);
        let p = d.xz * inv_y * alt_scale + wind;

        let height_profile = smoothstep(0.0, 0.22, h) * (1.0 - smoothstep(0.55, 1.0, h));
        let base_n = fbm2(p * 1.15) * 0.68 + noise2(p * 3.6 - wind * 1.5) * 0.32;
        let density = max(0.0, base_n * height_profile - (1.0 - cov) * 0.68) * 2.6;

        if density > 0.004 {
            let p_sun = p + light_step * (1.0 - h * 0.5);
            let sun_n = max(0.0, fbm2(p_sun * 1.15) * height_profile - (1.0 - cov) * 0.68) * 2.4;
            let optical_depth = sun_n * 1.45 + (1.0 - h) * 0.35;

            let beer = exp(-optical_depth * 1.35) * 0.7 + exp(-optical_depth * 0.35) * 0.3;
            let powder = 1.0 - exp(-density * 2.8) * 0.45;
            let direct = sun_col * beer * powder * (0.55 + 1.45 * phase);
            let ambient = amb_col * mix(0.38, 1.05, h);
            let step_col = direct + ambient;

            let step_trans = exp(-density * 0.42);
            scattered_light += transmittance * (1.0 - step_trans) * step_col;
            transmittance *= step_trans;
            if transmittance < 0.02 {
                break;
            }
        }
    }

    let aerial_fade = smoothstep(0.015, 0.22, d.y);
    let cloud_alpha = (1.0 - transmittance) * aerial_fade;
    result = result * (1.0 - cloud_alpha) + scattered_light * aerial_fade + sky_bg * (1.0 - aerial_fade) * (1.0 - transmittance);
    return result;
}

fn sky(input: SkyInput) -> vec4<f32> {
    if frame.dimension != 0 {
        return input.color;
    }

    let d = normalize(input.direction);
    let sdir = normalize(frame.sun_direction);
    let mdir = normalize(frame.moon_direction);
    let scol = sun_color();
    let acol = ambient_color();
    let night = night_factor();

    // Base physical Rayleigh + Mie atmosphere
    var col = photon_sky_atmosphere(d);

    // Night stars + Milky Way + Northern Aurora + Sun + Moon halo
    if d.y > -0.04 {
        let horizon_vis = smoothstep(-0.04, 0.08, d.y);
        let clear_sky = 1.0 - frame.rain * 0.92;
        if night > 0.01 {
            if galaxy_enabled {
                let stars = it_calculate_stars(d) * night * clear_sky * horizon_vis * 0.85;
                let galaxy = draw_photon_galaxy(d, night) * clear_sky;
                col += stars + galaxy;
            }
            col += draw_photon_aurora(d, night);
        }
        col += draw_photon_sun(d, sdir, scol) * clear_sky * horizon_vis;
        col += draw_photon_moon_halo(d, mdir) * clear_sky * horizon_vis;
    }

    // Volumetric clouds
    col = sample_photon_clouds(d, col, sdir, scol, acol);

    return vec4<f32>(max(col, vec3<f32>(0.0)), 1.0);
}
