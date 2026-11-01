//! The Pro desktop dialogs: command palette, shortcut overlay, menu bar additions, and that the
//! Classic layout is untouched.

use std::time::Duration;

use serde_json::json;

use crate::headless::Headless;
use crate::state::{DesktopLayout, Dialog, ViewMode};
use crate::{LightcraftApp, Services};

const T: Duration = Duration::from_secs(20);

fn demo(pro: bool) -> Headless {
    let mut h = Headless::new(LightcraftApp::new(lightcraft_engine::Session::with_demo(), Services::default()), [1440.0, 900.0], 1.0);
    h.app.ui.settings.desktop_layout = if pro { DesktopLayout::Pro } else { DesktopLayout::Classic };
    h.settle(T);
    h.step();
    h
}

fn run(h: &mut Headless, command: &str) {
    let r = h.request("engine.execute", json!({"command": command, "params": {}}), T);
    assert_eq!(r["ok"], true, "{command}: {r}");
    h.settle(T);
    h.step();
}

#[test]
fn palette_lists_every_command_by_label_and_runs_one() {
    let mut h = demo(true);
    run(&mut h, "app.palette");
    let st = h.app.ui.palette.clone().expect("the palette opens in Pro");
    // everything bindable is there, by label
    let entries = crate::palette::entries(&h.app);
    for b in crate::shortcuts::bindable() {
        assert!(entries.iter().any(|e| e.id == b.id), "{} is missing from the palette", b.id);
    }
    assert!(entries.iter().any(|e| e.id == "settings:shortcuts"));
    assert!(st.query.is_empty());
    // fuzzy filter finds Square Grid with a few letters and running it changes the view
    h.app.ui.view = ViewMode::Detail;
    let hits = crate::palette::search(&entries, "sqgrid");
    let top = hits.first().map(|h| entries[h.0].clone()).expect("a match for sqgrid");
    assert_eq!(top.id, "view.squareGrid", "{top:?}");
    crate::palette::run(&mut h.app, &egui::Context::default(), &top).expect("runs");
    assert_eq!(h.app.ui.view, ViewMode::SquareGrid);
}

#[test]
fn palette_runs_the_selected_entry_on_enter_and_closes_on_escape() {
    let mut h = demo(true);
    run(&mut h, "app.palette");
    for c in "square".chars() {
        let r = h.request("ui.text", json!({"text": c.to_string()}), T);
        assert_eq!(r["ok"], true, "{r}");
    }
    h.settle(T);
    h.step();
    h.app.ui.view = ViewMode::Detail;
    let r = h.request("ui.key", json!({"key": "Enter"}), T);
    assert_eq!(r["ok"], true, "{r}");
    h.settle(T);
    h.step();
    assert!(h.app.ui.palette.is_none(), "Enter closes the palette");
    assert_eq!(h.app.ui.view, ViewMode::SquareGrid, "and runs the first match");
    run(&mut h, "app.palette");
    assert!(h.app.ui.palette.is_some());
    let r = h.request("ui.key", json!({"key": "Escape"}), T);
    assert_eq!(r["ok"], true);
    h.step();
    assert!(h.app.ui.palette.is_none());
}

#[test]
fn classic_has_no_palette_overlay_or_extra_menu_items() {
    let mut h = demo(false);
    run(&mut h, "app.palette");
    assert!(h.app.ui.palette.is_none(), "the Classic layout has no palette");
    run(&mut h, "app.shortcutOverlay");
    assert!(!h.app.ui.shortcut_overlay);
    let bar = crate::menubar::menu_bar(&h.app);
    let text = serde_json::to_string(&bar).expect("menu json");
    assert!(!text.contains("Command Palette"), "Classic menus are unchanged");
    assert!(!text.contains("Shortcuts Editor"));
    assert!(text.contains("Rename Photos"));
}

#[test]
fn pro_menus_gain_the_palette_shortcuts_editor_and_batch_rename() {
    let h = demo(true);
    let text = serde_json::to_string(&crate::menubar::menu_bar(&h.app)).expect("menu json");
    assert!(text.contains("Command Palette"));
    assert!(text.contains("Shortcuts Editor"));
    assert!(text.contains("Batch Rename"));
    assert!(!text.contains("Rename Photos"));
}

#[test]
fn the_palette_shortcut_takes_no_existing_binding() {
    let taken: Vec<&str> =
        crate::shortcuts::bindable().iter().filter(|b| b.id != "app.palette" && b.default == Some(crate::palette::SHORTCUT)).map(|b| b.id).collect();
    assert!(taken.is_empty(), "{} is shared with {taken:?}", crate::palette::SHORTCUT);
}

#[test]
fn question_mark_toggles_the_overlay_and_escape_closes_it() {
    let mut h = demo(true);
    h.request("ui.text", json!({"text": "?"}), T);
    h.step();
    assert!(h.app.ui.shortcut_overlay, "? opens the overlay");
    let groups = crate::palette::overlay_groups(&h.app, false);
    assert!(groups.iter().any(|(g, rows)| g == "File" && rows.iter().any(|(l, _)| l.contains("Import"))));
    h.request("ui.key", json!({"key": "Escape"}), T);
    h.step();
    assert!(!h.app.ui.shortcut_overlay);
}

#[test]
fn pro_export_dialog_opens_with_its_two_panes_title_and_default_button() {
    let mut h = demo(true);
    run(&mut h, "library.selectAll");
    run(&mut h, "dialog.export");
    assert!(matches!(h.app.ui.dialog, Some(Dialog::Export { .. })));
    for _ in 0..3 {
        h.step();
    }
    let ids: Vec<String> = h.app.widgets.iter().map(|(id, _)| id.clone()).collect();
    assert!(ids.iter().any(|i| i == "section:exportFile"), "collapsible sections: {ids:?}");
    assert!(ids.iter().any(|i| i == "button:exportWmSaveCurrent"), "saved watermarks pane");
}

#[test]
fn pro_settings_has_the_navigation_and_a_shortcuts_page() {
    let mut h = demo(true);
    let r = h.request("engine.execute", json!({"command": "app.settings", "params": {"tab": "shortcuts"}}), T);
    assert_eq!(r["ok"], true, "{r}");
    h.settle(T);
    for _ in 0..3 {
        h.step();
    }
    let ids: Vec<String> = h.app.widgets.iter().map(|(id, _)| id.clone()).collect();
    assert!(ids.iter().any(|i| i == "button:settingsTab-shortcuts"), "{ids:?}");
    assert!(ids.iter().any(|i| i == "field:shortcutsSearch"), "the keymap editor is the Shortcuts page");
    // Classic refuses the Pro-only page
    let mut c = demo(false);
    let r = c.request("engine.execute", json!({"command": "app.settings", "params": {"tab": "shortcuts"}}), T);
    assert_eq!(r["ok"], false, "{r}");
}
