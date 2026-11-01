//! Shared look of the Pro desktop layout (Settings ▸ Appearance ▸ Layout ▸ Pro): the iPad V4 glass identity
//! (neutral dark glass, accent #0A84FF) at desktop density. Only used while `theme::desktop_pro` is on.

use egui::{Align2, Color32, CornerRadius, Rect, Response, Sense, Stroke, StrokeKind, Ui, pos2, vec2};

use crate::theme::Tokens;

/// Dense metrics (points).
pub const ROW_H: f32 = 26.0;
pub const GROUP_H: f32 = 30.0;
pub const CHIP_H: f32 = 22.0;
pub const BUTTON_H: f32 = 24.0;
pub const OPTION_BAR_H: f32 = 32.0;
pub const TOOL_STRIP_W: f32 = 38.0;
pub const TOOL_SIZE: f32 = 30.0;
pub const FILM_H: f32 = 104.0;
pub const STATUS_H: f32 = 24.0;
/// Radii: card 12, control 8.
pub const CARD_R: u8 = 12;
pub const CONTROL_R: u8 = 8;

/// The colours of the Pro look: the spec's tokens in the dark appearance, the active theme's own in a light one.
#[derive(Clone, Copy)]
pub struct Pal {
    pub text: Color32,
    pub text2: Color32,
    pub text3: Color32,
    pub text4: Color32,
    pub accent: Color32,
    pub accent_hi: Color32,
    pub accent_bg: Color32,
    pub field: Color32,
    pub field_h: Color32,
    pub rim2: Color32,
    pub track: Color32,
    pub glass: Color32,
    pub clip_hi: Color32,
    pub clip_sh: Color32,
}

impl Pal {
    pub fn get(ctx: &egui::Context) -> Pal {
        let t = Tokens::get(ctx);
        let accent = Color32::from_rgb(10, 132, 255);
        if ctx.global_style().visuals.dark_mode {
            Pal {
                text: Color32::from_rgb(0xEC, 0xEC, 0xF0),
                text2: Color32::from_rgb(0xB4, 0xB4, 0xBB),
                text3: Color32::from_rgb(0x82, 0x82, 0x8A),
                text4: Color32::from_rgb(0x5A, 0x5A, 0x62),
                accent,
                accent_hi: Color32::from_rgb(0x4A, 0xA3, 0xFF),
                accent_bg: Color32::from_rgba_unmultiplied(10, 132, 255, 46),
                field: Color32::from_white_alpha(18),
                field_h: Color32::from_white_alpha(31),
                rim2: Color32::from_white_alpha(18),
                track: Color32::from_white_alpha(41),
                glass: crate::glass::fill(),
                clip_hi: Color32::from_rgb(0xFF, 0x5A, 0x4A),
                clip_sh: Color32::from_rgb(0x4A, 0x8C, 0xFF),
            }
        } else {
            Pal {
                text: t.text,
                text2: t.text_label,
                text3: t.text_dim,
                text4: t.text_disabled,
                accent,
                accent_hi: accent,
                accent_bg: Color32::from_rgba_unmultiplied(10, 132, 255, 46),
                field: Color32::from_black_alpha(16),
                field_h: Color32::from_black_alpha(30),
                rim2: Color32::from_black_alpha(24),
                track: Color32::from_black_alpha(46),
                glass: t.chrome,
                clip_hi: Color32::from_rgb(0xE0, 0x30, 0x20),
                clip_sh: Color32::from_rgb(0x20, 0x60, 0xE0),
            }
        }
    }
}

/// A chip / segment (22pt high, pill). `active` paints the accent wash.
pub fn chip(ui: &mut Ui, id: &str, label: &str, active: bool) -> Response {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let galley = ui.painter().layout_no_wrap(label.to_string(), t.font(11.0), pal.text);
    let (r, resp) = ui.allocate_exact_size(vec2((galley.size().x + 18.0).max(34.0), CHIP_H), Sense::click());
    crate::widgets::announce_selected(&resp, label.to_string(), active);
    crate::widgets::register(ui, format!("button:{id}"), r);
    paint_chip(ui, r, &resp, label, active);
    resp
}

/// A chip that fills `r` (for equal-width clusters).
pub fn chip_in(ui: &mut Ui, id: &str, r: Rect, label: &str, active: bool) -> Response {
    let resp = ui.interact(r, ui.scope_id().with(("chip", id)), Sense::click());
    crate::widgets::announce_selected(&resp, label.to_string(), active);
    crate::widgets::register(ui, format!("button:{id}"), r);
    paint_chip(ui, r, &resp, label, active);
    resp
}

fn paint_chip(ui: &Ui, r: Rect, resp: &Response, label: &str, active: bool) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let fill = if active {
        pal.accent_bg
    } else if resp.hovered() {
        pal.field_h
    } else {
        pal.field
    };
    ui.painter().rect_filled(r, CornerRadius::same(255), fill);
    ui.painter().text(r.center(), Align2::CENTER_CENTER, label, t.font(11.0), if active { pal.accent_hi } else { pal.text });
}

/// A 24pt text button; `primary` fills it with the accent.
pub fn button(ui: &mut Ui, id: &str, label: &str, primary: bool) -> Response {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let galley = ui.painter().layout_no_wrap(label.to_string(), t.font(11.5), pal.text);
    let (r, resp) = ui.allocate_exact_size(vec2((galley.size().x + 20.0).max(44.0), BUTTON_H), Sense::click());
    crate::widgets::announce(&resp, label.to_string());
    crate::widgets::register(ui, format!("button:{id}"), r);
    let fill = if primary {
        if resp.hovered() { pal.accent_hi } else { pal.accent }
    } else if resp.hovered() {
        pal.field_h
    } else {
        pal.field
    };
    ui.painter().rect_filled(r, CornerRadius::same(CONTROL_R), fill);
    ui.painter().text(r.center(), Align2::CENTER_CENTER, label, t.font(11.5), if primary { Color32::WHITE } else { pal.text });
    resp
}

/// A small square icon button (`size` points), accent wash while `active`.
pub fn icon_button(ui: &mut Ui, id: &str, icon: crate::icons::Icon, size: f32, active: bool, tip: &str) -> Response {
    let pal = Pal::get(ui.ctx());
    let (r, resp) = ui.allocate_exact_size(vec2(size, size), Sense::click());
    crate::widgets::announce_selected(&resp, tip.to_string(), active);
    crate::widgets::register(ui, format!("button:{id}"), r);
    if active {
        ui.painter().rect_filled(r, CornerRadius::same(CONTROL_R), pal.accent_bg);
    } else if resp.hovered() {
        ui.painter().rect_filled(r, CornerRadius::same(CONTROL_R), pal.field_h);
    }
    crate::icons::paint(ui.painter(), r.shrink((size - 16.0).max(4.0) / 2.0), icon, if active { pal.accent_hi } else { pal.text2 });
    resp.on_hover_text(tip)
}

/// A hairline in the dock.
pub fn hairline(ui: &mut Ui) {
    let pal = Pal::get(ui.ctx());
    let (r, _) = ui.allocate_exact_size(vec2(ui.available_width(), 1.0), Sense::hover());
    ui.painter().rect_filled(r, 0.0, pal.rim2);
}

/// A sub-section title inside a group (11pt, bold, uppercase).
pub fn sub_title(ui: &mut Ui, title: &str) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let (r, _) = ui.allocate_exact_size(vec2(ui.available_width(), 24.0), Sense::hover());
    ui.painter().text(
        pos2(r.left() + 12.0, r.bottom() - 6.0),
        Align2::LEFT_BOTTOM,
        crate::i18n::tr(title).to_uppercase(),
        t.semibold(10.0),
        pal.text3,
    );
}

/// Paint a rounded rectangle outline inside `r` (focus ring and editing ring).
pub fn ring(ui: &Ui, r: Rect, radius: u8, color: Color32, width: f32) {
    ui.painter().rect_stroke(r, CornerRadius::same(radius), Stroke::new(width, color), StrokeKind::Inside);
}

/// The dock's egui style: 11.5pt text, rounded 8pt buttons on a soft field fill, an accent selection. Applied to the
/// panels the Pro dock shows (Develop, Crop, Masking…) so their stock buttons and checkboxes match the dense rows.
pub fn dock_style(ui: &mut Ui) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let style = ui.style_mut();
    for font in style.text_styles.values_mut() {
        font.size = font.size.min(12.0);
    }
    style.text_styles.insert(egui::TextStyle::Body, t.font(11.5));
    style.text_styles.insert(egui::TextStyle::Button, t.font(11.5));
    style.spacing.button_padding = vec2(8.0, 3.0);
    style.spacing.interact_size.y = 22.0;
    let r = CornerRadius::same(CONTROL_R);
    let w = &mut style.visuals.widgets;
    for (state, fill) in [(&mut w.inactive, pal.field), (&mut w.hovered, pal.field_h), (&mut w.active, pal.accent_bg)] {
        state.bg_fill = fill;
        state.weak_bg_fill = fill;
        state.corner_radius = r;
        state.bg_stroke = Stroke::NONE;
    }
    style.visuals.selection.bg_fill = pal.accent_bg;
    style.visuals.selection.stroke = Stroke::new(1.0, pal.accent_hi);
}
