//! The desktop Pro Library layout (Settings ▸ Appearance ▸ Layout): the Classic layout is left alone,
//! Pro adds the status bar, the dense toolbar, square rounded tiles and marquee selection.

use std::time::Duration;

use lightcraft_catalog::{Op, Photo, PhotoId, Source};
use lightcraft_engine::Session;
use serde_json::json;

use crate::headless::Headless;
use crate::state::{DesktopLayout, ViewMode};
use crate::{LightcraftApp, Services};

const T: Duration = Duration::from_secs(30);
const SETTLE: Duration = Duration::from_secs(120);

fn library(n: u64) -> Session {
    let mut s = Session::new();
    for i in 0..n {
        let path = format!("/lightcraft-pro-test/IMG_{i:05}.jpg");
        let mut p = Photo::new(PhotoId(i + 1), Source::File { path }, &format!("IMG_{i:05}.jpg"), "JPEG", 6000, 4000, "2026-01-01T00:00:00");
        p.captured = Some(format!("2026-03-{:02}T10:00:00", 1 + i / 12));
        s.catalog.apply(Op::AddPhoto { photo: Box::new(p) }).unwrap();
    }
    s
}

fn grid(layout: DesktopLayout) -> Headless {
    let app = LightcraftApp::new(library(40), Services { png: None, ..Default::default() });
    let mut h = Headless::new(app, [1440.0, 900.0], 1.0);
    h.app.ui.settings.desktop_layout = layout;
    h.app.ui.view = ViewMode::PhotoGrid;
    h.app.ui.thumb_size = 150.0;
    h.settle(SETTLE);
    h
}

/// Every tile on screen, top left first.
fn tiles(h: &Headless) -> Vec<egui::Rect> {
    let mut v: Vec<egui::Rect> = h.app.widgets.iter().filter(|(w, _)| w.starts_with("thumb:")).map(|(_, r)| *r).collect();
    v.sort_by(|a, b| (a.top(), a.left()).partial_cmp(&(b.top(), b.left())).unwrap());
    v
}

fn widget(h: &Headless, id: &str) -> Option<egui::Rect> {
    h.app.widgets.iter().find(|(w, _)| w == id).map(|(_, r)| *r)
}

#[test]
fn classic_has_no_pro_chrome() {
    let h = grid(DesktopLayout::Classic);
    for id in ["bar:status", "proCollection", "proViewGrid"] {
        assert!(widget(&h, id).is_none(), "{id} appeared in the Classic layout");
    }
    assert!(widget(&h, "icon:import").is_some(), "Classic keeps its own toolbar");
    let cell = tiles(&h)[0];
    assert!(cell.width() > cell.height() * 1.2, "Classic tiles keep the photo's shape: {cell:?}");
}

#[test]
fn pro_shows_the_status_bar_the_toolbar_and_square_tiles() {
    let mut h = grid(DesktopLayout::Pro);
    let bar = widget(&h, "bar:status").expect("status bar");
    assert!((bar.height() - crate::panels::chrome_pro::STATUS_H).abs() < 1.5, "{bar:?}");
    assert!(widget(&h, "slider:thumbSize").is_some());
    assert!(widget(&h, "proCollection").is_some());
    let cell = tiles(&h)[0];
    assert!((cell.width() - cell.height()).abs() < 0.5, "Pro tiles are square: {cell:?}");
    assert!((cell.width() - 150.0).abs() < 0.5, "and as big as the slider says: {cell:?}");
    // the slider drives the size
    let r = widget(&h, "slider:thumbSize").unwrap();
    let r2 = h.request("ui.clickWidget", json!({"id": "slider:thumbSize", "fx": 1.0, "fy": 0.5}), T);
    assert_eq!(r2["ok"], true, "{r2}");
    h.settle(SETTLE);
    assert!(h.app.ui.thumb_size > 400.0, "{} (slider {r:?})", h.app.ui.thumb_size);
}

#[test]
fn dragging_on_empty_space_selects_with_a_marquee() {
    let mut h = grid(DesktopLayout::Pro);
    let all = tiles(&h);
    let first = all[0];
    // the empty strip right of the first row of tiles (the row does not fill the width)
    let row_end = all.iter().filter(|r| (r.top() - first.top()).abs() < 1.0).map(|r| r.right()).fold(first.right(), f32::max);
    let canvas = h.app.canvas_rect.expect("grid drawn");
    assert!(row_end + 20.0 < canvas.right(), "room right of the tiles: {row_end} in {canvas:?}");
    let (x0, y0) = (row_end + 12.0, first.top() + 20.0);
    let r = h.request("ui.drag", json!({"x": x0, "y": y0, "toX": first.center().x, "toY": first.center().y, "steps": 6}), T);
    assert_eq!(r["ok"], true, "{r}");
    h.settle(SETTLE);
    let n = h.app.session.selection.ids.len();
    assert!(n >= 3, "the marquee took {n} tiles");
}

#[test]
fn small_helpers() {
    use crate::panels::bottombar_pro::{sort_text, thousands};
    assert_eq!(thousands(0), "0");
    assert_eq!(thousands(999), "999");
    assert_eq!(thousands(1248), "1,248");
    assert_eq!(thousands(1_234_567), "1,234,567");
    let s = lightcraft_catalog::Sort { key: lightcraft_catalog::SortKey::CaptureDate, ascending: false, ..Default::default() };
    assert_eq!(sort_text(s), "Sort: Capture date, newest first");
    // a wide photo fills a square tile by cropping its sides
    let uv = crate::panels::grid_pro::cover_uv([300, 100], egui::Rect::from_min_size(egui::Pos2::ZERO, egui::vec2(50.0, 50.0)));
    assert!((uv.width() - 1.0 / 3.0).abs() < 1e-4 && (uv.height() - 1.0).abs() < 1e-4, "{uv:?}");
    assert_eq!(crate::panels::grid_pro::cover_uv([0, 0], egui::Rect::NOTHING), egui::Rect::from_min_max(egui::pos2(0.0, 0.0), egui::pos2(1.0, 1.0)));
}

/// The Library's right panel in Pro stacks the histogram, Quick Develop, Info and Keywords; Classic
/// keeps the Edit panel there.
#[test]
fn pro_right_panel_stacks_quick_develop_info_and_keywords() {
    use crate::state::RightPanel;
    let mut pro = grid(DesktopLayout::Pro);
    pro.app.ui.right = RightPanel::Edit;
    pro.app.session.selection.ids = vec![PhotoId(1)];
    pro.app.session.selection.active = Some(PhotoId(1));
    pro.settle(SETTLE);
    for id in ["section:libQuickDevelop", "section:keywording"] {
        assert!(widget(&pro, id).is_some(), "{id} missing in the Pro Library panel");
    }
    assert!(widget(&pro, "section:pro.basic").is_none(), "the Develop dock is not shown in the Library");

    let mut classic = grid(DesktopLayout::Classic);
    classic.app.ui.right = RightPanel::Edit;
    classic.app.session.selection.ids = vec![PhotoId(1)];
    classic.app.session.selection.active = Some(PhotoId(1));
    classic.settle(SETTLE);
    assert!(widget(&classic, "section:libQuickDevelop").is_none());
    assert!(widget(&classic, "section:keywording").is_none());
}
