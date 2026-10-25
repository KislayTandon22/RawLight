//! Real-world RAW evaluation and auto-editing test using diverse Signature Edits RAWs.

use crate::{Session, SourceLevel};
use serde_json::json;
use std::collections::BTreeMap;
use std::path::PathBuf;
use std::time::Instant;

fn signature_edits_dir() -> Option<PathBuf> {
    let p = PathBuf::from("/Users/kislayranjanneetandon/Documents/Lightworks Ipad/test_raws/signature_edits");
    if p.is_dir() { Some(p) } else { None }
}

#[test]
fn test_signature_edits_raw_import_and_auto_edit_flow() {
    let Some(dir) = signature_edits_dir() else { return };
    let files: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            let ext = p.extension().and_then(|s| s.to_str()).unwrap_or("").to_lowercase();
            matches!(ext.as_str(), "dng" | "arw" | "cr2" | "nef" | "rw2")
        })
        .filter_map(|p| p.to_str().map(String::from))
        .collect();

    assert!(!files.is_empty(), "Signature Edits raw files must be present");
    println!("Found {} downloaded RAW files for auto-edit evaluation", files.len());

    let mut session = Session::new().with_fs();
    let report = crate::import::import_with(
        &mut session,
        &files,
        &crate::import::ImportOptions { mode: crate::import::ImportMode::Add, ..Default::default() },
    )
    .expect("importing RAW files into session");

    println!("Imported {} photos into session (failed: {})", report.imported.len(), report.failed.len());
    assert!(!report.imported.is_empty(), "Imported photos should not be empty");

    let mut portraits = 0;
    let mut sunsets = 0;
    let mut landscapes = 0;
    let mut evaluated = 0;

    #[derive(Default)]
    struct FormatStats {
        count: usize,
        total_decode_us: u128,
        total_tone_us: u128,
        total_wb_us: u128,
        exposures: Vec<f64>,
        highlights: Vec<f64>,
        shadows: Vec<f64>,
        whites: Vec<f64>,
        blacks: Vec<f64>,
        contrasts: Vec<f64>,
        vibrances: Vec<f64>,
        drs: Vec<f64>,
        wb_temp_deltas: Vec<f64>,
        wb_tint_deltas: Vec<f64>,
    }

    let mut by_format: BTreeMap<String, FormatStats> = BTreeMap::new();
    let mut all_tone_latencies_us = Vec::new();
    let mut all_wb_latencies_us = Vec::new();
    let mut all_decode_latencies_us = Vec::new();

    for &id_num in &report.imported {
        let id = lightcraft_catalog::PhotoId(id_num);
        let (file_name, ext) = {
            let ph = session.catalog.photo(id).expect("photo exists");
            let ext = PathBuf::from(&ph.file_name).extension().and_then(|s| s.to_str()).unwrap_or("unknown").to_uppercase();
            (ph.file_name.clone(), ext)
        };

        let t_decode_start = Instant::now();
        let src = match session.source_now(id, SourceLevel::Thumb) {
            Ok(s) => s,
            Err(e) => {
                eprintln!("source_now skipped for {file_name}: {e}");
                continue;
            }
        };
        let decode_us = t_decode_start.elapsed().as_micros();
        all_decode_latencies_us.push(decode_us);

        let info = session.source_info(id);
        let d = session.develop_of(id).as_deref().cloned().unwrap_or_default();

        let t_tone_start = Instant::now();
        let auto = lightcraft_pipeline::auto::auto_tone(&src, &info, &d);
        let tone_us = t_tone_start.elapsed().as_micros();
        all_tone_latencies_us.push(tone_us);

        let t_wb_start = Instant::now();
        let (auto_temp, auto_tint) = lightcraft_pipeline::auto::auto_wb(&src, &info);
        let wb_us = t_wb_start.elapsed().as_micros();
        all_wb_latencies_us.push(wb_us);

        assert!(auto.exposure.is_finite() && auto.exposure.abs() <= 5.0, "exposure must be reasonable: {}", auto.exposure);
        assert!(auto.contrast.is_finite() && auto.contrast.abs() <= 100.0);
        assert!(auto.highlights.is_finite() && auto.highlights.abs() <= 100.0);
        assert!(auto.shadows.is_finite() && auto.shadows.abs() <= 100.0);
        assert!(auto.whites.is_finite() && auto.whites.abs() <= 100.0);
        assert!(auto.blacks.is_finite() && auto.blacks.abs() <= 100.0);
        assert!(auto.vibrance.is_finite() && auto.vibrance.abs() <= 100.0);
        assert!(auto.saturation.is_finite() && auto.saturation.abs() <= 100.0);
        assert!(auto.texture.is_finite() && auto.texture.abs() <= 100.0);
        assert!(auto.clarity.is_finite() && auto.clarity.abs() <= 100.0);
        assert!(auto.dehaze.is_finite() && auto.dehaze.abs() <= 100.0);

        let fstats = by_format.entry(ext).or_default();
        fstats.count += 1;
        fstats.total_decode_us += decode_us;
        fstats.total_tone_us += tone_us;
        fstats.total_wb_us += wb_us;
        fstats.exposures.push(auto.exposure);
        fstats.highlights.push(auto.highlights);
        fstats.shadows.push(auto.shadows);
        fstats.whites.push(auto.whites);
        fstats.blacks.push(auto.blacks);
        fstats.contrasts.push(auto.contrast);
        fstats.vibrances.push(auto.vibrance);
        fstats.wb_temp_deltas.push((auto_temp - info.as_shot_temp).abs());
        fstats.wb_tint_deltas.push((auto_tint - info.as_shot_tint).abs());

        evaluated += 1;
        if let Some(analysis) = lightcraft_pipeline::auto::analyze_scene(&src, &info, &d) {
            let dr = analysis.p99 - analysis.p1;
            fstats.drs.push(dr);
            if analysis.skin_ratio > 0.04 {
                portraits += 1;
                assert_eq!(auto.texture, 0.0, "Portrait photos should protect skin pores");
            }
            if analysis.warm_sky_ratio > 0.08 {
                sunsets += 1;
                assert!(auto.highlights >= -50.0, "Sunset warm clouds highlights should not be crushed");
            }
            if (analysis.dark_channel_mean > 0.05 || (analysis.sky_mean > analysis.p50 && analysis.p75 > 0.0)) && analysis.skin_ratio < 0.03 {
                landscapes += 1;
            }
        }
    }

    println!("\n=== EVALUATION BENCHMARK REPORT ({} PHOTOS) ===", evaluated);
    println!("Scene classification: Portraits={}, Sunsets={}, Landscapes={}", portraits, sunsets, landscapes);

    all_decode_latencies_us.sort_unstable();
    all_tone_latencies_us.sort_unstable();
    all_wb_latencies_us.sort_unstable();

    let p50 = |v: &[u128]| v[v.len() / 2] as f64 / 1000.0;
    let p95 = |v: &[u128]| v[(v.len() as f64 * 0.95) as usize] as f64 / 1000.0;
    let mean = |v: &[u128]| (v.iter().sum::<u128>() as f64 / v.len() as f64) / 1000.0;

    println!("\nCompute Latency Summary (ms):");
    println!(
        "  Thumb Decode:  mean = {:.2} ms, p50 = {:.2} ms, p95 = {:.2} ms",
        mean(&all_decode_latencies_us),
        p50(&all_decode_latencies_us),
        p95(&all_decode_latencies_us)
    );
    println!(
        "  Auto Tone:     mean = {:.2} ms, p50 = {:.2} ms, p95 = {:.2} ms",
        mean(&all_tone_latencies_us),
        p50(&all_tone_latencies_us),
        p95(&all_tone_latencies_us)
    );
    println!(
        "  Auto WB:       mean = {:.2} ms, p50 = {:.2} ms, p95 = {:.2} ms",
        mean(&all_wb_latencies_us),
        p50(&all_wb_latencies_us),
        p95(&all_wb_latencies_us)
    );

    println!("\nSensor / Bayer Matrix Breakdown:");
    for (fmt, st) in &by_format {
        let avg_exp = st.exposures.iter().sum::<f64>() / st.count as f64;
        let avg_hl = st.highlights.iter().sum::<f64>() / st.count as f64;
        let avg_sh = st.shadows.iter().sum::<f64>() / st.count as f64;
        let avg_wh = st.whites.iter().sum::<f64>() / st.count as f64;
        let avg_bl = st.blacks.iter().sum::<f64>() / st.count as f64;
        let avg_con = st.contrasts.iter().sum::<f64>() / st.count as f64;
        let avg_vib = st.vibrances.iter().sum::<f64>() / st.count as f64;
        let avg_dr = if st.drs.is_empty() { 0.0 } else { st.drs.iter().sum::<f64>() / st.drs.len() as f64 };
        let avg_tone_ms = (st.total_tone_us as f64 / st.count as f64) / 1000.0;
        let avg_wb_ms = (st.total_wb_us as f64 / st.count as f64) / 1000.0;
        let avg_temp_d = st.wb_temp_deltas.iter().sum::<f64>() / st.count as f64;

        println!(
            "  [{fmt}] ({:2} files): DR={:.1}EV | Exp={:+.2}EV, Cont={:.1}, HL={:+.1}, SH={:+.1}, Wh={:+.1}, Bl={:+.1}, Vib={:+.1} | WB ΔTemp={:.0}K | Tone={:.2}ms, WB={:.2}ms",
            st.count, avg_dr, avg_exp, avg_con, avg_hl, avg_sh, avg_wh, avg_bl, avg_vib, avg_temp_d, avg_tone_ms, avg_wb_ms
        );
    }
    println!("=================================================\n");

    assert!(evaluated >= 10, "Should successfully evaluate at least 10 raw photos");

    // Test batch selection auto edit command
    let targets: Vec<u64> = report.imported.iter().take(5).copied().collect();
    let cmd = crate::cmd::find_command("develop.auto").expect("develop.auto command");
    let res = (cmd.run)(&mut session, &json!({"ids": targets, "wb": true})).expect("batch develop.auto");
    assert!(res.is_object() || res.is_array());
}
