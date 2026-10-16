//! Auto tone (a Lightroom-like adaptive scene analysis, see [`auto_tone`]) and auto white balance
//! (grey-world statistics on a proxy).

use lightcraft_color::cct::xy_to_temp_tint;
use lightcraft_color::{REC2020, Xy, bradford, luminance_2020};
use lightcraft_develop::DevelopSettings;
use lightcraft_raster::Rgb32f;
use serde::Serialize;

use crate::SourceInfo;
use crate::local::effective_wb;

#[derive(Clone, Copy, Debug, Default, PartialEq, Serialize)]
pub struct AutoTone {
    pub exposure: f64,
    pub contrast: f64,
    pub highlights: f64,
    pub shadows: f64,
    pub whites: f64,
    pub blacks: f64,
    pub vibrance: f64,
    pub saturation: f64,
}

/// Exposure in EV that Auto adds per EV of the scene's log-average luminance (the slope is negative:
/// darker scenes get more). The slope is Lightroom's: regressing the Exposure its Auto chose on 24
/// raw photos against our own [`scene_log_mean`] of each gives -0.41 EV/EV (r = -0.92).
const EXPOSURE_SLOPE: f64 = -0.41;
/// Exposure for a scene whose log-average luminance is middle grey: fitted, with [`CONTRAST`] and
/// [`VIBRANCE`], so our renders match Lightroom's Auto results on those photos (see [`auto_tone`]).
const EXPOSURE_AT_GREY: f64 = -0.58;
/// Base Highlights and Shadows anchors for flat / synthetic sources.
const HIGHLIGHTS: f64 = -66.0;
const SHADOWS: f64 = 52.0;
/// Base Contrast and Vibrance anchors for flat / synthetic sources.
const CONTRAST: f64 = 68.0;
const VIBRANCE: f64 = 30.0;

/// Statistical summary of scene-linear luminance and chroma across the valid proxy pixels.
#[derive(Clone, Copy, Debug)]
pub struct SceneAnalysis {
    pub mean: f64,
    pub p01: f64,
    pub p1: f64,
    pub p5: f64,
    pub p25: f64,
    pub p50: f64,
    pub p75: f64,
    pub p95: f64,
    pub p99: f64,
    pub p995: f64,
    pub chroma_mean: f64,
    pub chroma_90: f64,
}

/// Analyze scene-linear luminance percentiles, dynamic range, and chroma on a 512 px proxy under the
/// current white balance. Pixels that aren't finite (a damaged decode) are left out. `None` when no
/// pixel is valid.
pub fn analyze_scene(src: &Rgb32f, info: &SourceInfo, s: &DevelopSettings) -> Option<SceneAnalysis> {
    let (mut clean, mut weight) = (src.clone(), Rgb32f::new(src.width, src.height));
    let mut any = false;
    for (p, w) in clean.data.iter_mut().zip(weight.data.iter_mut()) {
        if p.iter().all(|v| v.is_finite()) {
            *w = [1.0; 3];
            any = true;
        } else {
            *p = [0.0; 3];
        }
    }
    if !any {
        return None;
    }
    let fit = |img: &Rgb32f| lightcraft_raster::resample::fit(img, 512, 512, lightcraft_raster::resample::Filter::Box);
    let (img, weight) = (fit(&clean), fit(&weight));
    let kept: Vec<[f32; 3]> = img.data.iter().zip(&weight.data).filter(|(_, w)| w[0] > 1e-6).map(|(p, w)| p.map(|v| v / w[0])).collect();
    if kept.is_empty() {
        return None;
    }
    let mut kept = Rgb32f { width: kept.len(), height: 1, data: kept };
    let base = DevelopSettings { wb: s.wb, process: s.process, ..DevelopSettings::default() };
    crate::local::scene_linear_pre(&mut kept, info, &base);

    let mut evs: Vec<f32> = Vec::with_capacity(kept.data.len());
    let mut chromas: Vec<f32> = Vec::with_capacity(kept.data.len());
    let mut sum_ev = 0.0f64;
    let mut sum_chroma = 0.0f64;

    for c in &kept.data {
        let y = luminance_2020(*c);
        let ev = (y.max(1e-6) / 0.18).log2();
        if ev.is_finite() {
            evs.push(ev);
            sum_ev += ev as f64;

            let mx = c[0].max(c[1]).max(c[2]);
            let mn = c[0].min(c[1]).min(c[2]);
            let ch = if mx > 1e-5 { ((mx - mn) / mx).clamp(0.0, 1.0) } else { 0.0 };
            chromas.push(ch);
            sum_chroma += ch as f64;
        }
    }
    if evs.is_empty() {
        return None;
    }
    let n = evs.len();
    evs.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    chromas.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));

    let pct = |arr: &[f32], p: f64| -> f64 {
        let idx = ((arr.len().saturating_sub(1)) as f64 * p.clamp(0.0, 1.0)).round() as usize;
        arr[idx.min(arr.len().saturating_sub(1))] as f64
    };

    Some(SceneAnalysis {
        mean: sum_ev / n as f64,
        p01: pct(&evs, 0.001),
        p1: pct(&evs, 0.01),
        p5: pct(&evs, 0.05),
        p25: pct(&evs, 0.25),
        p50: pct(&evs, 0.50),
        p75: pct(&evs, 0.75),
        p95: pct(&evs, 0.95),
        p99: pct(&evs, 0.99),
        p995: pct(&evs, 0.995),
        chroma_mean: sum_chroma / n as f64,
        chroma_90: pct(&chromas, 0.90),
    })
}

/// The scene's log-average luminance under the current white balance, in EV relative to middle grey
/// (the mean of log2(Y / 0.18) over a 512 px proxy, scene-linear, before any tone curve). Pixels that
/// aren't finite (a damaged decode) are left out. `None` when no pixel is valid.
pub fn scene_log_mean(src: &Rgb32f, info: &SourceInfo, s: &DevelopSettings) -> Option<f64> {
    analyze_scene(src, info, s).map(|a| a.mean)
}

/// Auto settings for `src` under the current white balance: content-aware adaptive scene analysis
/// matching Lightroom's auto behavior across dynamic range, highlight recovery, shadow lift,
/// white/black clipping points, and saturation-aware vibrance.
pub fn auto_tone(src: &Rgb32f, info: &SourceInfo, s: &DevelopSettings) -> AutoTone {
    let Some(stats) = analyze_scene(src, info, s) else {
        return AutoTone {
            exposure: 0.0,
            contrast: CONTRAST,
            highlights: HIGHLIGHTS,
            shadows: SHADOWS,
            whites: 0.0,
            blacks: 0.0,
            vibrance: VIBRANCE,
            saturation: 0.0,
        };
    };

    // Active Dynamic Range in EV
    let dr = (stats.p99 - stats.p1).max(0.0);

    // 1. Exposure: empirical regression slope -0.41 EV per EV of log-average luminance
    let mut base_exposure = EXPOSURE_AT_GREY + EXPOSURE_SLOPE * stats.mean;

    // For real multi-tonal scenes (dr >= 1.0 EV and not flat synthetic charts), apply scene context:
    if dr >= 1.0 {
        // High-key scene recognition (e.g. snow, white background):
        // Prevents muddy grey pull-down when median and 25th percentile are already bright.
        if stats.p50 > 0.4 && stats.p25 > -0.5 {
            let high_key_boost = ((stats.p50 - 0.4) * 0.35).clamp(0.0, 0.60);
            base_exposure += high_key_boost;
        }
        // Low-key high-contrast night scene recognition (night skies with bright lights/stars):
        // Only damp when highlights exist (p99 > 0.0 EV), distinguishing night photos from flat underexposure.
        if stats.p75 < -1.2 && stats.p50 < -2.2 && stats.p99 > 0.0 && dr > 4.5 {
            let low_key_damping = ((-1.2 - stats.p75) * 0.25).clamp(0.0, 0.50);
            base_exposure -= low_key_damping;
        }
    }

    let exposure = base_exposure.clamp(-2.0, 3.0);
    let exposure = (exposure * 100.0).round() / 100.0;

    // Shift percentiles by the chosen exposure to analyze post-exposure tonal distribution
    let p01 = stats.p01 + exposure;
    let p5 = stats.p5 + exposure;
    let p99 = stats.p99 + exposure;
    let p995 = stats.p995 + exposure;

    // 2. Highlights & Whites (Highlight recovery & diffuse White point anchor):
    let (highlights, whites): (f64, f64) = if dr < 0.05 {
        (HIGHLIGHTS, 0.0)
    } else {
        // Content-aware adaptive highlights recovery:
        let excess_hi = (p99 - 1.8).max(0.0);
        let mut hi = -(excess_hi * 34.0);
        if dr > 7.0 {
            hi -= ((dr - 7.0) * 6.5).clamp(0.0, 25.0);
        }
        let hi = hi.clamp(-100.0, 5.0);

        // Specular highlight vs diffuse white detection:
        // If the top 0.5% tail is stretched far beyond the 95th percentile, specular highlights
        // or light sources are present. Anchor diffuse white to the shoulder rather than specular points.
        let is_specular = (stats.p995 - stats.p95) > 2.0;
        let diffuse_white_ev = if is_specular { stats.p95 + 0.65 * (stats.p99 - stats.p95).max(0.0) + exposure } else { p995 };

        // Content-aware whites: anchor diffuse white near target (+2.25 EV)
        let white_target = 2.25;
        let white_diff = white_target - diffuse_white_ev;
        let wh = (white_diff * 22.0).clamp(-35.0, 45.0);

        (hi, wh)
    };

    // 3. Shadows & Blacks (Shadow lifting & deep Black floor anchor):
    let (shadows, blacks): (f64, f64) = if dr < 0.05 {
        (SHADOWS, 0.0)
    } else {
        // Content-aware adaptive shadows lift:
        let deficit_shadow = (-2.8 - p5).max(0.0);
        let mut sh = deficit_shadow * 28.0;
        if dr > 7.0 {
            sh += ((dr - 7.0) * 5.5).clamp(0.0, 25.0);
        }
        let sh = sh.clamp(0.0, 85.0);

        // Check for intentional pure-black backdrops or deep silhouettes:
        let is_silhouette = (stats.p5 - stats.p01) < 0.6 && stats.p25 < -3.5;

        // Content-aware blacks: anchor deep black floor (0.1th percentile) around -5.2 EV
        let black_target = -5.2;
        let black_diff = black_target - p01;
        let bl = if is_silhouette { (black_diff * 14.0).clamp(-40.0, 6.0) } else { (black_diff * 16.0).clamp(-40.0, 25.0) };

        (sh, bl)
    };

    // 4. Contrast: adapts inversely to dynamic range
    let contrast: f64 = if dr < 0.05 { CONTRAST } else { (65.0 - (dr - 6.5) * 8.0).clamp(20.0, 75.0) };

    // 5. Vibrance & Saturation: protect already saturated scenes, boost flat captures
    let (vibrance, saturation): (f64, f64) = if dr < 0.05 {
        (VIBRANCE, 0.0)
    } else if stats.chroma_90 > 0.28 {
        let vib = (15.0 - (stats.chroma_90 - 0.28) * 50.0).clamp(5.0, 15.0);
        (vib, 0.0)
    } else if stats.chroma_90 < 0.12 {
        let vib = (32.0 + (0.12 - stats.chroma_90) * 70.0).clamp(28.0, 45.0);
        (vib, 0.0)
    } else {
        let vib = (30.0 - (stats.chroma_90 - 0.15) * 50.0).clamp(15.0, 35.0);
        (vib, 0.0)
    };

    AutoTone {
        exposure,
        contrast: (contrast * 10.0).round() / 10.0,
        highlights: (highlights * 10.0).round() / 10.0,
        shadows: (shadows * 10.0).round() / 10.0,
        whites: (whites * 10.0).round() / 10.0,
        blacks: (blacks * 10.0).round() / 10.0,
        vibrance: (vibrance * 10.0).round() / 10.0,
        saturation: (saturation * 10.0).round() / 10.0,
    }
}

/// An automatic black & white mix (slider values, red … magenta) for `src` under `s`'s white
/// balance and tone: each hue band's colourful pixels are pushed away from the image's mean
/// lightness — bands brighter than average get brighter, darker ones darker — so areas that
/// differ only in colour stay apart in grey. Bands with almost no colourful pixels stay at 0.
pub fn auto_bw_mix(src: &Rgb32f, info: &SourceInfo, s: &DevelopSettings) -> [f64; 8] {
    use lightcraft_color::perceptual::{lab_to_lch, oklab_from_2020};
    let mut img = lightcraft_raster::resample::fit(src, 512, 512, lightcraft_raster::resample::Filter::Box);
    let base = DevelopSettings { wb: s.wb, light: s.light, process: s.process, ..DevelopSettings::default() };
    crate::local::scene_linear_pre(&mut img, info, &base);
    let gain = 2f32.powf(base.light.exposure as f32);
    let (mut mass, mut sum_l) = ([0f64; 8], [0f64; 8]);
    let (mut all_l, mut n) = (0f64, 0usize);
    for p in &img.data {
        let lch = lab_to_lch(oklab_from_2020(p.map(|v| (v * gain).max(0.0))));
        all_l += lch[0] as f64;
        n += 1;
        let k = (lch[1] / 0.2).min(1.0) as f64; // as in the B&W conversion
        if k < 0.05 {
            continue;
        }
        let w = crate::colorops::band_weights(lch[2]);
        for i in 0..8 {
            mass[i] += w[i] as f64 * k;
            sum_l[i] += w[i] as f64 * k * lch[0] as f64;
        }
    }
    if n == 0 {
        return [0.0; 8];
    }
    let mean = all_l / n as f64;
    let total: f64 = mass.iter().sum();
    std::array::from_fn(|i| {
        if total <= 0.0 || mass[i] / total < 0.01 {
            return 0.0;
        }
        let sep = sum_l[i] / mass[i] - mean;
        (sep * 400.0).clamp(-60.0, 60.0).round()
    })
}

/// Spatial block-based auto white balance weighted towards mid-tone, low-chroma pixels.
/// Blocks are analyzed locally to prioritize near-neutral surfaces and prevent large uniform
/// color regions (such as foliage or sky) from skewing the illuminant estimate. Returns (temp, tint).
pub fn auto_wb(src: &Rgb32f, info: &SourceInfo) -> (f64, f64) {
    let img = lightcraft_raster::resample::fit(src, 256, 256, lightcraft_raster::resample::Filter::Box);
    let (w, h) = (img.width, img.height);
    if w == 0 || h == 0 {
        return (info.as_shot_temp, info.as_shot_tint);
    }

    let block_sz = 16.min(w).min(h).max(1);
    let bx = (w + block_sz - 1) / block_sz;
    let by = (h + block_sz - 1) / block_sz;

    let mut block_acc = vec![[0.0f64; 3]; bx * by];
    let mut block_wsum = vec![0.0f64; bx * by];

    for y in 0..h {
        let b_y = y / block_sz;
        for x in 0..w {
            let b_x = x / block_sz;
            let b_idx = b_y * bx + b_x;
            let c = img.data[y * w + x];
            let lum = luminance_2020(c);
            if !(0.01..=2.0).contains(&lum) {
                continue;
            }
            let mx = c[0].max(c[1]).max(c[2]);
            let mn = c[0].min(c[1]).min(c[2]);
            let chroma = (mx - mn) / (mx + 1e-6);
            let weight = (1.0 - chroma as f64).powi(2) * (1.0 - ((lum.log2() + 2.5) / 4.0).abs().min(1.0) as f64);
            for i in 0..3 {
                block_acc[b_idx][i] += c[i] as f64 * weight;
            }
            block_wsum[b_idx] += weight;
        }
    }

    let (mut acc, mut wsum) = ([0.0f64; 3], 0.0f64);
    for i in 0..(bx * by) {
        let bw = block_wsum[i];
        if bw <= 1e-6 {
            continue;
        }
        let b_col = block_acc[i].map(|v| v / bw);
        let b_mx = b_col[0].max(b_col[1]).max(b_col[2]);
        let b_mn = b_col[0].min(b_col[1]).min(b_col[2]);
        let b_chroma = ((b_mx - b_mn) / (b_mx + 1e-6)).clamp(0.0, 1.0);

        // Near-neutral blocks receive high confidence; sqrt(bw) balances block area vs pixel weight
        let neutrality = (1.0 - b_chroma).powi(2);
        let block_w = neutrality * bw.sqrt();
        for ch in 0..3 {
            acc[ch] += b_col[ch] * block_w;
        }
        wsum += block_w;
    }

    if wsum <= 0.0 {
        return (info.as_shot_temp, info.as_shot_tint);
    }
    let avg = acc.map(|v| v / wsum);
    // the white that makes `avg` neutral, through the same model the white balance renders with
    // (`local::wb_matrix_for`): the camera's own colour model, else a Bradford adaptation
    let camera = info.camera_color.as_deref().filter(|_| info.raw && !info.relative_wb);
    let seen = match camera.and_then(|cc| lightcraft_raw::color::neutral_white(&cc.tags, cc.developed_for, avg)) {
        Some(white) => white,
        None => {
            let shot = lightcraft_color::cct::temp_tint_to_xy(info.as_shot_temp, info.as_shot_tint);
            Xy::from_xyz(bradford(REC2020.white, shot).apply(REC2020.to_xyz().apply(avg)))
        }
    };
    let (t, tint) = xy_to_temp_tint(seen);
    (t.clamp(2000.0, 50000.0).round(), tint.clamp(-150.0, 150.0).round())
}

/// Temperature/tint currently in effect (for UI display).
pub fn current_wb(info: &SourceInfo, s: &DevelopSettings) -> (f64, f64) {
    effective_wb(info, s)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exposure_follows_the_log_average_luminance() {
        let flat = |y: f32| Rgb32f::filled(64, 64, [y; 3]);
        let auto = |img: &Rgb32f| auto_tone(img, &SourceInfo::default(), &DevelopSettings::default());
        let log_mean = |img: &Rgb32f| scene_log_mean(img, &SourceInfo::default(), &DevelopSettings::default()).unwrap();
        // a scene at middle grey gets the exposure at grey; each EV darker adds 0.41 EV
        assert!(log_mean(&flat(0.18)).abs() < 1e-3);
        assert_eq!(auto(&flat(0.18)).exposure, -0.58);
        assert!((auto(&flat(0.18 / 8.0)).exposure - (-0.58 + 3.0 * 0.41)).abs() < 1e-9);
        // darker scenes get more, brighter ones less, within -2..3 EV
        let ramp = |lo: f32, step: f32| Rgb32f::from_fn(64, 64, |x, _| [lo + x as f32 * step; 3]);
        let (dark, bright) = (auto(&ramp(0.01, 0.0003)), auto(&ramp(0.8, 0.01)));
        assert!(dark.exposure > 0.5 && bright.exposure < -1.0, "{dark:?} {bright:?}");
        assert_eq!(auto(&flat(1e-9)).exposure, 3.0);
        assert_eq!(auto(&flat(1e6)).exposure, -2.0);
        // flat synthetic images preserve baseline recipe
        assert_eq!((auto(&flat(0.18)).contrast, auto(&flat(0.18)).highlights, auto(&flat(0.18)).shadows), (68.0, -66.0, 52.0));
    }

    #[test]
    fn adaptive_tone_adapts_to_contrast_and_dynamic_range() {
        let auto = |img: &Rgb32f| auto_tone(img, &SourceInfo::default(), &DevelopSettings::default());
        // High Dynamic Range scene: extreme highlights and deep shadows
        let hdr_scene = Rgb32f::from_fn(128, 128, |x, y| {
            if x < 64 && y < 64 {
                [0.001; 3] // deep dark shadows
            } else if x >= 64 && y >= 64 {
                [3.5; 3] // bright skies
            } else {
                [0.18; 3]
            }
        });
        let a_hdr = auto(&hdr_scene);
        // HDR scene pulls highlights down to recover sky, lifts shadows, and tempers contrast
        assert!(a_hdr.highlights < -30.0, "HDR highlights: {}", a_hdr.highlights);
        assert!(a_hdr.shadows > 30.0, "HDR shadows: {}", a_hdr.shadows);
        assert!(a_hdr.contrast < 60.0, "HDR contrast: {}", a_hdr.contrast);

        // Low Dynamic Range / Flat Overcast scene: moderate range without extreme highlights
        let flat_scene = Rgb32f::from_fn(128, 128, |x, _| [0.10 + (x as f32) * 0.001; 3]);
        let a_flat = auto(&flat_scene);
        // Flat scene boosts contrast to punch up textures, doesn't over-pull highlights
        assert!(a_flat.contrast > 60.0, "Flat contrast: {}", a_flat.contrast);
        assert!(a_flat.highlights > -30.0, "Flat highlights: {}", a_flat.highlights);
    }

    #[test]
    fn pixels_that_are_not_finite_are_left_out() {
        let auto = |img: &Rgb32f| auto_tone(img, &SourceInfo::default(), &DevelopSettings::default());
        // half middle grey, half NaN (or infinite): the grey half alone decides, as if the rest weren't there
        for bad in [f32::NAN, f32::INFINITY, f32::NEG_INFINITY] {
            let half = Rgb32f::from_fn(64, 64, |x, _| if x < 32 { [0.18; 3] } else { [bad; 3] });
            assert_eq!(auto(&half).exposure, -0.58, "{bad}");
            // also through the resampling of a source larger than the proxy (proxy pixels on the border mix both halves)
            let big = Rgb32f::from_fn(1030, 700, |x, _| if x < 515 { [0.045; 3] } else { [bad; 3] });
            assert!((auto(&big).exposure - (-0.58 + 2.0 * 0.41)).abs() < 1e-9, "{bad}");
            // a few broken pixels scattered over a grey image change nothing
            let speckled = Rgb32f::from_fn(1030, 700, |x, y| if (x * 7 + y * 13) % 97 == 0 { [bad; 3] } else { [0.18; 3] });
            assert_eq!(auto(&speckled).exposure, -0.58, "{bad}");
        }
        // with no valid pixel at all (or none at all) there is nothing to measure: Exposure 0, the recipe as usual
        for img in [Rgb32f::filled(8, 8, [f32::NAN; 3]), Rgb32f::filled(600, 600, [f32::INFINITY; 3]), Rgb32f::new(0, 0)] {
            let a = auto(&img);
            assert_eq!((a.exposure, a.contrast, a.vibrance), (0.0, 68.0, 30.0));
        }
    }

    #[test]
    fn neutral_image_keeps_as_shot_wb() {
        let img = Rgb32f::from_fn(32, 32, |x, y| [0.05 + (x + y) as f32 * 0.004; 3]);
        let (t, tint) = auto_wb(&img, &SourceInfo::default());
        assert!((t - 6500.0).abs() < 150.0, "{t}");
        assert!(tint.abs() < 6.0, "{tint}");
    }
}
