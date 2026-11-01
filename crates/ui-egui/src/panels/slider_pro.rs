//! The Pro desktop layout's slider: one dense line (label, track, numeric field), 26pt high.
//!
//! * Click or drag the track; Alt/Option drags fine (a tenth), Shift coarse (ten times). Pressing or releasing a
//!   modifier mid-drag re-anchors, so the thumb never jumps.
//! * Click the value to type it: Enter commits, Esc cancels, leaving the field commits.
//! * The wheel nudges only over the value field, or over a slider that has keyboard focus.
//! * Arrow keys nudge a focused slider (Shift ten times, Alt a tenth), Home resets, Enter or F2 types a value.
//! * Double-click the label or the track resets the control.

use egui::{Align, Align2, Color32, CornerRadius, Key, Modifiers, Rect, Sense, Stroke, Ui, pos2, vec2};
use lightcraft_develop::ControlSpec;

use super::ui_pro::{Pal, ROW_H, ring};
use crate::theme::Tokens;
use crate::widgets::{SliderOut, register, shown_value, typed_value};

const LABEL_W: f32 = 88.0;
const FIELD_W: f32 = 46.0;
const FIELD_H: f32 = 18.0;
const PAD_L: f32 = 12.0;
const PAD_R: f32 = 10.0;
const GAP: f32 = 8.0;

/// What a drag modifier does to the pointer's travel: Alt/Option a tenth, Shift ten times.
pub(crate) fn drag_scale(m: Modifiers) -> f32 {
    if m.alt {
        0.1
    } else if m.shift {
        10.0
    } else {
        1.0
    }
}

/// `value` moved by `steps` nudges scaled by `mult`: a nudge is about 1/200 of the range on the control's steps
/// (exposure 0.05, most sliders 1, temperature 50 K). A scaled nudge never rounds away to nothing: at least one step.
pub(crate) fn nudge_by(spec: &ControlSpec, value: f64, steps: f64, mult: f64) -> f64 {
    let step = spec.step.max(1e-9);
    let unit = if spec.id == "wb.temp" { 50.0 } else { ((spec.max - spec.min) / 200.0 / step).round().max(1.0) * step };
    let mut delta = unit * steps * mult;
    if delta != 0.0 && delta.abs() < step {
        delta = step * delta.signum();
    }
    (((value + delta) / step).round() * step).clamp(spec.min, spec.max)
}

/// The slider position (0..=1) a drag has reached: where it was anchored plus the pointer's travel over the
/// track's width, scaled by the modifier.
pub(crate) fn drag_pos(anchor_pos: f64, anchor_x: f32, x: f32, width: f32, scale: f32) -> f64 {
    if width <= 0.0 {
        return anchor_pos.clamp(0.0, 1.0);
    }
    (anchor_pos + f64::from((x - anchor_x) / width) * f64::from(scale)).clamp(0.0, 1.0)
}

/// Draw one dense slider row and report what the user did with it.
pub fn row(ui: &mut Ui, spec: &ControlSpec, value: f64, enabled: bool, label_override: Option<&str>) -> SliderOut {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let w = ui.available_width().max(120.0);
    let (row, _) = ui.allocate_exact_size(vec2(w, ROW_H), Sense::hover());
    let id = ui.scope_id().with(spec.id);
    let cy = row.center().y;
    let label_rect = Rect::from_min_size(pos2(row.left() + PAD_L, row.top()), vec2(LABEL_W.min(w * 0.4), ROW_H));
    let value_rect = Rect::from_center_size(pos2(row.right() - PAD_R - FIELD_W / 2.0, cy), vec2(FIELD_W, FIELD_H));
    let x0 = label_rect.right() + GAP;
    let x1 = (value_rect.left() - GAP).max(x0 + 24.0);
    let track_rect = Rect::from_min_max(pos2(x0, cy - 6.0), pos2(x1, cy + 6.0));
    let hit = Rect::from_min_max(pos2(x0 - 4.0, row.top()), pos2(x1 + 4.0, row.bottom()));
    let sense = if enabled { Sense::click_and_drag() } else { Sense::hover() };
    let resp = ui.interact(hit, id, sense);
    let label_resp = ui.interact(label_rect, id.with("label"), if enabled { Sense::click() } else { Sense::hover() });
    let value_resp = ui.interact(value_rect, id.with("value"), if enabled { Sense::click() } else { Sense::hover() });
    let label_text = crate::i18n::tr(label_override.unwrap_or(spec.label)).to_string();
    // screen readers: a slider named after its control, with its value, range and step
    resp.widget_info(|| egui::WidgetInfo::slider(enabled, value, label_text.clone()));
    let shown = shown_value(spec, value);
    ui.ctx().accesskit_node_builder(resp.id, |node| {
        node.set_min_numeric_value(spec.min);
        node.set_max_numeric_value(spec.max);
        node.set_numeric_value_step(spec.step);
        node.set_value(shown.clone());
        if enabled {
            node.add_action(egui::accesskit::Action::Increment);
            node.add_action(egui::accesskit::Action::Decrement);
        }
    });
    crate::widgets::announce(&label_resp, crate::i18n::tr_format!("Reset {name}", name = label_text.clone()));
    register(ui, format!("sliderLabel:{}", spec.id), label_rect);
    register(ui, format!("slider:{}", spec.id), track_rect);
    register(ui, format!("sliderValue:{}", spec.id), value_rect);
    crate::widgets::announce(&value_resp, format!("{label_text}: {}", crate::i18n::tr("Click to type a value")));
    if enabled {
        label_resp.clone().on_hover_text(crate::i18n::tr_format!("{name} — double-click to reset it", name = label_text.clone()).as_str());
    }

    if enabled && (resp.clicked() || resp.drag_started()) {
        resp.request_focus();
        ui.data_mut(|d| d.insert_temp(crate::widgets::focused_slider_key(), id));
    }
    if enabled && resp.gained_focus() {
        ui.data_mut(|d| d.insert_temp(crate::widgets::focused_slider_key(), id));
    }

    let to_x = |v: f64| track_rect.left() + spec.position(v) as f32 * track_rect.width();
    let step = spec.step.max(1e-9);
    let snap = |v: f64| ((v / step).round() * step).clamp(spec.min, spec.max);
    let mut out = SliderOut::default();
    let mut v = value;

    // typing a value
    let typing_id = id.with("typing");
    let mut typing: Option<(String, u8)> = ui.data(|d| d.get_temp(typing_id));
    if enabled && typing.is_none() {
        let key_edit = resp.has_focus() && ui.input(|i| i.key_pressed(Key::Enter) || i.key_pressed(Key::F2));
        if value_resp.clicked() || key_edit {
            typing = Some((shown_value(spec, value).trim_start_matches('+').replace('\u{2212}', "-"), 0));
        }
    }
    if let Some((mut text, frames)) = typing.take() {
        ui.painter().rect_filled(value_rect.expand2(vec2(2.0, 1.0)), CornerRadius::same(6), Color32::from_rgb(0x0C, 0x0C, 0x10));
        ring(ui, value_rect.expand2(vec2(2.0, 1.0)), 6, pal.accent, 1.5);
        let mut child = ui.new_child(egui::UiBuilder::new().max_rect(value_rect).layout(egui::Layout::right_to_left(Align::Center)));
        let field = crate::text_field::TextField::singleline(&format!("sliderField:{}", spec.id), &mut text)
            .font(t.font(11.0))
            .horizontal_align(Align::RIGHT)
            .width(value_rect.width())
            .margin(egui::Margin::symmetric(4, 0))
            .frame(false)
            .select_on_focus(true)
            .begin_edit(frames == 0)
            .show(&mut child);
        use crate::text_field::Ending;
        if frames < 2 && !matches!(field.ending, Some(Ending::Return | Ending::Escape)) {
            field.response.request_focus();
            let frames = frames.saturating_add(1);
            ui.data_mut(|d| d.insert_temp(typing_id, (text.clone(), frames)));
        } else if field.ending.is_some() || !field.editing || !enabled {
            let cancelled = !enabled || field.cancelled();
            if !cancelled {
                if let Some(nv) = typed_value(spec, &text) {
                    if (nv - value).abs() > 1e-12 {
                        out.value = Some(nv);
                        out.drag_started = true;
                        out.drag_stopped = true;
                        v = nv;
                    }
                } else {
                    // unparseable: the old value stays (the field simply closes)
                }
            }
            ui.data_mut(|d| d.remove::<(String, u8)>(typing_id));
        } else {
            ui.data_mut(|d| d.insert_temp(typing_id, (text.clone(), frames)));
        }
    } else if resp.double_clicked() || label_resp.double_clicked() {
        out.reset = true;
        out.value = Some(spec.default);
        v = spec.default;
    } else {
        let mods = ui.input(|i| i.modifiers);
        let scale = drag_scale(mods);
        let drag_id = id.with("drag");
        if resp.drag_started() {
            out.drag_started = true;
            ui.data_mut(|d| d.remove::<(f64, f32, f32)>(drag_id));
        }
        if (resp.dragged() || resp.drag_started())
            && let Some(p) = resp.interact_pointer_pos()
        {
            let kept: Option<(f64, f32, f32)> = ui.data(|d| d.get_temp(drag_id));
            let (apos, ax, ascale) = match kept {
                Some(k) if (k.2 - scale).abs() < f32::EPSILON => k,
                Some(_) => (spec.position(value), p.x, scale),
                None => {
                    // the first frame: the thumb jumps to the pointer (a click on the track), then travel is relative
                    let pos = f64::from(((p.x - track_rect.left()) / track_rect.width().max(1.0)).clamp(0.0, 1.0));
                    (pos, p.x, scale)
                }
            };
            ui.data_mut(|d| d.insert_temp(drag_id, (apos, ax, ascale)));
            let pos = drag_pos(apos, ax, p.x, track_rect.width(), ascale);
            let nv = snap(spec.value_at(pos));
            if (nv - value).abs() > 1e-12 {
                out.value = Some(nv);
                v = nv;
            }
        } else if resp.clicked()
            && let Some(p) = resp.interact_pointer_pos()
            && (p.x - to_x(value)).abs() > 6.0
        {
            let nv = snap(spec.value_at(f64::from(((p.x - track_rect.left()) / track_rect.width().max(1.0)).clamp(0.0, 1.0))));
            out.value = Some(nv);
            out.drag_started = true;
            out.drag_stopped = true;
            v = nv;
        }
        if resp.drag_stopped() {
            out.drag_stopped = true;
            ui.data_mut(|d| d.remove::<(f64, f32, f32)>(drag_id));
        }

        // keyboard on a focused slider
        if enabled && out.value.is_none() && resp.has_focus() {
            let mut nv = None;
            ui.input_mut(|i| {
                for (m, mult) in [(Modifiers::NONE, 1.0), (Modifiers::SHIFT, 10.0), (Modifiers::ALT, 0.1)] {
                    for (key, dir) in [(Key::ArrowUp, 1.0), (Key::ArrowRight, 1.0), (Key::ArrowDown, -1.0), (Key::ArrowLeft, -1.0)] {
                        if nv.is_none() && i.consume_key(m, key) {
                            nv = Some(nudge_by(spec, value, dir, mult));
                        }
                    }
                }
                for (key, dir) in [(Key::PageUp, 1.0), (Key::PageDown, -1.0)] {
                    if nv.is_none() && i.consume_key(Modifiers::NONE, key) {
                        nv = Some(nudge_by(spec, value, dir, 10.0));
                    }
                }
                if nv.is_none() && i.consume_key(Modifiers::NONE, Key::Home) {
                    nv = Some(spec.default);
                }
            });
            if let Some(nv) = nv.filter(|nv| (nv - value).abs() > 1e-12) {
                out.value = Some(nv);
                out.drag_started = true;
                out.drag_stopped = true;
                v = nv;
            }
            if ui.input_mut(|i| i.consume_key(Modifiers::NONE, Key::Escape)) {
                resp.surrender_focus();
            }
        }

        // the wheel: only over the value field, or over a focused slider (so scrolling the dock never edits)
        let wheel_id = id.with("wheel-rem");
        let over_row = ui.rect_contains_pointer(row);
        if enabled && out.value.is_none() && (value_resp.hovered() || (resp.has_focus() && over_row)) {
            let dy = ui.input_mut(|i| std::mem::take(&mut i.smooth_scroll_delta.y));
            if dy != 0.0 {
                let mut rem = ui.data(|d| d.get_temp::<f32>(wheel_id)).unwrap_or(0.0);
                let total = (rem + dy).clamp(-1000.0, 1000.0);
                let per = crate::theme::WHEEL_LINE_POINTS.max(1.0);
                let steps = (total / per).trunc();
                rem = total - steps * per;
                ui.data_mut(|d| d.insert_temp(wheel_id, rem));
                if steps != 0.0 {
                    let nv = nudge_by(spec, value, f64::from(steps), f64::from(drag_scale(mods)));
                    if (nv - value).abs() > 1e-12 {
                        out.value = Some(nv);
                        out.drag_started = true;
                        out.drag_stopped = true;
                        v = nv;
                    }
                }
            }
        } else {
            ui.data_mut(|d| d.remove::<f32>(wheel_id));
        }
    }

    paint(
        ui,
        &pal,
        &t,
        spec,
        PaintArgs {
            row,
            label_rect,
            value_rect,
            track_rect,
            label: &label_text,
            value: v,
            enabled,
            resp: &resp,
            value_resp: &value_resp,
            editing: ui.data(|d| d.get_temp::<(String, u8)>(typing_id)).is_some(),
        },
    );
    out
}

struct PaintArgs<'a> {
    row: Rect,
    label_rect: Rect,
    value_rect: Rect,
    track_rect: Rect,
    label: &'a str,
    value: f64,
    enabled: bool,
    resp: &'a egui::Response,
    value_resp: &'a egui::Response,
    editing: bool,
}

fn paint(ui: &Ui, pal: &Pal, t: &Tokens, spec: &ControlSpec, a: PaintArgs) {
    let p = ui.painter();
    let edited = (a.value - spec.default).abs() > 1e-9;
    let fade = |c: Color32| if a.enabled { c } else { c.gamma_multiply(0.4) };
    let hovered = a.resp.hovered() || a.resp.dragged() || ui.rect_contains_pointer(a.row);
    if hovered && a.enabled {
        p.rect_filled(a.row, CornerRadius::same(4), Color32::from_white_alpha(10));
    }
    if a.resp.has_focus() && a.enabled {
        ring(ui, a.row.shrink(0.75), 4, pal.accent, 1.5);
    }
    // label
    p.with_clip_rect(a.label_rect).text(
        pos2(a.label_rect.left(), a.label_rect.center().y),
        Align2::LEFT_CENTER,
        a.label,
        if edited { t.semibold(11.5) } else { t.font(11.5) },
        fade(if edited { pal.text } else { pal.text2 }),
    );
    // track
    let y = a.track_rect.center().y;
    let tr = a.track_rect;
    let x_of = |v: f64| tr.left() + spec.position(v) as f32 * tr.width();
    let tx = x_of(a.value);
    let x_def = x_of(spec.default);
    if let Some(stops) = crate::widgets::track_stops(&spec.track) {
        let n = stops.len().max(2) - 1;
        let steps = 40usize;
        for i in 0..steps {
            let (f0, f1) = (i as f32 / steps as f32, (i + 1) as f32 / steps as f32);
            let seg = ((f0 * n as f32).floor() as usize).min(n.saturating_sub(1));
            let local = f0 * n as f32 - seg as f32;
            let (Some(c0), Some(c1)) = (stops.get(seg), stops.get(seg + 1)) else { continue };
            let c = fade(crate::widgets::lerp(*c0, *c1, local));
            let r = Rect::from_min_max(pos2(tr.left() + tr.width() * f0, y - 2.0), pos2(tr.left() + tr.width() * f1 + 0.5, y + 2.0));
            p.rect_filled(r, 0.0, c);
        }
    } else {
        p.rect_filled(Rect::from_min_max(pos2(tr.left(), y - 1.5), pos2(tr.right(), y + 1.5)), CornerRadius::same(2), fade(pal.track));
        if edited {
            let (xa, xb) = (x_def.min(tx), x_def.max(tx));
            p.rect_filled(Rect::from_min_max(pos2(xa, y - 1.5), pos2(xb, y + 1.5)), CornerRadius::same(2), fade(pal.accent));
        }
    }
    // the default tick on centred and gradient tracks
    let centred = (spec.default - spec.min).abs() > 1e-9 || crate::widgets::track_stops(&spec.track).is_some();
    if centred {
        p.line_segment([pos2(x_def, y - 4.5), pos2(x_def, y + 4.5)], Stroke::new(1.0, fade(Color32::from_white_alpha(90))));
    }
    // thumb: 11pt, 13pt on hover; edited = white with an accent ring
    let r = if hovered && a.enabled { 6.5 } else { 5.5 };
    let c = pos2(tx, y);
    if edited {
        p.circle_filled(c, r, fade(Color32::WHITE));
        p.circle_stroke(c, r, Stroke::new(2.0, fade(pal.accent)));
    } else {
        p.circle_filled(c, r, fade(Color32::from_rgb(0xE8, 0xE8, 0xEE)));
        p.circle_stroke(c, r, Stroke::new(1.0, Color32::from_black_alpha(90)));
    }
    if hovered && a.enabled {
        ui.ctx().set_cursor_icon(egui::CursorIcon::ResizeHorizontal);
    }
    // numeric field
    if !a.editing {
        let bg = if a.value_resp.hovered() && a.enabled { pal.field_h } else { pal.field };
        p.rect_filled(a.value_rect, CornerRadius::same(6), fade(bg));
        p.text(
            pos2(a.value_rect.right() - 5.0, a.value_rect.center().y),
            Align2::RIGHT_CENTER,
            shown_value(spec, a.value).replace('-', "\u{2212}"),
            t.font(11.0),
            fade(if edited { pal.accent_hi } else { pal.text }),
        );
        if a.value_resp.hovered() && a.enabled {
            ui.ctx().set_cursor_icon(egui::CursorIcon::Text);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use lightcraft_develop::controls;

    fn spec(id: &str) -> ControlSpec {
        *controls::find(id).expect("control exists")
    }

    // Feature: Alt/Option drags fine, Shift coarse
    #[test]
    fn modifiers_scale_a_drag() {
        assert_eq!(drag_scale(Modifiers::NONE), 1.0);
        assert_eq!(drag_scale(Modifiers::ALT), 0.1);
        assert_eq!(drag_scale(Modifiers::SHIFT), 10.0);
        let plain = drag_pos(0.5, 100.0, 120.0, 200.0, 1.0);
        let fine = drag_pos(0.5, 100.0, 120.0, 200.0, 0.1);
        let coarse = drag_pos(0.5, 100.0, 120.0, 200.0, 10.0);
        assert!((plain - 0.6).abs() < 1e-6 && (fine - 0.51).abs() < 1e-6);
        assert_eq!(coarse, 1.0, "a coarse drag clamps to the range");
        assert_eq!(drag_pos(0.5, 0.0, 10.0, 0.0, 1.0), 0.5, "a zero-width track cannot divide by zero");
    }

    // Feature: nudges move by whole steps; fine nudges never round to nothing
    #[test]
    fn nudges_stay_on_steps_and_in_range() {
        let ex = spec("light.exposure");
        let up = nudge_by(&ex, 0.0, 1.0, 1.0);
        assert!(up > 0.0 && ((up / ex.step).round() * ex.step - up).abs() < 1e-9);
        let fine = nudge_by(&ex, 0.0, 1.0, 0.1);
        assert!(fine >= ex.step - 1e-9, "a fine nudge moves at least one step");
        assert!(fine < up);
        assert_eq!(nudge_by(&ex, ex.max, 5.0, 10.0), ex.max, "clamped at the top");
        assert_eq!(nudge_by(&ex, 0.0, 0.0, 1.0), 0.0);
    }
}
