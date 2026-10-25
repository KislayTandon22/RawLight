//! Headless tests of the Develop Left Sidebar:
//! - Dual-mode switcher [ Develop | Library ]
//! - Navigator section with FIT and 1:1 zoom controls and loupe pan thumbnail
//! - Presets section with category browser and hover preview
//! - Snapshots section with create, restore, rename, update, and delete
//! - History section with step navigation and clear

use serde_json::json;
use std::time::Duration;

use crate::headless::Headless;
use crate::state::{DevelopLeftMode, Zoom};
use crate::{LightcraftApp, Services};

const T: Duration = Duration::from_secs(20);
const SETTLE: Duration = Duration::from_secs(120);

fn demo() -> Headless {
    let services = Services { png: None, ..Default::default() };
    let app = LightcraftApp::new(lightcraft_engine::Session::with_demo(), services);
    let mut h = Headless::new(app, [1400.0, 2400.0], 1.0);
    let r = h.request("ui.set", json!({"view": "detail", "right": "edit", "leftPanel": true}), T);
    assert_eq!(r["ok"], true, "{r}");
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
fn develop_left_sidebar_renders_sections() {
    let h = demo();
    assert_eq!(h.app.ui.develop_left_mode, DevelopLeftMode::Develop);

    assert!(widget(&h, "developSection:navigator").is_some(), "Navigator section header must exist");
    assert!(widget(&h, "developSection:presets").is_some(), "Presets section header must exist");
    assert!(widget(&h, "developSection:snapshots").is_some(), "Snapshots section header must exist");
    assert!(widget(&h, "developSection:history").is_some(), "History section header must exist");
}

#[test]
fn mode_switcher_toggles_between_develop_and_library() {
    let mut h = demo();
    assert_eq!(h.app.ui.develop_left_mode, DevelopLeftMode::Develop);

    assert!(widget(&h, "button:developLeftMode-library").is_some(), "Library mode button exists");
    assert!(widget(&h, "button:developLeftMode-develop").is_some(), "Develop mode button exists");

    // Switch to Library
    click(&mut h, "button:developLeftMode-library");
    assert_eq!(h.app.ui.develop_left_mode, DevelopLeftMode::Library);

    // Switch back to Develop
    click(&mut h, "button:developLeftMode-develop");
    assert_eq!(h.app.ui.develop_left_mode, DevelopLeftMode::Develop);
}

#[test]
fn navigator_zoom_buttons_work() {
    let mut h = demo();
    assert_eq!(h.app.ui.zoom, Zoom::Fit);

    assert!(widget(&h, "button:navigatorZoom100").is_some(), "1:1 zoom button exists");
    assert!(widget(&h, "button:navigatorZoomFit").is_some(), "FIT zoom button exists");

    click(&mut h, "button:navigatorZoom100");
    assert_eq!(h.app.ui.zoom, Zoom::Percent(100.0));

    click(&mut h, "button:navigatorZoomFit");
    assert_eq!(h.app.ui.zoom, Zoom::Fit);
}

#[test]
fn snapshots_crud_and_restore() {
    let mut h = demo();
    let id = h.app.session.active().expect("active photo");

    // 1. Create Snapshot
    let r = h.app.run("version.create", json!({"name": "My Snapshot"}));
    assert!(r.is_ok(), "version.create should succeed: {r:?}");
    h.step();
    h.step();

    let p = h.app.session.catalog.photo(id).unwrap().clone();
    assert_eq!(p.versions.len(), 1);
    assert_eq!(p.versions[0].name, "My Snapshot");
    assert!(widget(&h, "snapshot:0").is_some(), "snapshot:0 row must render");

    // 2. Modify settings then restore
    let _ = h.app.run("develop.set", json!({"control": "light.exposure", "value": 1.5}));
    h.step();
    let p_edited = h.app.session.catalog.photo(id).unwrap();
    assert_ne!(p_edited.develop.light.exposure, p.versions[0].settings.light.exposure);

    let r_restore = h.app.run("version.restore", json!({"index": 0}));
    assert!(r_restore.is_ok(), "version.restore should succeed");
    h.step();
    let p_restored = h.app.session.catalog.photo(id).unwrap();
    assert_eq!(p_restored.develop.light.exposure, p.versions[0].settings.light.exposure);

    // 3. Delete Snapshot
    let r_del = h.app.run("version.delete", json!({"index": 0}));
    assert!(r_del.is_ok(), "version.delete should succeed");
    h.step();
    let p_after = h.app.session.catalog.photo(id).unwrap();
    assert_eq!(p_after.versions.len(), 0);
}

#[test]
fn history_steps_and_restore() {
    let mut h = demo();
    let id = h.app.session.active().expect("active photo");

    // Perform an edit to create a history step
    let _ = h.app.run("develop.set", json!({"control": "light.exposure", "value": 0.8}));
    h.step();
    h.step();

    let p = h.app.session.catalog.photo(id).unwrap().clone();
    assert!(!p.history.is_empty(), "history should have entries");
    assert!(widget(&h, "history:0").is_some(), "history step 0 should render");

    // Restore to step 0
    let r = h.app.run("history.restore", json!({"index": 0}));
    assert!(r.is_ok(), "history.restore should succeed");
}

#[test]
fn accordion_sections_collapse_and_expand() {
    let mut h = demo();
    assert!(h.app.ui.develop_navigator_open);
    assert!(h.app.ui.develop_presets_open);
    assert!(h.app.ui.develop_snapshots_open);
    assert!(h.app.ui.develop_history_open);

    click(&mut h, "developSection:navigator");
    assert!(!h.app.ui.develop_navigator_open);

    click(&mut h, "developSection:presets");
    assert!(!h.app.ui.develop_presets_open);

    click(&mut h, "developSection:snapshots");
    assert!(!h.app.ui.develop_snapshots_open);

    click(&mut h, "developSection:history");
    assert!(!h.app.ui.develop_history_open);
}
