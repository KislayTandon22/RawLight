//! Headless tests of the HSL / Color Mixer panel:
//! - HSL mode with subtabs [ All | Hue | Saturation | Luminance ]
//! - Color mode with 8 swatches + All
//! - B&W treatment mix mode with Auto button and all 8 channels
//! - Slider adjustments and TAT tool integration

use serde_json::json;
use std::time::Duration;

use crate::headless::Headless;
use crate::{LightcraftApp, Services};

const T: Duration = Duration::from_secs(20);
const SETTLE: Duration = Duration::from_secs(120);

fn demo() -> Headless {
    let services = Services { png: None, ..Default::default() };
    let app = LightcraftApp::new(lightcraft_engine::Session::with_demo(), services);
    let mut h = Headless::new(app, [1400.0, 2400.0], 1.0);
    let r = h.request("ui.set", json!({"view": "detail", "right": "edit"}), T);
    assert_eq!(r["ok"], true, "{r}");
    if !h.app.ui.section_open("color") {
        h.app.ui.toggle_section("color");
    }
    if !h.app.ui.flyout_open("mixer") {
        h.app.ui.toggle_flyout("mixer");
    }
    h.settle(SETTLE);
    h
}

fn widget(h: &Headless, id: &str) -> Option<egui::Rect> {
    h.app.widgets.iter().find(|(w, _)| w == id).map(|(_, r)| *r)
}

fn click(h: &mut Headless, id: &str) {
    let r = h.request("ui.clickWidget", json!({"id": id}), T);
    assert_eq!(r["ok"], true, "{r}");
    h.step();
    h.step();
}

#[test]
fn hsl_is_the_default_mode_with_all_sliders() {
    let h = demo();
    assert_eq!(h.app.ui.mixer_mode, "hsl");
    assert_eq!(h.app.ui.mixer_hsl_tab, "all");

    // Both mode buttons are present
    assert!(widget(&h, "button:mixerMode-hsl").is_some());
    assert!(widget(&h, "button:mixerMode-color").is_some());

    // All four HSL subtabs are present
    assert!(widget(&h, "button:hslTab-all").is_some());
    assert!(widget(&h, "button:hslTab-hue").is_some());
    assert!(widget(&h, "button:hslTab-sat").is_some());
    assert!(widget(&h, "button:hslTab-lum").is_some());

    // In "all" mode, hue, sat, and lum sliders exist for bands
    for band in ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"] {
        assert!(widget(&h, &format!("slider:mixer.{band}.hue")).is_some(), "missing hue slider for {band}");
        assert!(widget(&h, &format!("slider:mixer.{band}.sat")).is_some(), "missing sat slider for {band}");
        assert!(widget(&h, &format!("slider:mixer.{band}.lum")).is_some(), "missing lum slider for {band}");
    }
}

#[test]
fn hsl_subtabs_filter_sliders_correctly() {
    let mut h = demo();

    // Click Hue subtab
    click(&mut h, "button:hslTab-hue");
    assert_eq!(h.app.ui.mixer_hsl_tab, "hue");
    for band in ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"] {
        assert!(widget(&h, &format!("slider:mixer.{band}.hue")).is_some(), "hue slider should exist for {band}");
        assert!(widget(&h, &format!("slider:mixer.{band}.sat")).is_none(), "sat slider should NOT exist in hue tab");
        assert!(widget(&h, &format!("slider:mixer.{band}.lum")).is_none(), "lum slider should NOT exist in hue tab");
    }

    // Click Saturation subtab
    click(&mut h, "button:hslTab-sat");
    assert_eq!(h.app.ui.mixer_hsl_tab, "sat");
    for band in ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"] {
        assert!(widget(&h, &format!("slider:mixer.{band}.sat")).is_some(), "sat slider should exist for {band}");
        assert!(widget(&h, &format!("slider:mixer.{band}.hue")).is_none(), "hue slider should NOT exist in sat tab");
        assert!(widget(&h, &format!("slider:mixer.{band}.lum")).is_none(), "lum slider should NOT exist in sat tab");
    }

    // Click Luminance subtab
    click(&mut h, "button:hslTab-lum");
    assert_eq!(h.app.ui.mixer_hsl_tab, "lum");
    for band in ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"] {
        assert!(widget(&h, &format!("slider:mixer.{band}.lum")).is_some(), "lum slider should exist for {band}");
        assert!(widget(&h, &format!("slider:mixer.{band}.hue")).is_none(), "hue slider should NOT exist in lum tab");
        assert!(widget(&h, &format!("slider:mixer.{band}.sat")).is_none(), "sat slider should NOT exist in lum tab");
    }
}

#[test]
fn color_mode_swatches_and_band_selection() {
    let mut h = demo();

    // Switch to Color mode
    click(&mut h, "button:mixerMode-color");
    assert_eq!(h.app.ui.mixer_mode, "color");

    // Check that swatches are present
    for band in ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"] {
        assert!(widget(&h, &format!("mixerBand:{band}")).is_some(), "missing swatch for {band}");
    }
    assert!(widget(&h, "button:mixerBand-all").is_some());

    // By default red band is selected
    assert!(widget(&h, "slider:mixer.red.hue").is_some());
    assert!(widget(&h, "slider:mixer.red.sat").is_some());
    assert!(widget(&h, "slider:mixer.red.lum").is_some());
    assert!(widget(&h, "slider:mixer.blue.hue").is_none());

    // Click blue swatch
    click(&mut h, "mixerBand:blue");
    assert_eq!(h.app.ui.mixer_band, "blue");
    assert!(widget(&h, "slider:mixer.blue.hue").is_some());
    assert!(widget(&h, "slider:mixer.blue.sat").is_some());
    assert!(widget(&h, "slider:mixer.blue.lum").is_some());
    assert!(widget(&h, "slider:mixer.red.hue").is_none());
}

#[test]
fn bw_mode_displays_bw_mix_and_auto_button() {
    let mut h = demo();

    // Click B&W treatment toggle button
    click(&mut h, "button:bw");
    h.settle(SETTLE);

    // In B&W mode, auto button and bw sliders exist
    assert!(widget(&h, "button:bwAuto").is_some(), "missing Auto B&W Mix button");
    for band in ["red", "orange", "yellow", "green", "aqua", "blue", "purple", "magenta"] {
        assert!(widget(&h, &format!("slider:bw.{band}")).is_some(), "missing bw slider for {band}");
    }
}
