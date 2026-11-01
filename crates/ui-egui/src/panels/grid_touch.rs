//! iPad-only behaviour of the Grid views (the empty library's import buttons, the missing-original
//! badge and the circular selection ticks on a cell). `grid.rs` calls these; each returns at once
//! unless `theme::touch_ui` is on, so desktop is untouched.

use egui::{Color32, Rect, Sense, Stroke, pos2, vec2};
use lightcraft_catalog::{Photo, PhotoId, Source};
use serde_json::json;

use crate::LightcraftApp;
use crate::icons::{Icon, paint};
use crate::theme::Tokens;
use crate::theme::touch_ui;
use crate::widgets::register;

/// The iPad's empty library: what to do next, with the actions on screen. Returns true when it drew
/// something, so the caller knows not to fall back to the desktop message.
pub(super) fn empty_library(app: &mut LightcraftApp, ui: &mut egui::Ui) -> bool {
    let r = ui.max_rect();
    empty_library_in(app, ui, r)
}

/// The iPad's empty-library screen in `r`: Files folder first (the Photos picker cannot reach Files), then Photos.
pub(super) fn empty_library_in(app: &mut LightcraftApp, ui: &mut egui::Ui, r: egui::Rect) -> bool {
    if !touch_ui(ui.ctx()) {
        return false;
    }
    let t = Tokens::get(ui.ctx());
    let c = r.center();
    let side = 24.0;
    let wrap = (r.width() - 2.0 * side).max(120.0);
    // two square tiles side by side; they shrink with the panel so neither is clipped
    let gap = 12.0;
    let tile = 150.0f32.min((r.width() - gap - 2.0 * side) / 2.0).max(96.0);
    let title = ui.painter().layout(crate::i18n::tr("No photos yet").to_string(), t.semibold(22.0), t.text, wrap);
    let body = ui.painter().layout(
        crate::i18n::tr("Bring in photos from Files or your Photos library to start editing.").to_string(),
        t.font(14.0),
        t.text_dim,
        wrap,
    );
    let block_h = title.size().y + 10.0 + body.size().y + 22.0 + tile;
    let top = c.y - block_h / 2.0;
    let p = ui.painter();
    p.galley(pos2(c.x - title.size().x / 2.0, top), title.clone(), t.text);
    let body_y = top + title.size().y + 10.0;
    p.galley(pos2(c.x - body.size().x / 2.0, body_y), body.clone(), t.text_dim);
    let y = body_y + body.size().y + 22.0;
    let import_folder = Rect::from_min_size(pos2(c.x - tile - gap / 2.0, y), vec2(tile, tile));
    let import_photos = Rect::from_min_size(pos2(c.x + gap / 2.0, y), vec2(tile, tile));
    for (rect, id, label, command, primary, icon) in [
        (import_folder, "emptyImportFolder", "Import from Folder", "file.addFolder", true, Icon::Folder),
        (import_photos, "emptyImportPhotos", "Import Photos", "file.addPhotos", false, Icon::Photos),
    ] {
        let resp = ui.interact(rect, egui::Id::unique(id), Sense::click());
        register(ui, format!("button:{id}"), rect);
        crate::widgets::announce(&resp, crate::i18n::tr(label));
        let fill = match (primary, resp.is_pointer_button_down_on(), resp.hovered()) {
            (true, true, _) => t.accent.gamma_multiply(0.8),
            (true, _, _) => t.accent,
            (false, true, _) => Color32::from_white_alpha(50),
            (false, _, true) => Color32::from_white_alpha(34),
            _ => Color32::from_white_alpha(22),
        };
        ui.painter().rect_filled(rect, 22.0, fill);
        paint(ui.painter(), Rect::from_center_size(pos2(rect.center().x, rect.top() + tile * 0.36), vec2(34.0, 34.0)), icon, Color32::WHITE);
        let text = ui.painter().layout(crate::i18n::tr(label).to_string(), t.semibold(15.0), Color32::WHITE, tile - 20.0);
        let text_pos = pos2(rect.center().x - text.size().x / 2.0, rect.top() + tile * 0.62);
        ui.painter().galley(text_pos, text, Color32::WHITE);
        if resp.clicked() {
            let _ = app.run(command, json!({}));
        }
    }
    true
}

/// The original is gone (a drive that left, or an old install): say so on the cell, not only in the
/// detail view.
pub(super) fn missing_badge(app: &LightcraftApp, ui: &egui::Ui, p: &egui::Painter, t: &Tokens, img_rect: Rect, photo: &Photo, id: PhotoId) {
    if !touch_ui(ui.ctx()) {
        return;
    }
    let Source::File { path } = &photo.source else { return };
    if !app.session.media.availability.is_offline(path) {
        return;
    }
    let g = p.layout_no_wrap(crate::i18n::tr("Original missing").into(), t.semibold(10.5), Color32::WHITE);
    let br = Rect::from_min_size(img_rect.left_top() + vec2(6.0, 6.0), vec2(g.size().x + 26.0, 20.0));
    p.rect_filled(br, 10.0, Color32::from_rgba_unmultiplied(40, 30, 10, 220));
    paint(p, Rect::from_center_size(pos2(br.left() + 11.0, br.center().y), vec2(13.0, 13.0)), Icon::Info, t.caution);
    p.galley(pos2(br.left() + 20.0, br.center().y - g.size().y / 2.0), g, Color32::WHITE);
    register(ui, format!("badge:missing:{}", id.0), br);
}

/// Apple-style circular multiselect checkbox (multi-select mode, or more than one photo selected).
pub(super) fn select_circle(app: &LightcraftApp, ui: &egui::Ui, p: &egui::Painter, t: &Tokens, img_rect: Rect, id: PhotoId, selected: bool) {
    if !touch_ui(ui.ctx()) || !(app.ui.multi_select || selected || app.session.selection.ids.len() > 1) {
        return;
    }
    let center = img_rect.right_top() + vec2(-18.0, 18.0);
    let check_circle = Rect::from_center_size(center, vec2(26.0, 26.0));
    register(ui, format!("select_circle:{}", id.0), check_circle);
    if selected {
        p.circle_filled(center, 12.0, t.accent);
        p.circle_stroke(center, 12.0, Stroke::new(1.0, Color32::WHITE));
        p.line_segment([center + vec2(-4.5, 0.0), center + vec2(-1.5, 3.5)], Stroke::new(2.4, Color32::WHITE));
        p.line_segment([center + vec2(-1.5, 3.5), center + vec2(5.0, -3.5)], Stroke::new(2.4, Color32::WHITE));
    } else {
        p.circle_filled(center, 12.0, Color32::from_rgba_unmultiplied(0, 0, 0, 100));
        p.circle_stroke(center, 12.0, Stroke::new(1.6, Color32::from_rgba_unmultiplied(255, 255, 255, 200)));
    }
}
