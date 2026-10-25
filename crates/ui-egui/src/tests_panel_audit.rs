//! Apple Publisher Guidelines & HIG Audit Tests
//! Verifies Apple close buttons on all dialogs and panels, minimum 44pt touch targets,
//! and panel lifecycle on iPad touch UI.

use crate::headless::Headless;
use crate::state::RightPanel;
use crate::{LightcraftApp, Services};
use serde_json::json;
use std::time::Duration;

const T: Duration = Duration::from_secs(5);

fn ipad_app() -> Headless {
    let png = |img: &lightcraft_raster::Rgba8| {
        lightcraft_codecs::encode_png(&lightcraft_codecs::EncodeImage::rgba8(img), &lightcraft_codecs::EncodeMeta::default()).unwrap_or_default()
    };
    let services = Services {
        png: Some(Box::new(png)),
        write: Some(Box::new(|p: &str, b: &[u8]| std::fs::write(p, b).map_err(|e| e.to_string()))),
        ..Default::default()
    };
    let mut app = LightcraftApp::new(lightcraft_engine::Session::with_demo(), services);
    app.native_menu = false;
    let mut h = Headless::new(app, [1180.0, 820.0], 2.0); // iPad Air 11-inch point bounds
    crate::theme::set_touch_ui(&h.view.ctx, true);
    h.settle(Duration::from_secs(10));
    h
}

fn has_widget(h: &Headless, id: &str) -> bool {
    h.app.widgets.iter().any(|(w, _)| w == id)
}

fn widget_rect(h: &Headless, id: &str) -> egui::Rect {
    h.app
        .widgets
        .iter()
        .find(|(w, _)| w == id)
        .map(|(_, r)| *r)
        .unwrap_or_else(|| panic!("Widget `{id}` not found on screen. Available: {:?}", h.app.widgets.iter().map(|(w, _)| w).collect::<Vec<_>>()))
}

#[test]
fn test_apple_close_button_on_all_dialogs() {
    let mut h = ipad_app();

    // 1. Welcome dialog
    h.app.ui.dialog = Some(crate::state::Dialog::Welcome);
    h.settle(Duration::from_secs(2));
    assert!(has_widget(&h, "button:dialogClose"), "Welcome dialog must have Apple close button");
    let close_rect = widget_rect(&h, "button:dialogClose");
    assert!(close_rect.height() >= 44.0 && close_rect.width() >= 44.0, "Close button hit area must meet 44x44 Apple HIG: {close_rect:?}");
    let r = h.request("ui.clickWidget", json!({"id": "button:dialogClose"}), T);
    assert_eq!(r["ok"], true);
    assert!(h.app.ui.dialog.is_none(), "Clicking Apple close button dismisses Welcome dialog");

    // 2. Export dialog
    h.app.run("dialog.export", json!({})).unwrap();
    h.settle(Duration::from_secs(2));
    assert!(has_widget(&h, "button:dialogClose"), "Export dialog must have Apple close button");
    assert!(has_widget(&h, "button:dialogCancel"), "Export dialog must have Cancel button");
    assert!(has_widget(&h, "button:dialogOk"), "Export dialog must have OK/Export button");
    let ok_rect = widget_rect(&h, "button:dialogOk");
    let cancel_rect = widget_rect(&h, "button:dialogCancel");
    assert!(ok_rect.height() >= 40.0, "Export OK button touch height: {ok_rect:?}");
    assert!(cancel_rect.height() >= 40.0, "Export Cancel button touch height: {cancel_rect:?}");
    let r = h.request("ui.clickWidget", json!({"id": "button:dialogClose"}), T);
    assert_eq!(r["ok"], true);
    assert!(h.app.ui.dialog.is_none(), "Clicking Apple close button dismisses Export dialog");

    // 3. Settings dialog
    h.app.run("app.settings", json!({})).unwrap();
    h.settle(Duration::from_secs(2));
    assert!(has_widget(&h, "button:dialogClose"), "Settings dialog must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:dialogClose"}), T);
    assert_eq!(r["ok"], true);
    assert!(h.app.ui.dialog.is_none(), "Clicking Apple close button dismisses Settings dialog");

    // 4. About dialog
    h.app.ui.dialog = Some(crate::state::Dialog::About);
    h.settle(Duration::from_secs(2));
    assert!(has_widget(&h, "button:dialogClose"), "About dialog must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:dialogClose"}), T);
    assert_eq!(r["ok"], true);
    assert!(h.app.ui.dialog.is_none(), "Clicking Apple close button dismisses About dialog");

    // 5. New Album dialog
    h.app.ui.dialog = Some(crate::state::Dialog::NewAlbum { name: "Audit".into(), folder: false, parent: None, include_selected: true });
    h.settle(Duration::from_secs(2));
    assert!(has_widget(&h, "button:dialogClose"), "New Album dialog must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:dialogClose"}), T);
    assert_eq!(r["ok"], true);
    assert!(h.app.ui.dialog.is_none(), "Clicking Apple close button dismisses New Album dialog");
}

#[test]
fn test_apple_close_button_on_sidebars_and_panels() {
    let mut h = ipad_app();

    // 1. Left Panel in Library Mode
    h.app.ui.left_panel = true;
    h.step();
    assert!(has_widget(&h, "button:leftPanelClose"), "Left panel header must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:leftPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert!(!h.app.ui.left_panel, "Tapping left panel close button collapses left panel");

    // 2. Right Panel: QuickDevelop
    h.app.ui.right = RightPanel::QuickDevelop;
    h.step();
    assert!(has_widget(&h, "button:rightPanelClose"), "QuickDevelop panel must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:rightPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert_eq!(h.app.ui.right, RightPanel::None, "Tapping close button closes QuickDevelop");

    // 3. Right Panel: Edit
    h.app.ui.right = RightPanel::Edit;
    h.step();
    assert!(has_widget(&h, "button:rightPanelClose"), "Edit panel must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:rightPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert_eq!(h.app.ui.right, RightPanel::None, "Tapping close button closes Edit");

    // 4. Right Panel: Crop
    h.app.ui.right = RightPanel::Crop;
    h.step();
    assert!(has_widget(&h, "button:rightPanelClose"), "Crop panel must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:rightPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert_eq!(h.app.ui.right, RightPanel::None, "Tapping close button closes Crop");

    // 5. Right Panel: Masking
    h.app.ui.right = RightPanel::Masking;
    h.step();
    assert!(has_widget(&h, "button:rightPanelClose"), "Masking panel must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:rightPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert_eq!(h.app.ui.right, RightPanel::None, "Tapping close button closes Masking");

    // 6. Right Panel: Info
    h.app.ui.right = RightPanel::Info;
    h.step();
    assert!(has_widget(&h, "button:rightPanelClose"), "Info panel must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:rightPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert_eq!(h.app.ui.right, RightPanel::None, "Tapping close button closes Info");

    // 7. Right Panel: Keywords
    h.app.ui.right = RightPanel::Keywords;
    h.step();
    assert!(has_widget(&h, "button:rightPanelClose"), "Keywords panel must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:rightPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert_eq!(h.app.ui.right, RightPanel::None, "Tapping close button closes Keywords");

    // 8. Right Panel: Versions
    h.app.ui.right = RightPanel::Versions;
    h.step();
    assert!(has_widget(&h, "button:rightPanelClose"), "Versions panel must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:rightPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert_eq!(h.app.ui.right, RightPanel::None, "Tapping close button closes Versions");

    // 9. Right Panel: Activity
    h.app.ui.right = RightPanel::Activity;
    h.step();
    assert!(has_widget(&h, "button:rightPanelClose"), "Activity panel must have Apple close button");
    let r = h.request("ui.clickWidget", json!({"id": "button:rightPanelClose"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert_eq!(h.app.ui.right, RightPanel::None, "Tapping close button closes Activity");
}

#[test]
fn test_capture_and_validate_all_panels() {
    use lightcraft_catalog::PhotoId;

    let shot_dir_buf =
        std::env::var_os("LIGHTCRAFT_SHOT_DIR").map_or_else(|| std::env::temp_dir().join("lightcraft-panel-audit"), std::path::PathBuf::from);
    let shot_dir = shot_dir_buf.as_path();
    std::fs::create_dir_all(shot_dir).unwrap();

    let take_shot = |h: &mut Headless, name: &str| {
        let p = shot_dir.join(format!("{name}.png"));
        let r = h.request("ui.screenshot", json!({"path": p.to_string_lossy(), "headless": true}), T);
        assert_eq!(r["ok"], true, "Screenshot failed for {name}: {r:?}");
        assert!(p.exists(), "Screenshot file was created: {:?}", p);
        println!("Saved screenshot: {name}.png");
    };

    let mut h = ipad_app();

    // -------------------------------------------------------------
    // 1. Library Grid View with Multi-Selection & Batch Export
    // -------------------------------------------------------------
    h.app.ui.view = crate::state::ViewMode::PhotoGrid;
    h.app.ui.left_panel = false;
    h.app.ui.right = RightPanel::None;
    h.app.session.selection.active = Some(PhotoId(1));
    h.app.session.selection.ids = vec![PhotoId(1), PhotoId(2), PhotoId(3)];
    h.settle(Duration::from_millis(500));
    take_shot(&mut h, "01_library_grid_multiselect");

    // -------------------------------------------------------------
    // 2. Detail View with Edit / Develop Panel
    // -------------------------------------------------------------
    h.app.ui.view = crate::state::ViewMode::Detail;
    h.app.ui.right = RightPanel::Edit;
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:rightPanelClose"), "Edit panel close button must exist");
    let close_rect = widget_rect(&h, "button:rightPanelClose");
    assert!(close_rect.width() >= 32.0 && close_rect.height() >= 32.0, "Close button size >= 32pt");
    take_shot(&mut h, "02_detail_develop_panel");

    // -------------------------------------------------------------
    // 3. Detail View with Masking Panel & Local Controls
    // -------------------------------------------------------------
    h.app.ui.right = RightPanel::Masking;
    let _ = h.app.session.execute(
        "mask.add",
        &json!({
            "kind": "linear",
            "name": "Sky Gradient",
            "start": [0.5, 0.1],
            "end": [0.5, 0.4]
        }),
    );
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:rightPanelClose"), "Masking panel close button must exist");
    take_shot(&mut h, "03_detail_masking_panel");

    // -------------------------------------------------------------
    // 4. Detail View with Spot Removal Tool
    // -------------------------------------------------------------
    h.app.ui.right = RightPanel::Remove;
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:rightPanelClose"), "Remove panel close button must exist");
    take_shot(&mut h, "04_detail_remove_tool");

    // -------------------------------------------------------------
    // 5. Detail View with Crop & Straighten Tool
    // -------------------------------------------------------------
    h.app.ui.right = RightPanel::Crop;
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:rightPanelClose"), "Crop panel close button must exist");
    take_shot(&mut h, "05_detail_crop_straighten");

    // -------------------------------------------------------------
    // 6. Detail View with Info / Metadata Panel
    // -------------------------------------------------------------
    h.app.ui.right = RightPanel::Info;
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:rightPanelClose"), "Info panel close button must exist");
    take_shot(&mut h, "06_detail_info_metadata");

    // -------------------------------------------------------------
    // 7. Detail View with Quick Develop Panel
    // -------------------------------------------------------------
    h.app.ui.right = RightPanel::QuickDevelop;
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:rightPanelClose"), "QuickDevelop panel close button must exist");
    take_shot(&mut h, "07_detail_quick_develop");

    // -------------------------------------------------------------
    // 8. Detail View with Presets & History Sidebar (Left Develop)
    // -------------------------------------------------------------
    h.app.ui.right = RightPanel::None;
    h.app.ui.left_panel = true;
    h.app.ui.develop_left_mode = crate::state::DevelopLeftMode::Develop;
    h.settle(Duration::from_millis(500));
    take_shot(&mut h, "08_detail_presets_sidebar");

    // -------------------------------------------------------------
    // 9. Batch Export Modal Dialog (Liquid Glass + Circular Close)
    // -------------------------------------------------------------
    h.app.ui.left_panel = false;
    h.app.run("dialog.export", json!({})).unwrap();
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:dialogClose"), "Export dialog close button must exist");
    assert!(has_widget(&h, "button:dialogOk"), "Export dialog OK button must exist");
    assert!(has_widget(&h, "button:dialogCancel"), "Export dialog Cancel button must exist");
    take_shot(&mut h, "09_modal_batch_export");
    let _ = h.request("ui.clickWidget", json!({"id": "button:dialogClose"}), T);
    h.settle(Duration::from_millis(200));

    // -------------------------------------------------------------
    // 10. Settings / Preferences Modal Dialog
    // -------------------------------------------------------------
    h.app.run("app.settings", json!({})).unwrap();
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:dialogClose"), "Settings dialog close button must exist");
    take_shot(&mut h, "10_modal_settings_preferences");
    let _ = h.request("ui.clickWidget", json!({"id": "button:dialogClose"}), T);
    h.settle(Duration::from_millis(200));

    // -------------------------------------------------------------
    // 11. Welcome Modal Dialog
    // -------------------------------------------------------------
    h.app.ui.dialog = Some(crate::state::Dialog::Welcome);
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:dialogClose"), "Welcome dialog close button must exist");
    take_shot(&mut h, "11_modal_welcome");
    let _ = h.request("ui.clickWidget", json!({"id": "button:dialogClose"}), T);
    h.settle(Duration::from_millis(200));

    // -------------------------------------------------------------
    // 12. Library Left Sidebar (Albums, Smart Collections, Folders)
    // -------------------------------------------------------------
    h.app.ui.left_panel = true;
    h.app.ui.view = crate::state::ViewMode::PhotoGrid;
    h.settle(Duration::from_millis(500));
    assert!(has_widget(&h, "button:leftPanelClose"), "Left panel close button must exist");
    take_shot(&mut h, "12_left_sidebar_library");
}
