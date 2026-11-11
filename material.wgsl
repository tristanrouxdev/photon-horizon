// ============================================================================
// Photon Horizon — Material Stage (BSDF, LabPBR, Shadows, Colored Lights, Water)
// Ported from Photon Shaders (bsdf.glsl, diffuse_lighting.glsl, water_normal.glsl)
// + IterationT End Sky Reflections on End Water & Specular Surfaces
// ============================================================================

override shadows: bool = true;
override soft_shadows: bool = true;
override cloud_shadows: bool = true;
override colored_lights: bool = true;
override rain_puddles: bool = true;
override water_reflections: bool = true;
override water_waves: bool = true;
override water_clarity: f32 = 1.0;

override end_planet_enabled: bool = true;
override end_blackhole_enabled: bool = true;
override end_planet_cycle: f32 = 1.0;
override end_planet_angle: f32 = 28.0;
override end_doppler: bool = true;

// Photon Hammon 2017 diffuse BRDF
fn hammon_diffuse(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, roughness: f32, albedo: vec3<f32>) -> vec3<f32> {
    let ndl = max(dot(n, l), 0.0);
    if ndl <= 0.0 {
        return vec3<f32>(0.0);
    }
    let ndv = max(abs(dot(n, v)), 1e-4);
    let h = normalize(v + l);
    let ndh = max(dot(n, h), 0.0);
    let lv = dot(l, v);

    let facing = 0.5 + 0.5 * lv;
    let rough = facing * (0.9 - 0.4 * facing) * ((0.5 + ndh) / max(ndh, 0.1));
    let smooth_term = 1.05 * (1.0 - pow5(1.0 - ndl)) * (1.0 - pow5(1.0 - ndv));
    let single = mix(smooth_term, rough, roughness) * RCP_PI;
    let multi = 0.1159 * roughness;

    return ndl * (vec3<f32>(single) + albedo * multi);
}

// Smith-GGX Specular BRDF (Photon bsdf.glsl)
fn ggx_specular(n: vec3<f32>, v: vec3<f32>, l: vec3<f32>, roughness: f32, f0: vec3<f32>) -> vec3<f32> {
    let ndl = max(dot(n, l), 0.0);
    let ndv = max(dot(n, v), 1e-4);
    if ndl <= 0.0 {
        return vec3<f32>(0.0);
    }
    let h = normalize(v + l);
    let ndh = max(dot(n, h), 0.0);
    let vdh = max(dot(v, h), 0.0);

    let alpha = max(roughness * roughness, 0.002);
    let alpha2 = alpha * alpha;
    let denom = ndh * ndh * (alpha2 - 1.0) + 1.0;
    let d_ggx = alpha2 / max(PI * denom * denom, 1e-6);

    let k = alpha * 0.5;
    let g_v = ndv / (ndv * (1.0 - k) + k);
    let g_l = ndl / (ndl * (1.0 - k) + k);
    let f = f0 + (1.0 - f0) * pow5(1.0 - vdh);

    return (d_ggx * g_v * g_l * f) / max(4.0 * ndv, 1e-4);
}

fn sample_shadow_point(cam_rel_pos: vec3<f32>) -> f32 {
    let sp = shadow_position(cam_rel_pos);
    return textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z);
}

// 5-tap rotated Poisson soft shadow + translucent stained-glass shadow color
fn sample_photon_shadow(cam_rel_pos: vec3<f32>, n: vec3<f32>, sss_amount: f32) -> vec3<f32> {
    if !shadows || frame.has_shadow == 0u {
        return vec3<f32>(1.0);
    }
    let base_bias = max(frame.shadow_center_texel * 1.5, 0.03) * mix(1.0, 2.2, sss_amount);
    let biased_pos = cam_rel_pos + n * base_bias;
    let sp0 = shadow_position(biased_pos);
    let s0 = textureSampleCompareLevel(shadow_map, shadow_sampler, sp0.xy, sp0.z);

    var s_avg = s0;
    if soft_shadows {
        let spread = mix(0.05, 0.14, sss_amount);
        let s1 = sample_shadow_point(biased_pos + vec3<f32>( spread, 0.0,  spread));
        let s2 = sample_shadow_point(biased_pos + vec3<f32>(-spread, 0.0,  spread));
        let s3 = sample_shadow_point(biased_pos + vec3<f32>( spread, 0.0, -spread));
        let s4 = sample_shadow_point(biased_pos + vec3<f32>(-spread, 0.0, -spread));
        s_avg = (s0 * 2.0 + s1 + s2 + s3 + s4) / 6.0;
    }

    if s_avg > 0.01 {
        let st = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, sp0.xy, sp0.z);
        if st < s0 - 0.01 {
            let sc_dims = vec2<f32>(textureDimensions(shadow_color));
            let sc_texel = vec2<i32>(clamp(sp0.xy * sc_dims, vec2<f32>(0.0), sc_dims - 1.0));
            let sc = textureLoad(shadow_color, sc_texel, 0);
            let tint = mix(vec3<f32>(1.0), sc.rgb, clamp(sc.a, 0.0, 0.92));
            return tint * s_avg;
        }
    }
    return vec3<f32>(s_avg);
}

// Cloud shadow projection on Overworld terrain
fn sample_cloud_shadow(world_pos: vec3<f32>, sun_dir: vec3<f32>) -> f32 {
    if !cloud_shadows || frame.dimension != 0 || sun_dir.y <= 0.03 {
        return 1.0;
    }
    let wind = vec2<f32>(frame.time * 0.012, frame.time * 0.005);
    let cloud_plane_uv = (world_pos.xz + sun_dir.xz * ((160.0 - world_pos.y) / max(sun_dir.y, 0.12))) * 0.0042 + wind;
    let n = fbm2(cloud_plane_uv * 1.15);
    let shadow = smoothstep(0.46, 0.72, n);
    return 1.0 - shadow * 0.58 * (1.0 - frame.rain * 0.65);
}

// Photon multi-octave gerstner/noise water wave normal (ported from Photon water_normal.glsl)
fn photon_water_normal(world_pos: vec3<f32>, base_n: vec3<f32>) -> vec3<f32> {
    if !water_waves || abs(base_n.y) < 0.5 {
        return base_n;
    }
    let t = frame.time * 1.35;
    let p = world_pos.xz * 0.82;

    let dir1 = vec2<f32>(0.86, 0.50);
    let dir2 = vec2<f32>(-0.52, 0.85);
    let dir3 = vec2<f32>(0.31, -0.95);

    let uv1 = p * 1.15 + dir1 * t * 0.75;
    let uv2 = p * 2.45 + dir2 * t * 1.05;
    let uv3 = p * 5.20 + dir3 * t * 1.45;

    let eps = 0.08;
    let h0 = noise2(uv1) * 0.55 + noise2(uv2) * 0.30 + noise2(uv3) * 0.15;
    let hx = noise2(uv1 + vec2<f32>(eps, 0.0)) * 0.55 + noise2(uv2 + vec2<f32>(eps * 2.0, 0.0)) * 0.30 + noise2(uv3 + vec2<f32>(eps * 4.0, 0.0)) * 0.15;
    let hz = noise2(uv1 + vec2<f32>(0.0, eps)) * 0.55 + noise2(uv2 + vec2<f32>(0.0, eps * 2.0)) * 0.30 + noise2(uv3 + vec2<f32>(0.0, eps * 4.0)) * 0.15;

    let slope = vec2<f32>(h0 - hx, h0 - hz) * 1.85;
    return normalize(vec3<f32>(slope.x, 1.0, slope.y));
}

// Camera-relative world position from screen UV and reversed depth
fn reconstruct_cam_pos(uv: vec2<f32>, depth: f32) -> vec3<f32> {
    let clip = vec4<f32>(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, depth, 1.0);
    let view = frame.projection_inverse * clip;
    return (frame.view_inverse * vec4<f32>(view.xyz / view.w, 0.0)).xyz;
}

// Evaluate reflected sky environment (including IterationT Planet + Black Hole in The End!)
fn sample_environment_reflection(refl_dir: vec3<f32>, screen_uv: vec2<f32>, wave_offset: vec2<f32>, sky_vis: f32) -> vec3<f32> {
    if frame.dimension == 1 {
        let tf = end_time_factor(end_planet_cycle, end_planet_angle);
        let ldir = end_light_dir();
        var end_refl = vec3<f32>(0.015, 0.010, 0.028) + it_calculate_stars(refl_dir) * 0.65;
        if end_planet_enabled {
            end_refl = it_planet_end2(end_refl, frame.camera_position, refl_dir, ldir, tf);
        }
        if end_blackhole_enabled {
            end_refl = it_black_hole_accretion_disc(end_refl, refl_dir, ldir, 0.5, end_doppler, false);
        }
        return end_refl;
    }

    if frame.dimension == -1 {
        return frame.fog_color * 0.45;
    }

    let sdir = normalize(frame.sun_direction);
    let scol = sun_color();
    var env = photon_sky_atmosphere(vec3<f32>(refl_dir.x, max(refl_dir.y, 0.02), refl_dir.z)) * sky_vis;

    if water_reflections && frame.has_reflection != 0u && sky_vis > 0.05 {
        let refl_uv = clamp(screen_uv + wave_offset, vec2<f32>(0.002), vec2<f32>(0.998));
        let planar = textureSampleLevel(reflection, reflection_sampler, refl_uv, 0.0);
        if planar.a > 0.01 {
            env = mix(env, planar.rgb, planar.a * sky_vis * 0.92);
        }
    }

    let glint = pow(max(dot(refl_dir, sdir), 0.0), 256.0) * 18.0 + pow(max(dot(refl_dir, sdir), 0.0), 32.0) * 0.65;
    env += scol * glint * sky_vis * (1.0 - frame.rain * 0.85);
    return env;
}

fn material(input: MaterialInput) -> Surface {
    // Preserve full texture contrast & biome tint; lift dark Nether albedos slightly so Nether Bricks & Basalt stay crisp
    let raw_albedo = max(input.albedo.rgb * input.tint.rgb, vec3<f32>(0.001));
    let albedo = select(raw_albedo, mix(raw_albedo, pow(raw_albedo, vec3<f32>(0.68)), 0.42), frame.dimension == -1);
    let cam_pos = input.position;
    let world_pos = cam_pos + frame.camera_position;
    let dist = length(cam_pos);
    let v = -cam_pos / max(dist, 1e-4);

    let block_lm = clamp(input.light.x, 0.0, 1.0);
    let sky_lm = clamp(input.light.y, 0.0, 1.0);
    let sky_vis = smoothstep(0.05, 0.92, sky_lm);
    let ao = 1.0;

    // ------------------------------------------------------------------------
    // WATER SHADING (Photon Beer-Lambert Absorption + Refraction + Reflections)
    // ------------------------------------------------------------------------
    if input.fluid == 1u {
        let wn = photon_water_normal(world_pos, input.normal);
        let ndv = max(dot(wn, v), 0.02);
        let fresnel = clamp(0.02 + 0.98 * pow5(1.0 - ndv), 0.04, 0.96);

        let wave_offset = wn.xz * 0.032 / max(1.0, dist * 0.12);
        let refr_uv = clamp(input.screen + wave_offset * 0.45, vec2<f32>(0.002), vec2<f32>(0.998));

        let depth_dims = vec2<f32>(textureDimensions(opaque_depth));
        let depth_texel = vec2<i32>(clamp(refr_uv * depth_dims, vec2<f32>(0.0), depth_dims - 1.0));
        let bg_depth = textureLoad(opaque_depth, depth_texel, 0);
        let bg_cam_pos = reconstruct_cam_pos(refr_uv, max(bg_depth, 0.0001));
        let water_depth = select(24.0, max(0.0, length(bg_cam_pos) - dist), bg_depth > 0.00001);

        let col_dims = vec2<f32>(textureDimensions(opaque_color));
        let col_texel = vec2<i32>(clamp(refr_uv * col_dims, vec2<f32>(0.0), col_dims - 1.0));
        let bg_col = textureLoad(opaque_color, col_texel, 0).rgb;

        let absorb_coeff = vec3<f32>(0.36, 0.11, 0.045) / max(water_clarity, 0.25);
        let transmittance = exp(-absorb_coeff * min(water_depth, 32.0));

        let sdir = normalize(frame.sun_direction);
        let shadow_val = select(1.0, sample_shadow_point(cam_pos + vec3<f32>(0.0, 0.08, 0.0)), shadows && frame.has_shadow != 0u && frame.dimension == 0);
        let scatter_light = (sun_color() * max(sdir.y, 0.0) * shadow_val * 0.55 + ambient_color() * 0.85) * max(sky_vis, 0.15);
        let deep_water_col = albedo * scatter_light * vec3<f32>(0.16, 0.48, 0.62);

        let refracted = mix(deep_water_col, bg_col * transmittance + deep_water_col * (1.0 - transmittance), clamp(exp(-water_depth * 0.08), 0.15, 1.0));
        let refl_dir = reflect(-v, wn);
        let reflected = sample_environment_reflection(refl_dir, input.screen, wave_offset, max(sky_vis, f32(frame.dimension == 1)));

        let water_col = mix(refracted, reflected, fresnel);
        set_surface(wn, 0.95, shadow_val);
        return Surface(vec4<f32>(water_col, 0.92));
    }

    // ------------------------------------------------------------------------
    // SOLID & TRANSLUCENT BLOCKS (LabPBR + Rain Puddles + Photon BSDF)
    // ------------------------------------------------------------------------
    var n = normalize(input.normal);
    var roughness = 0.82;
    var f0 = vec3<f32>(0.04);
    var sss = 0.0;
    var emissive = input.emission;

    let is_foliage = input.material == MAT_LEAVES || input.material == MAT_PLANT || input.material == MAT_TALL_LOWER || input.material == MAT_TALL_UPPER || input.material == MAT_VINE;
    if is_foliage {
        sss = 0.68;
        roughness = 0.65;
    }

    // LabPBR normal & specular maps when present
    if block_pbr_maps() {
        let nm = block_normal_map(input.uv);
        let n_xy = nm.rg * 2.0 - 1.0;
        let n_z = sqrt(max(0.0, 1.0 - dot(n_xy, n_xy)));
        let t = input.tangent.xyz;
        let b = cross(n, t) * input.tangent.w;
        n = normalize(t * n_xy.x + b * n_xy.y + n * n_z);

        let spec = block_specular_map(input.uv);
        let smoothness = spec.r;
        roughness = clamp(sqr(1.0 - smoothness), 0.03, 0.98);
        if spec.g * 255.0 >= 229.5 {
            f0 = albedo;
        } else {
            f0 = vec3<f32>(max(0.02, spec.g));
        }
        if spec.b * 255.0 >= 65.0 {
            sss = max(sss, (spec.b * 255.0 - 65.0) / 190.0);
        }
        if spec.a < 0.996 {
            emissive = max(emissive, spec.a);
        }
    } else if dist < 48.0 {
        // Auto-generated texel micro-relief when using vanilla textures without LabPBR
        let t = input.tangent.xyz;
        let b = cross(n, t) * input.tangent.w;
        let luma_here = luminance(input.albedo.rgb);
        let d_u = dpdx(luma_here);
        let d_v = dpdy(luma_here);
        let bump_fade = (1.0 - smoothstep(16.0, 48.0, dist)) * 0.35;
        n = normalize(n - (t * d_u + b * d_v) * bump_fade);
    }

    // Photon Rain Puddles on upward-facing outdoor surfaces
    var puddle_factor = 0.0;
    if rain_puddles && frame.dimension == 0 && frame.wetness > 0.01 && n.y > 0.75 && !is_foliage && input.fluid == 0u {
        let puddle_noise = smoothstep(0.42, 0.68, fbm2(world_pos.xz * 0.28));
        puddle_factor = puddle_noise * frame.wetness * smoothstep(0.65, 0.92, sky_lm) * smoothstep(0.75, 0.96, n.y);
        roughness = mix(roughness, 0.03, puddle_factor);
        f0 = mix(f0, vec3<f32>(0.025), puddle_factor);
        n = normalize(mix(n, vec3<f32>(0.0, 1.0, 0.0), puddle_factor * 0.85));
    }

    let wet_albedo = albedo * (1.0 - puddle_factor * 0.32);

    // Directional Sun/Moon/End-Planet/Nether Light
    var l_dir = normalize(frame.light_direction);
    if frame.dimension == 1 {
        l_dir = end_light_dir();
    } else if frame.dimension == -1 {
        l_dir = normalize(vec3<f32>(0.34, 0.84, 0.42));
    }

    let direct_col = photon_direct_light();
    let amb_col = ambient_color();

    // Shadows (Shadow map + Cloud shadows)
    var shadow_rgb = vec3<f32>(1.0);
    if frame.dimension == 0 {
        shadow_rgb = sample_photon_shadow(cam_pos, input.normal, sss) * sample_cloud_shadow(world_pos, l_dir);
    }

    // Diffuse + Specular + Subsurface Scattering
    let diff = hammon_diffuse(n, v, l_dir, roughness, wet_albedo);
    let spec_brdf = ggx_specular(n, v, l_dir, roughness, f0);

    let back_scatter = pow(clamp(dot(v, -l_dir), 0.0, 1.0), 3.0) * 0.65 + max(0.0, dot(-n, l_dir)) * 0.35;
    let sss_term = wet_albedo * sss * (0.35 + back_scatter) * RCP_PI;

    let dim_sky_vis = select(sky_vis, 0.90, frame.dimension != 0);
    let direct_lighting = (wet_albedo * diff + sss_term + spec_brdf) * direct_col * shadow_rgb * dim_sky_vis;

    // Hemispherical sky ambient lighting
    let hemi = 0.68 + 0.32 * n.y;
    let sky_ambient = wet_albedo * amb_col * hemi * ao * select(max(sky_vis, 0.08), 0.92, frame.dimension != 0);

    // Blocklight + Colored Point Lights + Handheld Dynamic Light
    let bl_falloff = get_blocklight_falloff(block_lm);
    var block_light = photon_blocklight_color() * bl_falloff;

    if colored_lights {
        let flood = block_light_color(cam_pos + input.normal * 0.35);
        if flood.a > 0.001 {
            block_light = mix(block_light, flood.rgb * bl_falloff * 1.35, clamp(flood.a, 0.0, 0.90));
        }
        block_light += input.colored_light * 1.45;
    }

    // Emissive boost for lava, torches, end rods, sea lanterns, glowstone
    let emissive_light = wet_albedo * emissive * 2.8;

    // Specular environment reflection on smooth LabPBR blocks & rain puddles
    var env_spec = vec3<f32>(0.0);
    if roughness < 0.35 || puddle_factor > 0.05 {
        let ndv = max(dot(n, v), 0.01);
        let f_env = f0 + (1.0 - f0) * pow5(1.0 - ndv);
        let refl_dir = reflect(-v, n);
        let env_col = sample_environment_reflection(refl_dir, input.screen, n.xz * 0.015, sky_vis);
        let smoothness_factor = sqr(1.0 - roughness);
        env_spec = env_col * f_env * smoothness_factor * max(puddle_factor, smoothness_factor * 0.65);
    }

    let total_color = direct_lighting + sky_ambient + wet_albedo * block_light * ao + emissive_light + env_spec;

    set_surface(n, 1.0 - roughness, emissive);

    return Surface(vec4<f32>(max(total_color, vec3<f32>(0.0)), input.albedo.a));
}
