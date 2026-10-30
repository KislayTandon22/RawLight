//! The library's top bar (touch + glass): one floating capsule with the collection menu, the
//! search field, Sort, the filter pill, Select and the blue Import button. It replaces the desktop
//! bar ([`super::topbar_touch`]) in the grid only: [`show`] returns whether it drew.

use egui::{Color32, CornerRadius, Frame, Id, Margin, Rect, Sense, pos2, vec2};
use serde_json::json;

use crate::LightcraftApp;
use crate::icons::{Icon, paint};
use crate::state::ViewMode;
use crate::theme::Tokens;
use crate::widgets::{announce, register};

const CONTROL_H: f32 = crate::ui_kit_touch::CONTROL_H;
const BAR_H: f32 = crate::ui_kit_touch::BAR_H;
const GAP: f32 = 6.0;
const BLUE: Color32 = Color32::from_rgb(10, 132, 255);

fn soft(alpha: u8) -> Color32 {
    Color32::from_white_alpha(alpha)
}

fn grid_open(app: &LightcraftApp) -> bool {
    app.ui.view == ViewMode::PhotoGrid && !app.ui.right.is_edit_tool()
}

/// A text capsule (label, optional filled blue); returns its response.
fn pill(ui: &mut egui::Ui, id: &str, rect: Rect, label: &str, fill: Color32, ink: Color32, weight_bold: bool) -> egui::Response {
    let t = Tokens::get(ui.ctx());
    let resp = ui.interact(rect, Id::unique(("grid-bar", id)), Sense::click());
    announce(&resp, label.to_owned());
    register(ui, format!("gridBar:{id}"), rect);
    let down = resp.is_pointer_button_down_on();
    let fill = if fill == Color32::TRANSPARENT && down { soft(30) } else { fill };
    ui.painter().rect_filled(rect, rect.height() / 2.0, fill);
    let font = if weight_bold { t.semibold(15.0) } else { t.font(15.0) };
    ui.painter().text(rect.center(), egui::Align2::CENTER_CENTER, label, font, ink);
    resp
}

fn text_width(ui: &egui::Ui, label: &str, size: f32) -> f32 {
    let t = Tokens::get(ui.ctx());
    ui.painter().layout_no_wrap(label.to_owned(), t.semibold(size), Color32::WHITE).size().x
}

pub fn show(app: &mut LightcraftApp, ui: &mut egui::Ui) -> bool {
    let ctx = ui.ctx().clone();
    if !crate::theme::touch_ui(&ctx) || !crate::glass::active(&ctx) || !grid_open(app) || crate::theme::phone(&ctx) {
        return false;
    }
    let insets = crate::theme::safe_area_insets(&ctx);
    let safe_top = insets[0].max(28.0);
    let frame = Frame::NONE
        .fill(crate::glass::fill())
        .stroke(crate::glass::rim())
        .corner_radius(CornerRadius::same((BAR_H / 2.0).round() as u8))
        .shadow(crate::glass::shadow())
        .inner_margin(Margin { left: 8, right: 8, top: 0, bottom: 0 })
        .outer_margin(Margin { left: 8 + insets[2].round() as i8, right: 8 + insets[3].round() as i8, top: safe_top.round() as i8 + 8, bottom: 8 });
    egui::Panel::top("grid_bar").exact_size(BAR_H + safe_top + 16.0).frame(frame).show(ui, |ui| {
        let (rect, _) = ui.allocate_exact_size(vec2(ui.available_width(), BAR_H), Sense::hover());
        contents(app, ui, rect);
    });
    true
}

fn contents(app: &mut LightcraftApp, ui: &mut egui::Ui, rect: Rect) {
    let t = Tokens::get(ui.ctx());
    let cy = rect.center().y;
    let row = |left: f32, w: f32| Rect::from_min_size(pos2(left, cy - CONTROL_H / 2.0), vec2(w, CONTROL_H));

    // right cluster, laid out from the right edge: Import, Select, filter, Sort
    let mut right = rect.right();
    let import_w = text_width(ui, "Import", 15.0) + 56.0;
    let import = row(right - import_w, import_w);
    right = import.left() - GAP;
    let select_label = if app.ui.multi_select { "Done" } else { "Select" };
    let select_w = text_width(ui, select_label, 15.0) + 32.0;
    let select = row(right - select_w, select_w);
    right = select.left() - GAP;
    let active = lightcraft_engine::filter_chips(&app.session.filter, &app.session.catalog).len();
    let filter_w = if active > 0 { 76.0 } else { CONTROL_H + 8.0 };
    let filter = row(right - filter_w, filter_w);
    right = filter.left() - GAP;
    let sort = row(right - CONTROL_H - 8.0, CONTROL_H + 8.0);
    right = sort.left() - GAP * 2.0;

    // left: the collection menu, then the search field filling what is left
    let title = crate::i18n::source_title(&app.session);
    let title_w = (text_width(ui, &title, 17.0) + 56.0).clamp(120.0, 260.0);
    let collection = row(rect.left(), title_w);
    let search = row(collection.right() + GAP * 2.0, (right - collection.right() - GAP * 2.0).max(120.0));

    // collection
    let resp = ui.interact(collection, Id::unique(("grid-bar", "collection")), Sense::click());
    announce(&resp, title.clone());
    register(ui, "gridBar:collection", collection);
    ui.painter().text(pos2(collection.left() + 14.0, cy), egui::Align2::LEFT_CENTER, &title, t.semibold(17.0), Color32::WHITE);
    paint(ui.painter(), Rect::from_center_size(pos2(collection.right() - 16.0, cy), vec2(14.0, 14.0)), Icon::ChevronDown, soft(190));
    if resp.clicked() {
        let _ = app.run("view.leftPanel", json!({}));
    }

    // search
    ui.painter().rect_filled(search, search.height() / 2.0, soft(26));
    paint(ui.painter(), Rect::from_center_size(pos2(search.left() + 22.0, cy), vec2(16.0, 16.0)), Icon::Search, soft(158));
    let mut child = ui.new_child(
        egui::UiBuilder::new()
            .max_rect(Rect::from_min_max(pos2(search.left() + 40.0, search.top() + 4.0), pos2(search.right() - 12.0, search.bottom() - 4.0)))
            .layout(egui::Layout::left_to_right(egui::Align::Center)),
    );
    child.spacing_mut().interact_size.y = CONTROL_H - 8.0;
    if app.ui.search.is_empty() {
        let hint = crate::i18n::tr_format!("Search {n} photos", n = app.session.visible().len());
        ui.painter().text(pos2(search.left() + 40.0, cy), egui::Align2::LEFT_CENTER, hint, t.font(15.0), soft(130));
    }
    register(ui, "field:search", search);
    let r = crate::text_field::TextField::singleline("field:search", &mut app.ui.search)
        .label(crate::i18n::tr("Search Photos"))
        .frame(false)
        .width(search.width() - 56.0)
        .font(t.font(15.0))
        .text_color(Color32::WHITE)
        .show(&mut child)
        .response;
    if r.changed() {
        let q = app.ui.search.clone();
        let _ = app.run("library.filter", json!({"text": q}));
    }

    // sort
    let sr = ui.interact(sort, Id::unique(("grid-bar", "sort")), Sense::click());
    announce(&sr, crate::i18n::tr("Sort").to_owned());
    register(ui, "gridBar:sort", sort);
    if sr.is_pointer_button_down_on() {
        ui.painter().rect_filled(sort, sort.height() / 2.0, soft(30));
    }
    paint(ui.painter(), Rect::from_center_size(sort.center(), vec2(20.0, 20.0)), Icon::Sort, Color32::WHITE);
    egui::Popup::menu(&sr).show(|ui| {
        ui.set_min_width(220.0);
        super::bottombar_touch::sort_menu(app, ui)
    });

    // filter
    let fr = ui.interact(filter, Id::unique(("grid-bar", "filter")), Sense::click());
    announce(&fr, crate::i18n::tr("Filter").to_owned());
    register(ui, "gridBar:filter", filter);
    if active > 0 || app.ui.filter_bar {
        ui.painter().rect_filled(filter, filter.height() / 2.0, soft(36));
    } else if fr.is_pointer_button_down_on() {
        ui.painter().rect_filled(filter, filter.height() / 2.0, soft(30));
    }
    let ink = if active > 0 { Color32::from_rgb(74, 163, 255) } else { Color32::WHITE };
    if active > 0 {
        paint(ui.painter(), Rect::from_center_size(pos2(filter.left() + 24.0, cy), vec2(18.0, 18.0)), Icon::Filter, ink);
        ui.painter().text(pos2(filter.right() - 22.0, cy), egui::Align2::CENTER_CENTER, active.to_string(), t.semibold(15.0), ink);
    } else {
        paint(ui.painter(), Rect::from_center_size(filter.center(), vec2(18.0, 18.0)), Icon::Filter, ink);
    }
    if fr.clicked() {
        let _ = app.run("view.filterBar", json!({}));
    }

    // select
    if pill(ui, "select", select, crate::i18n::tr(select_label), Color32::TRANSPARENT, Color32::WHITE, true).clicked() {
        let _ = app.run("view.multiSelect", json!({}));
    }

    // import
    let ir = pill(ui, "import", import, "", BLUE, Color32::WHITE, true);
    ui.painter().text(pos2(import.center().x + 10.0, cy), egui::Align2::CENTER_CENTER, crate::i18n::tr("Import"), t.semibold(15.0), Color32::WHITE);
    paint(ui.painter(), Rect::from_center_size(pos2(import.left() + 24.0, cy), vec2(16.0, 16.0)), Icon::Plus, Color32::WHITE);
    if ir.clicked() {
        let _ = app.run("file.addFolder", json!({}));
    }
}
