//! Shared glass styling and touch shell for dialogs on iPad and iPhone.

use egui::{Align, Color32, CornerRadius, Frame, Layout, Margin, Response, RichText, Sense, Stroke, Ui, pos2, vec2};

use crate::theme::Tokens;

/// The corner radius for dialog glass cards.
pub const DIALOG_RADIUS: u8 = 28;
/// The inner padding around dialog content.
pub const DIALOG_PADDING: i8 = 16;
/// 44-point control height.
pub const CONTROL_H: f32 = 44.0;
/// The pill corner radius.
pub const PILL_RADIUS: f32 = 22.0;
/// The iOS accent blue (#0a84ff).
pub const ACCENT_BLUE: Color32 = Color32::from_rgb(10, 132, 255);

/// A rounded floating card; on phone it docks at the bottom as a sheet.
pub fn frame(ctx: &egui::Context) -> Frame {
    let phone = crate::theme::phone(ctx);
    let radius = if phone {
        CornerRadius { nw: DIALOG_RADIUS, ne: DIALOG_RADIUS, sw: DIALOG_RADIUS, se: DIALOG_RADIUS }
    } else {
        CornerRadius::same(DIALOG_RADIUS)
    };
    Frame::NONE
        .fill(crate::glass::fill())
        .corner_radius(radius)
        .shadow(crate::glass::shadow())
        .inner_margin(Margin::same(DIALOG_PADDING))
        .outer_margin(Margin::same(8))
        .stroke(Stroke::NONE)
}

/// A touch dialog's title row: 17pt semibold title on the left, 44pt round close button on the right.
/// Returns true when the close button was clicked.
pub fn title_row(ui: &mut Ui, title: &str) -> bool {
    let t = Tokens::get(ui.ctx());
    let mut closed = false;
    ui.allocate_ui_with_layout(vec2(ui.available_width(), CONTROL_H), Layout::left_to_right(Align::Center), |ui| {
        ui.add(egui::Label::new(RichText::new(crate::i18n::tr(title)).font(t.semibold(17.0)).color(t.text)));
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            let close_btn = crate::glass::close_button(ui);
            crate::widgets::register(ui, "button:dialogClose", close_btn.rect);
            if close_btn.clicked() {
                closed = true;
            }
        });
    });
    closed
}

/// The dialog footer: exactly ONE filled blue (#0a84ff) 44pt pill for the primary action,
/// with a neutral (white 12%) 44pt pill beside it for cancel when applicable.
/// Returns `(cancel_clicked, ok_clicked)`.
pub fn footer(ui: &mut Ui, cancel: &str, ok: &str, can_confirm: bool, primary: bool, informational: bool) -> (bool, bool) {
    let t = Tokens::get(ui.ctx());
    let phone = crate::theme::phone(ui.ctx());
    let mut cancel_clicked = false;
    let mut ok_clicked = false;

    let cancel_label = crate::i18n::tr(cancel);
    let ok_label = crate::i18n::tr(ok);

    let has_cancel = !informational && !cancel.is_empty();
    let has_ok = !ok.is_empty();

    let full_w = ui.available_width().max(1.0);

    ui.allocate_ui_with_layout(vec2(full_w, CONTROL_H), Layout::left_to_right(Align::Center), |ui| {
        if phone {
            if has_cancel && has_ok {
                let w = ((full_w - 8.0) / 2.0).max(40.0);
                let cancel_resp = draw_pill(ui, "button:dialogCancel", cancel_label, w, crate::ui_kit_touch::soft(ui, 31), t.text, true);
                if cancel_resp.clicked() {
                    cancel_clicked = true;
                }
                ui.add_space(8.0);
                let (fill, ink) = if can_confirm {
                    (if primary { ACCENT_BLUE } else { crate::ui_kit_touch::soft(ui, 46) }, Color32::WHITE)
                } else {
                    (crate::ui_kit_touch::soft(ui, crate::ui_kit_touch::CAPSULE_DISABLED_ALPHA), Color32::from_white_alpha(80))
                };
                let ok_resp = draw_pill(ui, "button:dialogOk", ok_label, w, fill, ink, can_confirm);
                if ok_resp.clicked() && can_confirm {
                    ok_clicked = true;
                }
            } else if has_ok {
                let (fill, ink) = if can_confirm {
                    (if primary { ACCENT_BLUE } else { crate::ui_kit_touch::soft(ui, 46) }, Color32::WHITE)
                } else {
                    (crate::ui_kit_touch::soft(ui, crate::ui_kit_touch::CAPSULE_DISABLED_ALPHA), Color32::from_white_alpha(80))
                };
                let ok_resp = draw_pill(ui, "button:dialogOk", ok_label, full_w, fill, ink, can_confirm);
                if ok_resp.clicked() && can_confirm {
                    ok_clicked = true;
                }
            } else if has_cancel || informational {
                let label = if !cancel.is_empty() { cancel_label } else { "Close" };
                let resp = draw_pill(ui, "button:dialogCancel", label, full_w, crate::ui_kit_touch::soft(ui, 31), t.text, true);
                if resp.clicked() {
                    cancel_clicked = true;
                }
            }
        } else {
            ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                if has_ok {
                    let ok_w = (ui.painter().layout_no_wrap(ok_label.to_string(), t.semibold(15.0), Color32::WHITE).size().x + 40.0).max(96.0);
                    let (fill, ink) = if can_confirm {
                        (if primary { ACCENT_BLUE } else { crate::ui_kit_touch::soft(ui, 46) }, Color32::WHITE)
                    } else {
                        (crate::ui_kit_touch::soft(ui, crate::ui_kit_touch::CAPSULE_DISABLED_ALPHA), Color32::from_white_alpha(80))
                    };
                    let ok_resp = draw_pill(ui, "button:dialogOk", ok_label, ok_w, fill, ink, can_confirm);
                    if ok_resp.clicked() && can_confirm {
                        ok_clicked = true;
                    }
                    ui.add_space(8.0);
                }
                if has_cancel {
                    let cancel_w = (ui.painter().layout_no_wrap(cancel_label.to_string(), t.semibold(15.0), t.text).size().x + 40.0).max(90.0);
                    let cancel_resp = draw_pill(ui, "button:dialogCancel", cancel_label, cancel_w, crate::ui_kit_touch::soft(ui, 31), t.text, true);
                    if cancel_resp.clicked() {
                        cancel_clicked = true;
                    }
                } else if informational && !has_ok {
                    let label = if !cancel.is_empty() { cancel_label } else { "Close" };
                    let close_w = (ui.painter().layout_no_wrap(label.to_string(), t.semibold(15.0), t.text).size().x + 40.0).max(90.0);
                    let resp = draw_pill(ui, "button:dialogCancel", label, close_w, crate::ui_kit_touch::soft(ui, 31), t.text, true);
                    if resp.clicked() {
                        cancel_clicked = true;
                    }
                }
            });
        }
    });

    (cancel_clicked, ok_clicked)
}

fn draw_pill(ui: &mut Ui, widget_name: &str, label: &str, width: f32, fill: Color32, ink: Color32, enabled: bool) -> Response {
    let t = Tokens::get(ui.ctx());
    let (rect, resp) = ui.allocate_exact_size(vec2(width, CONTROL_H), if enabled { Sense::click() } else { Sense::hover() });
    crate::widgets::announce(&resp, label);
    crate::widgets::register(ui, widget_name, rect);
    if ui.is_rect_visible(rect) {
        let p = ui.painter();
        let bg = if !enabled {
            fill
        } else if resp.is_pointer_button_down_on() {
            fill.gamma_multiply(0.8)
        } else if resp.hovered() {
            fill.gamma_multiply(1.1)
        } else {
            fill
        };
        p.rect_filled(rect, PILL_RADIUS, bg);
        let g = crate::widgets::one_line(p, label, t.semibold(15.0), ink, rect.width() - 16.0);
        let pos = pos2(rect.center().x - g.size().x / 2.0, rect.center().y - g.size().y / 2.0);
        p.galley(pos, g, ink);
    }
    resp
}

/// An iOS-style toggle row for dialogs: label on the left, animated switch on the right.
pub fn toggle(ui: &mut Ui, value: &mut bool, label: &str) -> Response {
    let t = Tokens::get(ui.ctx());
    let (rect, resp) = ui.allocate_exact_size(vec2(ui.available_width().max(1.0), CONTROL_H), Sense::click());
    let mut changed = false;
    if resp.clicked() {
        *value = !*value;
        changed = true;
    }
    if ui.is_rect_visible(rect) {
        let g = crate::widgets::one_line(ui.painter(), crate::i18n::tr(label), t.font(15.0), t.text, rect.width() - 60.0);
        let text_pos = pos2(rect.left(), rect.center().y - g.size().y / 2.0);
        ui.painter().galley(text_pos, g, t.text);

        const KNOB: f32 = 27.0;
        const TRACK_W: f32 = 51.0;
        const TRACK_H: f32 = 31.0;
        let track = egui::Rect::from_center_size(pos2(rect.right() - TRACK_W / 2.0 - 2.0, rect.center().y), vec2(TRACK_W, TRACK_H));
        let switch_id = resp.id.with("switch");
        let knob_x = ui.ctx().animate_value_with_time(
            switch_id.with("knob"),
            if *value { track.right() - KNOB / 2.0 - 2.0 } else { track.left() + KNOB / 2.0 + 2.0 },
            0.16,
        );
        let fill = if *value { ACCENT_BLUE } else { crate::ui_kit_touch::soft(ui, 26) };
        let p = ui.painter();
        p.rect_filled(track, TRACK_H / 2.0, fill);
        let knob_center = pos2(knob_x, track.center().y);
        p.circle_filled(knob_center + vec2(0.0, 1.0), KNOB / 2.0, Color32::from_black_alpha(45));
        p.circle_filled(knob_center, KNOB / 2.0, Color32::WHITE);
    }
    crate::widgets::announce_selected(&resp, crate::i18n::tr(label), *value);
    let mut final_resp = resp;
    if changed {
        final_resp.mark_changed();
    }
    final_resp
}
