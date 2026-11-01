//! Shared bits of the desktop "Pro" layout (Settings ▸ Appearance ▸ Layout): metrics and small
//! painted controls in the iPad V4 look at desktop density. Nothing here runs unless
//! [`crate::theme::desktop_pro`] is true.

use egui::{Color32, Rect, Response, Sense, Stroke, StrokeKind, pos2, vec2};

use crate::theme::Tokens;
use crate::widgets::{announce, register};

/// Toolbar height.
pub const TOOLBAR_H: f32 = 44.0;
/// Status bar height.
pub const STATUS_H: f32 = 26.0;
/// Sidebar and metadata row height.
pub const ROW_H: f32 = 24.0;
/// Right-panel section header height.
pub const PANEL_HEADER_H: f32 = 28.0;
/// Tile corner radius.
pub const TILE_RADIUS: f32 = 10.0;
/// Gap between tiles.
pub const TILE_GAP: f32 = 8.0;
/// Side padding of the grid.
pub const GRID_SIDE: f32 = 10.0;

/// Whether the Pro layout is on for this context.
pub fn on(ctx: &egui::Context) -> bool {
    crate::theme::desktop_pro(ctx)
}

/// The accent at a low alpha: the active-row and selected-tile wash.
pub fn accent_bg(t: &Tokens) -> Color32 {
    let a = t.accent;
    Color32::from_rgba_unmultiplied(a.r(), a.g(), a.b(), 56)
}

/// Text on the accent wash: the accent lifted towards white.
pub fn accent_text(t: &Tokens) -> Color32 {
    t.accent.lerp_to_gamma(Color32::WHITE, 0.45)
}

/// A hit area: registers it for automation and screen readers, and shows `tip` on hover.
pub fn hit(ui: &mut egui::Ui, id: &str, rect: Rect, tip: &str) -> Response {
    let resp = ui.interact(rect, egui::Id::unique(("pro", id)), Sense::click());
    register(ui, id, rect);
    announce(&resp, crate::i18n::tr(tip));
    if tip.is_empty() { resp } else { resp.on_hover_text(crate::i18n::tr(tip)) }
}

/// The hover / active wash behind a toolbar control.
pub fn wash(ui: &egui::Ui, rect: Rect, resp: &Response, active: bool, radius: f32) {
    let t = Tokens::get(ui.ctx());
    if active {
        ui.painter().rect_filled(rect, radius, accent_bg(&t));
    } else if resp.is_pointer_button_down_on() {
        ui.painter().rect_filled(rect, radius, t.pressed);
    } else if resp.hovered() {
        ui.painter().rect_filled(rect, radius, t.hover);
    }
}

/// A 1 px outline for grouped controls.
pub fn outline(ui: &egui::Ui, rect: Rect, radius: f32) {
    let t = Tokens::get(ui.ctx());
    ui.painter().rect_stroke(rect, radius, Stroke::new(1.0, t.field_border), StrokeKind::Inside);
}

/// A vertical separator `h` tall centred on `(x, y)`.
pub fn vsep(ui: &egui::Ui, x: f32, y: f32, h: f32) {
    let t = Tokens::get(ui.ctx());
    ui.painter().vline(x, (y - h / 2.0)..=(y + h / 2.0), Stroke::new(1.0, t.divider));
}

/// Width of `text` in `font`.
pub fn text_w(ui: &egui::Ui, text: &str, font: egui::FontId) -> f32 {
    ui.painter().layout_no_wrap(text.to_string(), font, Color32::WHITE).size().x
}

/// Rect of a control `w` wide, 28 tall, vertically centred on `cy`, starting at `x`.
pub fn slot(x: f32, cy: f32, w: f32, h: f32) -> Rect {
    Rect::from_min_size(pos2(x, cy - h / 2.0), vec2(w, h))
}
