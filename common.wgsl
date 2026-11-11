// ============================================================================
// Photon Shaders (SixthSurge) + IterationT End Sky (Tahnass) — Horizon WGSL Port
// Shared prelude module (common.wgsl)
// ============================================================================

const PI: f32 = 3.14159265359;
const HALF_PI: f32 = 1.57079632679;
const TAU: f32 = 6.28318530718;
const RCP_PI: f32 = 0.31830988618;

const MAT_LEAVES: u32 = 1u;
const MAT_PLANT: u32 = 2u;
const MAT_TALL_LOWER: u32 = 3u;
const MAT_TALL_UPPER: u32 = 4u;
const MAT_VINE: u32 = 5u;

// Photon AM0 solar irradiance in space
const PHOTON_SUNLIGHT_COLOR: vec3<f32> = vec3<f32>(1.051, 0.985, 0.940);
const PHOTON_PLANET_RADIUS: f32 = 6371e3;
const PHOTON_ATMO_OUTER: f32 = 6481e3;

fn saturate_f(x: f32) -> f32 {
    return clamp(x, 0.0, 1.0);
}

fn saturate_v3(x: vec3<f32>) -> vec3<f32> {
    return clamp(x, vec3<f32>(0.0), vec3<f32>(1.0));
}

fn sqr(x: f32) -> f32 {
    return x * x;
}

fn cube_f(x: f32) -> f32 {
    return x * x * x;
}

fn pow5(x: f32) -> f32 {
    let x2 = x * x;
    return x2 * x2 * x;
}

fn curve_f(x: f32) -> f32 {
    return x * x * (3.0 - 2.0 * x);
}

fn curve_v3(x: vec3<f32>) -> vec3<f32> {
    return x * x * (vec3<f32>(3.0) - 2.0 * x);
}

fn remap_saturate(x: f32, e0: f32, e1: f32) -> f32 {
    return clamp((x - e0) / (e1 - e0), 0.0, 1.0);
}

fn pulse(x: f32, center: f32, width: f32) -> f32 {
    let d = abs(x - center) / max(width, 1e-4);
    return max(0.0, 1.0 - d * d * (3.0 - 2.0 * min(d, 1.0)));
}

fn fast_acos(x: f32) -> f32 {
    let ax = clamp(abs(x), 0.0, 1.0);
    let res = (-0.156583 * ax + HALF_PI) * sqrt(max(1.0 - ax, 0.0));
    return select(PI - res, res, x >= 0.0);
}

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn to_display(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

// Interleaved Gradient Noise (Jimenez 2014)
fn ign(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(pixel, vec2<f32>(0.06711056, 0.00583715))));
}

// Smooth 2D & 3D procedural value noise (replaces texture lookups to stay well under texture budgets)
fn hash21(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn value_noise2d(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec2<f32>(3.0) - 2.0 * f);
    let a = hash21(i);
    let b = hash21(i + vec2<f32>(1.0, 0.0));
    let c = hash21(i + vec2<f32>(0.0, 1.0));
    let d = hash21(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn hash31(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

fn value_noise3d(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (vec3<f32>(3.0) - 2.0 * f);
    let n000 = hash31(i);
    let n100 = hash31(i + vec3<f32>(1.0, 0.0, 0.0));
    let n010 = hash31(i + vec3<f32>(0.0, 1.0, 0.0));
    let n110 = hash31(i + vec3<f32>(1.0, 1.0, 0.0));
    let n001 = hash31(i + vec3<f32>(0.0, 0.0, 1.0));
    let n101 = hash31(i + vec3<f32>(1.0, 0.0, 1.0));
    let n011 = hash31(i + vec3<f32>(0.0, 1.0, 1.0));
    let n111 = hash31(i + vec3<f32>(1.0, 1.0, 1.0));
    let nx00 = mix(n000, n100, u.x);
    let nx10 = mix(n010, n110, u.x);
    let nx01 = mix(n001, n101, u.x);
    let nx11 = mix(n011, n111, u.x);
    let nxy0 = mix(nx00, nx10, u.y);
    let nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

fn noise2(p: vec2<f32>) -> f32 {
    return value_noise2d(p);
}

fn fbm2(p_in: vec2<f32>) -> f32 {
    var p = p_in;
    var v = 0.0;
    var a = 0.5;
    for (var i = 0; i < 4; i++) {
        v += a * value_noise2d(p);
        p = p * 2.03 + vec2<f32>(17.1, 31.7);
        a *= 0.5;
    }
    return v;
}

fn fbm3(p_in: vec3<f32>) -> f32 {
    var p = p_in;
    var v = 0.0;
    var a = 0.5;
    for (var i = 0; i < 3; i++) {
        v += a * value_noise3d(p);
        p = p * 2.02 + vec3<f32>(11.3, 23.7, 7.9);
        a *= 0.5;
    }
    return v;
}

fn interleaved_gradient_noise(pixel: vec2<f32>) -> f32 {
    return ign(pixel);
}

fn henyey_greenstein(nu: f32, g: f32) -> f32 {
    return henyey_greenstein_phase(nu, g);
}

fn sun_color() -> vec3<f32> {
    return photon_direct_light();
}

fn moon_color() -> vec3<f32> {
    return vec3<f32>(0.52, 0.68, 0.98) * 0.28;
}

fn ambient_color() -> vec3<f32> {
    return photon_ambient_light();
}

fn photon_blocklight_color() -> vec3<f32> {
    // Photon warm 2400K incandescent blocklight
    return vec3<f32>(1.0, 0.58, 0.24) * 1.45;
}

fn get_blocklight_falloff(block_lm: f32) -> f32 {
    let x = clamp(block_lm, 0.0, 1.0);
    return x * x * (0.65 + 0.35 * x * x);
}

// ============================================================================
// PHOTON ATMOSPHERE & TIME-OF-DAY LIGHTING (SixthSurge)
// ============================================================================

fn daylight() -> f32 {
    return smoothstep(-0.06, 0.14, frame.sun_direction.y);
}

fn twilight() -> f32 {
    return 1.0 - smoothstep(0.0, 0.34, abs(frame.sun_direction.y));
}

fn night_factor() -> f32 {
    return 1.0 - smoothstep(-0.12, 0.04, frame.sun_direction.y);
}

fn henyey_greenstein_phase(nu: f32, g: f32) -> f32 {
    let gg = g * g;
    return (1.0 - gg) / (4.0 * PI * pow(max(1.0 + gg - 2.0 * g * nu, 1e-4), 1.5));
}

// Photon's atmospheric transmittance along elevation `mu = dir.y`
fn photon_atmosphere_transmittance(mu: f32) -> vec3<f32> {
    let m = max(mu, -0.08);
    // Air mass approximation (Kasten-Young style)
    let zenith_cos = max(m + 0.12 * exp(-11.0 * max(m, 0.0)), 0.025);
    let air_mass = 1.0 / zenith_cos;
    // Rayleigh + Mie + Ozone optical depth in linear RGB
    let beta_ext = vec3<f32>(0.068, 0.148, 0.315);
    return exp(-beta_ext * min(air_mass, 18.0));
}

// Photon's `get_sun_tint` & `get_light_color` (lighting/colors/light_color.glsl)
fn photon_direct_light() -> vec3<f32> {
    if frame.dimension == -1 {
        return vec3<f32>(0.0);
    }
    if frame.dimension == 1 {
        // End direct light from IterationT's ringed planet & accretion disc
        return vec3<f32>(1.15, 0.86, 0.58) * 1.35;
    }

    let sun_y = frame.sun_direction.y;
    let blue_hour = smoothstep(0.05, 1.0, exp(-190.0 * sqr(sun_y + 0.09604)));
    let me_pulse = sqr(pulse(sun_y, 0.17, 0.40));
    let me_tint = mix(vec3<f32>(1.0), vec3<f32>(1.05, 0.84, 0.93) * 1.2, me_pulse);
    let bh_tint = mix(vec3<f32>(1.0), vec3<f32>(0.95, 0.80, 1.0), blue_hour);

    let l = frame.light_direction;
    let is_sun = dot(l, frame.sun_direction) > 0.0;
    let trans = photon_atmosphere_transmittance(l.y);
    let weather_dim = 1.0 - 0.82 * max(frame.rain, frame.thunder);
    let horizon_fade = clamp(l.y / 0.06, 0.0, 1.0);

    if is_sun {
        let sun_col = PHOTON_SUNLIGHT_COLOR * trans * me_tint * bh_tint * 2.4;
        return sun_col * horizon_fade * weather_dim;
    } else {
        let moon_col = vec3<f32>(0.52, 0.68, 0.98) * 0.24;
        return moon_col * horizon_fade * weather_dim;
    }
}

fn photon_ambient_light() -> vec3<f32> {
    if frame.dimension == -1 {
        return vec3<f32>(0.42, 0.18, 0.10);
    }
    if frame.dimension == 1 {
        // Cosmic violet-indigo ambient + warm golden bounce from IterationT's End planet
        return vec3<f32>(0.22, 0.18, 0.34);
    }

    let sun_y = frame.sun_direction.y;
    let day = daylight();
    let tw = twilight();
    let rain = max(frame.rain, frame.thunder * 1.2);

    let day_amb = vec3<f32>(0.56, 0.74, 0.96) * 0.68;
    let tw_amb = vec3<f32>(0.58, 0.38, 0.56) * 0.46;
    let night_amb = vec3<f32>(0.055, 0.085, 0.155) * 0.38;
    let rain_amb = vec3<f32>(0.34, 0.38, 0.44) * 0.48;

    var amb = mix(night_amb, day_amb, day);
    amb = mix(amb, tw_amb, tw * (1.0 - rain * 0.7));
    amb = mix(amb, rain_amb, clamp(rain, 0.0, 1.0));
    return amb;
}

// Photon analytical Rayleigh + Mie + Ozone sky scattering along `ray_dir`
fn photon_sky_atmosphere(ray_dir: vec3<f32>) -> vec3<f32> {
    let mu = max(ray_dir.y, 0.001);
    let mu_s = frame.sun_direction.y;
    let nu_sun = dot(ray_dir, frame.sun_direction);
    let nu_moon = dot(ray_dir, frame.moon_direction);

    let day = daylight();
    let tw = twilight();
    let night = night_factor();
    let rain = frame.rain;

    // Stretch horizon gently like Photon's `atmosphere_scattering_uv`: mu *= sqrt(sqrt(mu))
    let h = pow(mu, 0.65);

    // Rayleigh zenith-to-horizon gradient with Ozone Chappuis band absorption at twilight
    let day_zenith = vec3<f32>(0.11, 0.34, 0.86);
    let day_horizon = vec3<f32>(0.58, 0.78, 0.98);
    var day_sky = mix(day_horizon, day_zenith, smoothstep(0.0, 0.85, h));

    // Sunset / Sunrise Ozone + Rayleigh scattering
    let ozone_zenith = vec3<f32>(0.05, 0.10, 0.30);
    let dusk_mid = vec3<f32>(0.36, 0.22, 0.48);
    let sun_side = pow(max(nu_sun, 0.0), 1.8);
    let dusk_horizon = mix(vec3<f32>(0.62, 0.28, 0.42), vec3<f32>(1.15, 0.48, 0.15), sun_side);
    var dusk_sky = mix(dusk_horizon, dusk_mid, smoothstep(0.0, 0.32, h));
    dusk_sky = mix(dusk_sky, ozone_zenith, smoothstep(0.25, 0.80, h));

    // Night sky
    let night_zenith = vec3<f32>(0.012, 0.020, 0.048);
    let night_horizon = vec3<f32>(0.032, 0.052, 0.105);
    let night_sky = mix(night_horizon, night_zenith, smoothstep(0.0, 0.70, h));

    var sky = mix(night_sky, day_sky, day);
    sky = mix(sky, dusk_sky, tw * (1.0 - rain * 0.8));

    // Photon's Mie forward scattering around Sun and Moon
    let mie_sun = henyey_greenstein_phase(nu_sun, 0.77) * (1.0 - rain * 0.9);
    let sun_trans = photon_atmosphere_transmittance(max(mu_s, 0.0));
    sky += PHOTON_SUNLIGHT_COLOR * sun_trans * min(mie_sun * 0.45, 2.2) * smoothstep(-0.08, 0.08, mu_s);

    let mie_moon = henyey_greenstein_phase(nu_moon, 0.82) * (1.0 - rain * 0.9);
    sky += vec3<f32>(0.45, 0.62, 0.95) * min(mie_moon * 0.08, 0.35) * night;

    // Rain desaturation & overcast blend (`atmosphere_post_processing`)
    let rain_zenith = vec3<f32>(0.18, 0.21, 0.26);
    let rain_horizon = vec3<f32>(0.38, 0.42, 0.48);
    let storm_mul = 1.0 - frame.thunder * 0.45;
    let rain_sky = mix(rain_horizon, rain_zenith, smoothstep(0.0, 0.75, h)) * storm_mul;
    sky = mix(sky, rain_sky, rain);

    // Lower hemisphere ground bounce
    if ray_dir.y < 0.0 {
        let ground_fade = 1.0 - smoothstep(-0.40, 0.0, ray_dir.y);
        let horizon_col = mix(mix(night_horizon, day_horizon, day), dusk_horizon, tw * (1.0 - rain));
        sky = mix(sky, horizon_col * 0.32, ground_fade);
    }

    return max(sky, vec3<f32>(0.0));
}

// ============================================================================
// PHOTON TONEMAPPING OPERATORS (post_processing/tonemap_operators.glsl)
// ============================================================================

fn tonemap_aces_fit(rgb_in: vec3<f32>) -> vec3<f32> {
    let v = rgb_in * 1.35;
    let m1 = mat3x3<f32>(
        vec3<f32>(0.59719, 0.07600, 0.02840),
        vec3<f32>(0.35458, 0.90834, 0.13383),
        vec3<f32>(0.04823, 0.01566, 0.83777)
    );
    let m2 = mat3x3<f32>(
        vec3<f32>(1.60475, -0.10208, -0.00327),
        vec3<f32>(-0.53108, 1.10813, -0.07276),
        vec3<f32>(-0.07367, -0.00605, 1.07602)
    );
    let x = m1 * v;
    let a = x * (x + 0.0245786) - 0.000090537;
    let b = x * (0.983729 * x + 0.4329510) + 0.238081;
    return to_display(saturate_v3(m2 * (a / b)));
}

fn tonemap_hejl_burgess(rgb_in: vec3<f32>) -> vec3<f32> {
    let rgb = rgb_in * min(vec3<f32>(1.0), vec3<f32>(1.0) - 0.8 * exp(-250.0 * rgb_in));
    let mapped = (rgb * (6.2 * rgb + 0.5)) / (rgb * (6.2 * rgb + 1.7) + 0.06);
    return saturate_v3(mapped);
}

fn tonemap_lottes(rgb_in: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(1.35);
    let d = vec3<f32>(0.92);
    let hdr_max = vec3<f32>(8.0);
    let mid_in = vec3<f32>(0.22);
    let mid_out = vec3<f32>(0.30);
    let b = (-pow(mid_in, a) + pow(hdr_max, a) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    let c = (pow(hdr_max, a * d) * pow(mid_in, a) - pow(hdr_max, a) * pow(mid_in, a * d) * mid_out)
        / ((pow(hdr_max, a * d) - pow(mid_in, a * d)) * mid_out);
    let x = max(rgb_in, vec3<f32>(0.0));
    let mapped = pow(x, a) / (pow(x, a * d) * b + c);
    return to_display(saturate_v3(mapped));
}

fn tonemap_ozius(rgb_in: vec3<f32>) -> vec3<f32> {
    let a = vec3<f32>(0.46);
    let b = vec3<f32>(0.60);
    let x = max(rgb_in * 1.4, vec3<f32>(0.0));
    let cr = mix(vec3<f32>(luminance(x)), x, 0.5) + vec3<f32>(1.0);
    let p = pow(x / (vec3<f32>(1.0) + x), a);
    let lin = pow(p * p * (vec3<f32>(3.0) - 2.0 * p), cr / b);
    return to_display(saturate_v3(lin));
}

fn photon_tonemap(hdr: vec3<f32>, op: u32) -> vec3<f32> {
    let clean = max(hdr, vec3<f32>(0.0));
    if op == 1u {
        return tonemap_hejl_burgess(clean);
    }
    if op == 2u {
        return tonemap_lottes(clean);
    }
    if op == 3u {
        return tonemap_ozius(clean);
    }
    return tonemap_aces_fit(clean);
}

// ============================================================================
// ITERATIONT END SKY & PLANETARY SYSTEM (Tahnass — EndSky.glsl & Utilities.glsl)
// ============================================================================

// Planckian locus blackbody radiation (Utilities.glsl: Blackbody)
fn blackbody(temperature: f32) -> vec3<f32> {
    let t = max(temperature, 1000.0);
    let rt = 1.0 / t;
    let rt2 = rt * rt;
    let coeff_x = vec4<f32>(rt2 * rt, rt2, rt, 1.0);

    let sx0 = vec4<f32>(-0.2661293e9, -0.2343589e6, 0.8776956e3, 0.179910);
    let sx1 = vec4<f32>(-3.0258469e9,  2.1070479e6, 0.2226347e3, 0.240390);
    let x = dot(coeff_x, select(sx1, sx0, t < 4000.0));

    let x2 = x * x;
    let coeff_y = vec4<f32>(x2 * x, x2, x, 1.0);
    let sy0 = vec4<f32>(-1.1063814, -1.34811020, 2.18555832, -0.20219683);
    let sy1 = vec4<f32>(-0.9549476, -1.37418593, 2.09137015, -0.16748867);
    let sy2 = vec4<f32>( 3.0817580, -5.87338670, 3.75112997, -0.37001483);
    let sy = select(select(sy2, sy1, t < 4000.0), sy0, t < 2222.0);
    let z = 1.0 / max(dot(coeff_y, sy), 1e-5);

    var xyz = vec3<f32>(x * z, 1.0, z);
    xyz.z -= xyz.x + 1.0;

    // GLSL column-major mat3 in Utilities.glsl
    let xyz_to_srgb = mat3x3<f32>(
        vec3<f32>( 3.24097, -0.96924,  0.05563),
        vec3<f32>(-1.53738,  1.87597, -0.20398),
        vec3<f32>(-0.49861,  0.04156,  1.05697)
    );
    return max(xyz_to_srgb * xyz, vec3<f32>(0.0));
}

fn ray_plane_intersection(ori: vec3<f32>, dir: vec3<f32>, normal: vec3<f32>) -> vec3<f32> {
    let ray_plane_angle = dot(dir, normal);
    var plane_ray_dist = 1e8;
    var intersection_pos = dir * plane_ray_dist;
    if abs(ray_plane_angle) > 0.0001 {
        plane_ray_dist = dot(-ori, normal) / ray_plane_angle;
        intersection_pos = ori + dir * plane_ray_dist;
    }
    return intersection_pos;
}

fn ray_sphere_intersection(ori: vec3<f32>, dir: vec3<f32>, radius: f32) -> vec2<f32> {
    let b = dot(ori, dir);
    let c = -radius * radius + dot(ori, ori);
    let d = b * b - c;
    if d >= 0.0 {
        let sd = sqrt(d);
        return vec2<f32>(-b - sd, -b + sd);
    }
    return vec2<f32>(1e10, -1e10);
}

fn mie_phase_function(g: f32, nu: f32) -> f32 {
    let gg = g * g;
    let k = 0.1193662 * (1.0 - gg) / (2.0 + gg);
    return k * (1.0 + nu * nu) * pow(max(1.0 + gg - 2.0 * g * nu, 1e-4), -1.5);
}

// IterationT ShadowModelViewEnd.glsl: End directional light vector
fn end_light_dir() -> vec3<f32> {
    // Derived from ShadowModelViewEnd rotationAngle = vec3(0.28, -1.1, 1.0)
    return normalize(vec3<f32>(0.54, 0.42, -0.73));
}

fn end_time_factor(cycle_speed: f32, angle_deg: f32) -> f32 {
    let base = angle_deg / 360.0 + 0.282;
    let anim = frame.time * (cycle_speed / 900.0);
    return fract(base + anim) * TAU;
}

fn end_planet_shadow(tf: f32) -> f32 {
    return (1.0 - smoothstep(0.35, 0.62, tf)) + smoothstep(1.6, 1.87, tf);
}

// IterationT EndSky.glsl: CalculateStars
fn it_calculate_stars(world_dir_in: vec3<f32>) -> vec3<f32> {
    let angle_y = frame.time * 0.001;
    let cy = cos(angle_y);
    let sy = sin(angle_y);
    let rot_y = mat3x3<f32>(
        vec3<f32>(cy, 0.0, sy),
        vec3<f32>(0.0, 1.0, 0.0),
        vec3<f32>(-sy, 0.0, cy)
    );
    var world_dir = rot_y * world_dir_in;

    let sun_vec = end_light_dir();
    let cosine = dot(sun_vec, vec3<f32>(0.0, 0.0, 1.0));
    let axis = cross(sun_vec, vec3<f32>(0.0, 0.0, 1.0));
    let cosec_sq = 1.0 / max(dot(axis, axis), 1e-5);
    world_dir = cosine * world_dir + cross(axis, world_dir) + (cosec_sq - cosec_sq * cosine) * dot(axis, world_dir) * axis;

    let scale = 384.0;
    let coverage = 0.009;
    let max_lum = 0.055;
    let p = world_dir * scale;
    let i = floor(p);
    let f = p - i;
    let r = dot(f - vec3<f32>(0.5), f - vec3<f32>(0.5));

    var i3 = fract(i * vec3<f32>(443.897, 441.423, 437.195));
    i3 += dot(i3, i3.yzx + vec3<f32>(19.19));
    var h = fract((i3.xx + i3.yz) * i3.zy);
    h.y = 2.0 * h.y - 4.0 * h.y * h.y + 3.0 * h.y * h.y * h.y;

    let c = remap_saturate(h.x, 1.0 - coverage, 1.0);
    return (max_lum * remap_saturate(r, 0.25, 0.0) * c * c) * blackbody(mix(4000.0, 8000.0, h.y));
}

// IterationT EndSky.glsl: Chandrasekhar H-function & planetary surface scattering (ppss)
fn it_h_func(albedo: vec3<f32>, a_in: f32) -> vec3<f32> {
    let a = max(a_in, 1e-4);
    let r_big = sqrt(max(vec3<f32>(1.0) - albedo, vec3<f32>(0.0)));
    let r = (vec3<f32>(1.0) - r_big) / (vec3<f32>(1.0) + r_big);
    var h = r + (vec3<f32>(0.5) - r * a) * log((1.0 + a) / a);
    h *= albedo * a;
    return vec3<f32>(1.0) / max(vec3<f32>(1.0) - h, vec3<f32>(1e-4));
}

fn it_ppss(albedo_in: vec3<f32>, normal: vec3<f32>, eye_dir: vec3<f32>, light_dir: vec3<f32>) -> vec3<f32> {
    let ndl = max(dot(normal, light_dir), 0.0);
    let ndv = max(dot(normal, eye_dir), 0.0);
    if ndl <= 0.0 || ndv <= 0.0 {
        return vec3<f32>(0.0);
    }
    let albedo = albedo_in * curve_f(saturate_f(ndl));
    let col = albedo * it_h_func(albedo, ndl) * it_h_func(albedo, ndv) / max(4.0 * PI * (ndl + ndv), 1e-4);
    return saturate_v3(col);
}

fn it_disc(a: f32, s: f32, h: f32) -> f32 {
    let d = curve_f(saturate_f((a - (1.0 - s)) * h));
    return d * d;
}

// 1D procedural noise for IterationT's planetary rings (5 octaves)
fn it_ring_fbm(ray_radius: f32) -> f32 {
    let oct_alpha = 0.5;
    let oct_scale = 4.0;
    let oct_shift = (oct_alpha / oct_scale) / 5.0;
    var accum = 0.0;
    var alpha = 0.5;
    var pos = ray_radius * 0.5 + 0.69;
    for (var i = 0; i < 5; i++) {
        // High-frequency smooth 1D band noise matching noisetex.z
        let p64 = pos * 64.0;
        let pi = floor(p64);
        let pf = curve_f(fract(p64));
        let n = mix(hash21(vec2<f32>(pi, 13.7)), hash21(vec2<f32>(pi + 1.0, 13.7)), pf);
        accum += alpha * n;
        pos = pos * oct_scale;
        alpha *= oct_alpha;
    }
    return accum + oct_shift;
}

// IterationT EndSky.glsl: PlanetEnd2 (The Giant Ringed Planet in The End)
fn it_planet_end2(color_in: vec3<f32>, eye_in: vec3<f32>, ray_dir_in: vec3<f32>, light_dir_in: vec3<f32>, tf: f32) -> vec3<f32> {
    var color = color_in;
    // Scaled by 1e-6 so standard f32 precision never overflows `radius * radius` (20.0^2 = 400.0)
    // Ray-sphere intersection and all ratios (eye.y / Rground, thickness) are 100% scale-invariant!
    let r_ground = 20.0;
    let r_atmo = 20.1;
    var eye = eye_in * 1e-6;
    eye.y += r_ground + 15.0;

    let p_shadow = end_planet_shadow(tf);
    let v_dot_l = dot(light_dir_in, ray_dir_in);
    let mie = mie_phase_function(0.8, v_dot_l);

    let angle_x = -1.57079633 + (0.2 * sin(tf + 3.0) - 0.1);
    let angle_y = tf;

    let cx = cos(angle_x);
    let sx = sin(angle_x);
    let cy = cos(angle_y);
    let sy = sin(angle_y);

    let rot_x = mat3x3<f32>(
        vec3<f32>(1.0, 0.0, 0.0),
        vec3<f32>(0.0, cx, -sx),
        vec3<f32>(0.0, sx, cx)
    );
    let rot_y = mat3x3<f32>(
        vec3<f32>(cy, 0.0, sy),
        vec3<f32>(0.0, 1.0, 0.0),
        vec3<f32>(-sy, 0.0, cy)
    );
    let eye_rot = rot_x * rot_y;

    let ring_angle = 0.008 * sin(tf + 4.6);
    let cr = cos(ring_angle);
    let sr = sin(ring_angle);
    let ring_rot = mat3x3<f32>(
        vec3<f32>(1.0, 0.0, 0.0),
        vec3<f32>(0.0, cr, sr),
        vec3<f32>(0.0, -sr, cr)
    );
    let ring_up = vec3<f32>(0.0, sr, cr);

    let ray_dir = eye_rot * ray_dir_in;
    let light_dir = eye_rot * light_dir_in;

    let ray_dir_ring = ring_rot * ray_dir;
    let light_dir_ring = ring_rot * light_dir;

    let ring_origin = vec3<f32>(0.0, cr, sr) * (eye.y / r_ground);

    var surface = vec3<f32>(0.0);
    let ground_hit = ray_sphere_intersection(eye, ray_dir, r_ground);
    let atmo_hit = ray_sphere_intersection(eye, ray_dir, r_atmo);

    let surface_pos = ray_dir * ground_hit.x;
    let surface_normal = normalize(surface_pos + vec3<f32>(0.0, eye.y, 0.0));

    if ground_hit.y > 0.0 {
        color = vec3<f32>(0.0);
        let surface_albedo = vec3<f32>(0.98, 0.87, 0.55);
        surface = it_ppss(surface_albedo, surface_normal, -ray_dir, light_dir);

        // Ring shadow cast onto the planet surface
        let origin = ring_origin + surface_pos / r_ground;
        let ray_pos = ray_plane_intersection(origin, light_dir_ring, vec3<f32>(0.0, 0.0, 1.0));
        let ray_rad = length(ray_pos);
        if ray_rad > 1.6 && ray_rad < 2.6 && dot(ray_pos - origin, light_dir_ring) > 0.0 {
            let fbm_val = it_ring_fbm(ray_rad);
            let shadow_atten = exp(-cube_f(saturate_f(fbm_val - 0.1) * 1.5) * smoothstep(1.6, 1.76, ray_rad));
            surface *= shadow_atten;
        }

        let u_dot_n = saturate_f(dot(ring_up, surface_normal));
        let d_dot_n = saturate_f(dot(-ring_up, surface_normal));
        let ol_vec = normalize(vec3<f32>(-light_dir.x + 1e-5, -light_dir.y, 0.0));
        let ol_rot = vec3<f32>(ol_vec.x, cr * ol_vec.y - sr * ol_vec.z, sr * ol_vec.y + cr * ol_vec.z);
        let ol_dot_n = saturate_f(dot(ol_rot, surface_normal));

        var ring_lighting = it_disc(u_dot_n, 1.2, 1.5) * (1.0 - it_disc(u_dot_n, 3.4, 0.3));
        ring_lighting += it_disc(d_dot_n, 1.2, 1.5) * (1.0 - it_disc(d_dot_n, 3.4, 0.3));
        ring_lighting *= 1.0 - it_disc(ol_dot_n, 0.7, 1.3);

        surface += surface_albedo * (1.5e-4 + ring_lighting * 0.01);
    }

    if atmo_hit.y > 0.0 {
        let is_ground = select(0.0, 1.0, ground_hit.y > 0.0);
        // Since r_ground is scaled by 1e-6, 1e-7 * 1e6 = 0.1
        let thickness = (atmo_hit.y - atmo_hit.x - (ground_hit.y - ground_hit.x) * is_ground) * 0.1;
        var top_atmo_mie = mie * thickness * thickness;
        top_atmo_mie *= mix(1.0, 1.0 - smoothstep(0.4, 0.9, dot(surface_normal, normalize(eye))), is_ground);
        surface += top_atmo_mie * vec3<f32>(0.65, 0.70, 1.0);
    }

    color += surface * 0.6;

    // Planetary rings in the sky
    let in_ring = saturate_f(abs(ring_angle) * 3000.0 - 0.8);
    var ring = 0.0;
    var transmittance = 1.0;

    if ray_dir_ring.z * ring_angle < 0.0 {
        let origin = vec3<f32>(0.0, cr, sr) * (eye.y / r_ground);
        let ring_pos = ray_plane_intersection(origin, ray_dir_ring, vec3<f32>(0.0, 0.0, 1.0));
        let ray_rad = length(ring_pos);

        if ray_rad > 1.6 && ray_rad < 2.6 {
            let fbm_val = it_ring_fbm(ray_rad);
            ring += cube_f(saturate_f(fbm_val - 0.1) * 1.5);
            ring *= smoothstep(1.6, 1.76, ray_rad);

            if ring_pos.y < 0.0 && ground_hit.y > 0.0 {
                ring = 0.0;
            } else {
                transmittance *= exp2(-ring * 3.0);
            }

            let d = length(cross(light_dir_ring, ring_pos));
            ring *= 0.98 * max(smoothstep(0.8, 1.2, d), select(0.0, 1.0, dot(light_dir_ring, ring_pos) >= 0.0)) + 0.02;
        }
    }

    ring = mix(p_shadow * 0.49 + 0.01, ring, in_ring);
    transmittance = mix(0.7, transmittance, in_ring);

    color *= transmittance;
    ring *= 1.0 + mie * 10.0 * p_shadow;
    color += ring * 0.012 * vec3<f32>(1.0, 0.85, 0.60);

    return color;
}

// IterationT EndSky.glsl: BlackHole_AccretionDisc_Stars
fn it_rotate_matrix(x: f32, y: f32, z: f32) -> mat3x3<f32> {
    let cx = cos(x); let sx = sin(x);
    let cy = cos(y); let sy = sin(y);
    let cz = cos(z); let sz = sin(z);
    let matx = mat3x3<f32>(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, cx, sx), vec3<f32>(0.0, -sx, cx));
    let maty = mat3x3<f32>(vec3<f32>(cy, 0.0, -sy), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(sy, 0.0, cy));
    let matz = mat3x3<f32>(vec3<f32>(cz, sz, 0.0), vec3<f32>(-sz, cz, 0.0), vec3<f32>(0.0, 0.0, 1.0));
    return maty * matx * matz;
}

fn it_pcurve(x: f32) -> f32 {
    let x2 = x * x;
    return 12.207 * x2 * x2 * (1.0 - x);
}

fn it_disc_fbm(pos_in: vec3<f32>, shift: vec3<f32>) -> f32 {
    var pos = pos_in;
    var accum = 0.0;
    var alpha = 0.5;
    for (var i = 0; i < 3; i++) {
        accum += alpha * value_noise3d(pos);
        pos = (pos + shift) * 2.2;
        alpha *= 0.88;
    }
    return accum + 0.13;
}

fn it_black_hole_accretion_disc(
    color_in: vec3<f32>,
    ray_dir_in: vec3<f32>,
    light_dir: vec3<f32>,
    dither: f32,
    doppler: bool,
    with_stars: bool
) -> vec3<f32> {
    var color = color_in;
    // 28 steps at 0.28 step_length covers the exact 8-unit volume around the singularity while staying fast
    let steps = 28;
    let r_steps = 1.0 / 28.0;
    let step_len = 0.28;

    let disc_radius = 2.25;
    let disc_width = 3.5;
    let disc_inner = disc_radius - disc_width * 0.5;

    let eye = -light_dir * 8.0;
    var ray_dir = ray_dir_in;
    var ray_pos = eye + ray_dir * (3.0 + step_len * dither);
    let rotation = it_rotate_matrix(0.1, 0.0, -0.35);

    var result = vec3<f32>(0.0);
    var transmittance = 1.0;
    let shift = frame.time * vec3<f32>(0.03, 0.05, 0.0);

    for (var i = 0; i < 28; i++) {
        if transmittance < 0.001 {
            break;
        }
        // WarpSpace gravitational lensing around origin (0,0,0)
        let sing_dist_sq = dot(ray_pos, ray_pos) + 0.00001;
        let warp_factor = 1.0 / sing_dist_sq;
        let sing_vec = normalize(-ray_pos);
        ray_dir = normalize(ray_dir + sing_vec * (warp_factor * 0.084));
        ray_pos += ray_dir * step_len;

        let disc_pos = rotation * ray_pos;
        let r = length(disc_pos);
        let p = atan2(-disc_pos.z, -disc_pos.x);
        let h = disc_pos.y;

        let radial_grad = 1.0 - saturate_f((r - disc_inner) / disc_width * 0.5);
        let dist = abs(h);
        let disc_thick = max(0.1 * radial_grad, 1e-4);

        let fr = abs(r - disc_inner) + 0.4;
        let fr2 = fr * fr;
        let fade = fr2 * fr2 * 0.04;
        var bloom_factor = 1.0 / (h * h * 40.0 + fade + 0.00002);
        bloom_factor *= saturate_f(2.0 - dist / disc_thick);
        bloom_factor *= bloom_factor;

        let dr = it_pcurve(saturate_f(radial_grad));
        var density = dr * saturate_f(1.0 - dist / disc_thick);
        density = saturate_f(density * 0.7);
        density = saturate_f(density + bloom_factor * 0.1);

        if density > 0.0001 {
            let disc_coord = vec3<f32>(r, p * (1.0 - radial_grad * 0.5) * 0.25, h * 0.1) * 3.5;
            var fbm = it_disc_fbm(disc_coord, shift);
            fbm = fbm * fbm;
            fbm = fbm * fbm;
            density *= fbm * dr;

            let gr = 1.0 - radial_grad;
            let gr2 = gr * gr;
            let glow_strength = 1.0 / (gr2 * gr2 * 400.0 + 0.002);
            var glow = blackbody(2700.0 + glow_strength * 50.0) * glow_strength;

            if doppler {
                glow *= sin(p - 1.07) * 0.75 + 1.0;
            }

            let step_trans = exp2(-density * 9.8);
            let integral = 1.0 - step_trans;
            transmittance *= step_trans;
            result += integral * transmittance * glow;
        }

        let torus_d = length(vec2<f32>(length(disc_pos.xz) - 1.0, disc_pos.y - 0.05));
        var bloom_disc = 1.0 / (pow(max(torus_d, 0.001), 3.5) + 0.001);
        let col_ring = blackbody(12000.0);
        bloom_disc *= select(0.0, 1.0, r >= 0.5);
        result += col_ring * bloom_disc * 0.1 * transmittance;
    }

    result *= r_steps;
    if with_stars {
        color += it_calculate_stars(ray_dir);
    }
    color *= transmittance;
    color += result;
    return color;
}

// IterationT EndSky.glsl: EndFog
fn it_end_fog(dist_in: f32, world_dir_in: vec3<f32>, tf: f32) -> vec3<f32> {
    let light_dir = end_light_dir();
    let v_dot_l = dot(light_dir, world_dir_in);
    let p_shadow = end_planet_shadow(tf);

    let angle_x = -1.57079633 + (0.2 * sin(tf + 3.0) - 0.1) - 0.008 * sin(tf + 4.7);
    let angle_y = tf;
    let cx = cos(angle_x); let sx = sin(angle_x);
    let cy = cos(angle_y); let sy = sin(angle_y);
    let rot_x = mat3x3<f32>(vec3<f32>(1.0, 0.0, 0.0), vec3<f32>(0.0, cx, -sx), vec3<f32>(0.0, sx, cx));
    let rot_y = mat3x3<f32>(vec3<f32>(cy, 0.0, sy), vec3<f32>(0.0, 1.0, 0.0), vec3<f32>(-sy, 0.0, cy));
    let world_dir = (rot_x * rot_y) * world_dir_in;

    let dist = min(dist_in, 512.0);
    let h = max(abs(world_dir.z) * dist * 0.03, 1e-4);
    var density = (1.0 - exp(-h)) / h * dist;
    density *= mie_phase_function(0.3, v_dot_l) * 10.0 * p_shadow + 0.25;
    density *= p_shadow * 0.93 + 0.07;

    // Warm golden-violet cosmic scattering matching IterationT's End atmosphere
    return vec3<f32>(1.0, 0.86, 0.68) * (density * 0.00045);
}
