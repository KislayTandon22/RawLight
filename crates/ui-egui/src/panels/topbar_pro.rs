//! The desktop "Pro" toolbar (Library): collection title, search, sort and filter, module switcher,
//! view modes and Import, in one dense 44 pt row. Reached from `topbar::show` only when
//! [`crate::theme::desktop_pro`] is on; the Classic bar is untouched.

use egui::{Align2, Color32, Rect, Stroke, StrokeKind, pos2, vec2};
use serde_json::json;

use super::chrome_pro::{self as pro, TOOLBAR_H};
use crate::LightcraftApp;
use crate::icons::{Icon, paint};
use crate::state::{RightPanel, ViewMode};
use crate::theme::Tokens;
use crate::widgets::register;

/// The module switcher's segments: label, icon, the command that opens it.
const MODULES: &[(&str, Icon, &str)] = &[
    ("Library", Icon::GridPhoto, "view.photoGrid"),
    ("Edit", Icon::Sliders, "panel.edit"),
    ("Crop", Icon::Crop, "panel.crop"),
    ("Heal", Icon::Eraser, "panel.remove"),
    ("Mask", Icon::Mask, "panel.masking"),
    ("History", Icon::Activity, "panel.activity"),
];

/// The view-mode group: id, icon, mode, command, tooltip.
const VIEWS: &[(&str, Icon, ViewMode, &str, &str)] = &[
    ("proViewGrid", Icon::GridPhoto, ViewMode::PhotoGrid, "view.photoGrid", "Grid (G)"),
    ("proViewLoupe", Icon::Single, ViewMode::Detail, "view.detail", "Loupe (D)"),
    ("proViewSurvey", Icon::Survey, ViewMode::Survey, "view.survey", "Survey (N)"),
    ("proViewCompare", Icon::Compare, ViewMode::Compare, "view.compare", "Compare (Shift+C)"),
];

/// Which module segment is lit for the current view and right panel.
pub fn current_module(view: ViewMode, panel: RightPanel) -> usize {
    match panel {
        RightPanel::Edit | RightPanel::Profiles | RightPanel::QuickDevelop if view == ViewMode::Detail => 1,
        RightPanel::Crop => 2,
        RightPanel::Remove | RightPanel::RedEye => 3,
        RightPanel::Masking => 4,
        RightPanel::Activity => 5,
        _ => 0,
    }
}

/// The sort key's short name for the toolbar button.
fn sort_label(key: lightcraft_catalog::SortKey) -> &'static str {
    use lightcraft_catalog::SortKey::*;
    match key {
        CaptureDate => "Capture date",
        ImportDate => "Added",
        EditDate => "Modified",
        FileName => "File name",
        Rating => "Rating",
        FileSize => "File size",
        Random => "Random",
    }
}

pub fn show(app: &mut LightcraftApp, ui: &mut egui::Ui) {
    let t = Tokens::get(ui.ctx());
    let left = match (app.integrated_titlebar, app.window_is_fullscreen) {
        (true, false) => 78,
        (true, true) => 16,
        (false, _) => 10,
    };
    egui::Panel::top("top_bar")
        .exact_size(TOOLBAR_H)
        .frame(egui::Frame::NONE.fill(t.chrome).inner_margin(egui::Margin { left, right: 12, top: 0, bottom: 0 }))
        .show(ui, |ui| {
            let full = ui.max_rect();
            let bar = Rect::from_min_max(pos2(full.left() - left as f32, full.top()), pos2(full.right() + 12.0, full.bottom()));
            ui.painter().hline(bar.x_range(), bar.bottom() - 0.5, Stroke::new(1.0, t.divider));
            register(ui, "region:titlebar", bar);
            if app.integrated_titlebar {
                let resp = craft_window::title_bar::empty_area(ui, bar);
                crate::widgets::announce(&resp, crate::i18n::tr("Title bar"));
            }
            let cy = full.center().y;
            let mut x = full.left();

            // ---- left: sidebar toggle, (menus), collection title
            let r = pro::slot(x, cy, 28.0, 28.0);
            let resp = pro::hit(ui, "icon:sidebar", r, "Show/hide My Photos panel");
            pro::wash(ui, r, &resp, app.ui.left_panel, 6.0);
            paint(ui.painter(), r.shrink(7.0), Icon::Sidebar, if app.ui.left_panel { pro::accent_text(&t) } else { t.icon });
            if resp.clicked() {
                let _ = app.run("view.leftPanel", json!({}));
            }
            x = r.right() + 8.0;
            if !app.native_menu {
                let w = crate::menubar::bar_width(ui) + 16.0;
                let mut menus = ui.new_child(
                    egui::UiBuilder::new()
                        .max_rect(Rect::from_min_max(pos2(x, full.top()), pos2(x + w, full.bottom())))
                        .layout(egui::Layout::left_to_right(egui::Align::Center)),
                );
                crate::menubar::show_in_window(app, &mut menus, w);
                x += w + 8.0;
            }
            let title = crate::i18n::source_title(&app.session);
            let total = app.session.source_total().unwrap_or_else(|| app.session.visible_shared().1.len());
            let tf = t.semibold(14.0);
            let title_w = pro::text_w(ui, &title, tf.clone()).min(200.0);
            let count = format!("{total}");
            let count_w = pro::text_w(ui, &count, t.font(12.0));
            let tr_ = pro::slot(x, cy, title_w + count_w + 40.0, 28.0);
            let resp = pro::hit(ui, "proCollection", tr_, "Choose a collection");
            pro::wash(ui, tr_, &resp, false, 6.0);
            let p = ui.painter().with_clip_rect(tr_);
            p.text(pos2(tr_.left() + 8.0, cy), Align2::LEFT_CENTER, &title, tf, t.text);
            paint(ui.painter(), Rect::from_center_size(pos2(tr_.left() + 8.0 + title_w + 10.0, cy), vec2(12.0, 12.0)), Icon::ChevronDown, t.text_dim);
            p.text(pos2(tr_.right() - 8.0, cy), Align2::RIGHT_CENTER, &count, t.font(12.0), t.text_dim);
            egui::Popup::menu(&resp).show(|ui| {
                for (label, kind) in [("All Photos", "all"), ("Recently Added", "recentlyAdded"), ("Picks", "picks")] {
                    if ui.button(crate::i18n::tr(label)).clicked() {
                        let _ = app.run("library.source", json!({"kind": kind}));
                    }
                }
            });
            x = tr_.right() + 10.0;

            // ---- right: Import, view modes
            let mut rx = full.right();
            let label = crate::i18n::tr("Import");
            let iw = pro::text_w(ui, label, t.semibold(12.5)) + 40.0;
            let ir = pro::slot(rx - iw, cy, iw, 28.0);
            let mac = ui.ctx().os() == egui::os::OperatingSystem::Mac;
            let tip = match crate::shortcuts::shortcut_of(&app.ui.settings.keymap, "file.addPhotos") {
                Some(sc) => format!("{} ({})", crate::i18n::tr("Import Photos…"), crate::menubar::shortcut_text(sc, mac)),
                None => crate::i18n::tr("Import Photos…").to_string(),
            };
            let resp = pro::hit(ui, "icon:import", ir, &tip);
            let fill = if resp.is_pointer_button_down_on() {
                t.accent.gamma_multiply(0.8)
            } else if resp.hovered() {
                t.accent.lerp_to_gamma(Color32::WHITE, 0.12)
            } else {
                t.accent
            };
            ui.painter().rect_filled(ir, 8.0, fill);
            paint(ui.painter(), Rect::from_center_size(pos2(ir.left() + 16.0, cy), vec2(13.0, 13.0)), Icon::Plus, Color32::WHITE);
            ui.painter().text(pos2(ir.left() + 28.0, cy), Align2::LEFT_CENTER, label, t.semibold(12.5), Color32::WHITE);
            if resp.clicked()
                && let Err(e) = app.run("file.addPhotos", json!({}))
            {
                app.toast_error(ui.ctx(), e);
            }
            rx = ir.left() - 12.0;

            let vw = VIEWS.len() as f32 * 26.0 + 4.0;
            let vr = pro::slot(rx - vw, cy, vw, 28.0);
            ui.painter().rect_filled(vr, 8.0, t.canvas);
            pro::outline(ui, vr, 8.0);
            for (i, &(id, icon, mode, cmd, tip)) in VIEWS.iter().enumerate() {
                let r = pro::slot(vr.left() + 2.0 + i as f32 * 26.0, cy, 26.0, 24.0);
                let on = app.ui.view == mode || (mode == ViewMode::PhotoGrid && app.ui.view == ViewMode::SquareGrid);
                let resp = pro::hit(ui, id, r, tip);
                pro::wash(ui, r, &resp, on, 6.0);
                paint(ui.painter(), Rect::from_center_size(r.center(), vec2(14.0, 14.0)), icon, if on { pro::accent_text(&t) } else { t.icon });
                if resp.clicked() {
                    let _ = app.run(cmd, json!({}));
                }
            }
            rx = vr.left() - 14.0;

            // ---- module switcher (right-aligned before the view modes): with labels when there is
            // room, icons only when tight, left out when there is none
            let sort_w = 150.0 + 44.0;
            let search_min = 180.0;
            let spare = rx - x - sort_w - search_min - 12.0;
            let labelled: Vec<f32> = MODULES.iter().map(|(l, _, _)| pro::text_w(ui, crate::i18n::tr(l), t.font(12.0)) + 36.0).collect();
            let compact: Vec<f32> = MODULES.iter().map(|_| 30.0).collect();
            let seg_w = if spare >= labelled.iter().sum::<f32>() + 18.0 {
                Some((labelled, true))
            } else if spare >= compact.iter().sum::<f32>() + 18.0 {
                Some((compact, false))
            } else {
                None
            };
            if let Some((seg_w, labels)) = seg_w {
                let sw: f32 = seg_w.iter().sum::<f32>() + 6.0;
                let sr = pro::slot(rx - sw, cy, sw, 28.0);
                ui.painter().rect_filled(sr, 8.0, t.canvas);
                pro::outline(ui, sr, 8.0);
                let cur = current_module(app.ui.view, app.ui.right);
                let mut sx = sr.left() + 3.0;
                for (i, (&(label, icon, cmd), w)) in MODULES.iter().zip(&seg_w).enumerate() {
                    let r = pro::slot(sx, cy, *w, 24.0);
                    let resp = pro::hit(ui, &format!("proModule:{}", label.to_lowercase()), r, if labels { "" } else { label });
                    let on = i == cur;
                    pro::wash(ui, r, &resp, on, 6.0);
                    let col = if on { pro::accent_text(&t) } else { t.text_label };
                    if labels {
                        paint(ui.painter(), Rect::from_center_size(pos2(r.left() + 13.0, cy), vec2(14.0, 14.0)), icon, col);
                        ui.painter().text(pos2(r.left() + 24.0, cy), Align2::LEFT_CENTER, crate::i18n::tr(label), t.font(12.0), col);
                    } else {
                        paint(ui.painter(), Rect::from_center_size(r.center(), vec2(14.0, 14.0)), icon, col);
                    }
                    if resp.clicked() {
                        if i > 0 && app.ui.view != ViewMode::Detail && cmd != "panel.activity" {
                            app.ui.view = ViewMode::Detail;
                        }
                        if i == 0 {
                            app.ui.right = RightPanel::None;
                            app.ui.presets = false;
                        }
                        let _ = app.run(cmd, json!({}));
                    }
                    sx += *w;
                }
                rx = sr.left() - 14.0;
            }

            // ---- sort + filter group, then the search field takes what is left
            let active_filters = lightcraft_engine::filter_chips(&app.session.filter, &app.session.catalog).len();
            let sort_text = crate::i18n::tr(sort_label(app.session.sort.key));
            let sbw = pro::text_w(ui, sort_text, t.font(12.0)) + 44.0;
            let gw = sbw + 44.0;
            let gr = pro::slot((rx - gw).max(x + search_min + 10.0), cy, gw, 28.0);
            ui.painter().rect_filled(gr, 8.0, t.canvas);
            pro::outline(ui, gr, 8.0);
            let sr = pro::slot(gr.left() + 2.0, cy, sbw, 24.0);
            let resp = pro::hit(ui, "icon:sort", sr, "Sort");
            pro::wash(ui, sr, &resp, false, 6.0);
            paint(ui.painter(), Rect::from_center_size(pos2(sr.left() + 14.0, cy), vec2(14.0, 14.0)), Icon::Sort, t.icon);
            ui.painter().text(pos2(sr.left() + 28.0, cy), Align2::LEFT_CENTER, sort_text, t.font(12.0), t.text_label);
            paint(ui.painter(), Rect::from_center_size(pos2(sr.right() - 10.0, cy), vec2(10.0, 10.0)), Icon::ChevronDown, t.text_dim);
            egui::Popup::menu(&resp).show(|ui| super::bottombar::sort_menu(app, ui));
            pro::vsep(ui, sr.right() + 1.0, cy, 16.0);
            let fr = pro::slot(sr.right() + 3.0, cy, 40.0, 24.0);
            let resp = pro::hit(ui, "icon:filter", fr, "Filter bar (Shift+F)");
            let on = app.ui.filter_bar;
            pro::wash(ui, fr, &resp, on, 6.0);
            let col = if on || active_filters > 0 { pro::accent_text(&t) } else { t.icon };
            paint(ui.painter(), Rect::from_center_size(pos2(fr.left() + 13.0, cy), vec2(14.0, 14.0)), Icon::Filter, col);
            if active_filters > 0 {
                ui.painter().text(pos2(fr.right() - 9.0, cy), Align2::CENTER_CENTER, active_filters.to_string(), t.semibold(11.0), col);
            }
            if resp.clicked() {
                let _ = app.run("view.filterBar", json!({}));
            }

            // search: 300 wide at most, between the title and the sort group
            let room = gr.left() - 10.0 - x;
            let w = room.clamp(120.0, 300.0);
            let sr = pro::slot(x, cy, w, 28.0);
            search_field(app, ui, sr, total);
        });
}

/// The 28 pt search field with its placeholder and shortcut hint.
fn search_field(app: &mut LightcraftApp, ui: &mut egui::Ui, sr: Rect, total: usize) {
    let t = Tokens::get(ui.ctx());
    let id = crate::text_field::id("field:search");
    if std::mem::take(&mut app.ui.focus_search) {
        ui.memory_mut(|m| m.request_focus(id));
    }
    let focused = ui.memory(|m| m.has_focus(id));
    ui.painter().rect(
        sr,
        8.0,
        t.field,
        Stroke::new(if focused { 1.5 } else { 1.0 }, if focused { t.accent } else { t.field_border }),
        StrokeKind::Inside,
    );
    paint(ui.painter(), Rect::from_center_size(pos2(sr.left() + 14.0, sr.center().y), vec2(14.0, 14.0)), Icon::Search, t.text_dim);
    let mac = ui.ctx().os() == egui::os::OperatingSystem::Mac;
    let hint = if mac { "⌘F" } else { "Ctrl+F" };
    let hint_w = pro::text_w(ui, hint, t.font(10.5)) + 10.0;
    let mut child = ui.new_child(
        egui::UiBuilder::new()
            .max_rect(Rect::from_min_max(pos2(sr.left() + 26.0, sr.top() + 3.0), pos2(sr.right() - hint_w - 6.0, sr.bottom() - 3.0)))
            .layout(egui::Layout::left_to_right(egui::Align::Center)),
    );
    if app.ui.search.is_empty() && !focused {
        let ph = crate::i18n::tr_format!("Search {n} photos", n = total);
        child.painter().text(pos2(sr.left() + 26.0, sr.center().y), Align2::LEFT_CENTER, ph, t.font(12.0), t.text_dim);
        let hr = pro::slot(sr.right() - hint_w - 4.0, sr.center().y, hint_w, 16.0);
        ui.painter().rect_stroke(hr, 4.0, Stroke::new(1.0, t.field_border), StrokeKind::Inside);
        ui.painter().text(hr.center(), Align2::CENTER_CENTER, hint, t.font(10.5), t.text_dim);
    }
    let resp = crate::text_field::TextField::singleline("field:search", &mut app.ui.search)
        .label(crate::i18n::tr("Search Photos"))
        .frame(false)
        .width((sr.width() - 26.0 - hint_w - 6.0).max(20.0))
        .font(t.font(12.0))
        .text_color(t.text)
        .show(&mut child)
        .response;
    if resp.changed() {
        let q = app.ui.search.clone();
        let _ = app.run("library.filter", json!({"text": q}));
    }
}
