//! The touch UI kit: the components the iPad and iPhone screens are built from, in the V4 design
//! language — floating glass capsule bars, controls 44 points tall, one filled blue action per
//! screen, a soft white oval for the selected state, and no outlines, hairlines or dividers.
//!
//! Every component draws only in a touch layout ([`crate::theme::touch_ui`]). In the desktop and
//! web-desktop layouts each one is inert (a zero-sized, non-interactive response), so a screen
//! shared by both layouts keeps exactly the behaviour and the pixels it had.
//!
//! ```ignore
//! if capsule_button(ui, "Done", Kind::Primary).clicked() { … }
//! segmented(ui, &["All", "Picked", "Rejected"], &mut app.ui.filter_tab);
//! ```
#![allow(dead_code)] // the touch screens adopt the kit one screen at a time; nothing calls it yet

use std::ops::RangeInclusive;

use egui::{Color32, CornerRadius, Rect, Response, Sense, Ui, pos2, vec2};

use crate::icons::{Icon, paint};
use crate::theme::Tokens;

/// A control's height: capsules, segments, the search field and the slider's hit area.
pub const CONTROL_H: f32 = 44.0;
/// The gap between controls of one group.
pub const GROUP_GAP: f32 = 8.0;
/// The margin a floating bar or a card keeps from the screen edge.
pub const SCREEN_MARGIN: f32 = 16.0;
/// A floating capsule bar's height.
pub const BAR_H: f32 = 60.0;

/// The design language's selected-state blue (#4aa3ff): the icon or label on the soft oval.
const SELECTED_BLUE: Color32 = Color32::from_rgb(0x4a, 0xa3, 0xff);
/// White at 62%: secondary text.
const SECONDARY_ALPHA: u8 = 158;
/// White at 20%: the selected oval.
const SELECTED_ALPHA: u8 = 51;
/// White at 12%: a neutral capsule's fill.
const NEUTRAL_ALPHA: u8 = 31;
/// White at 10%: a segmented control's track and the search capsule.
const TRACK_ALPHA: u8 = 26;
/// Blue at 18%: a tinted capsule's fill.
const TINT_ALPHA: u8 = 46;
/// Red at 18%: a destructive capsule's fill.
const DESTRUCTIVE_ALPHA: u8 = 46;

/// The inset of a segment's oval inside its slot, so the selected oval floats in the track.
const SEGMENT_INSET: f32 = 4.0;
/// A capsule's side padding around its label.
const CAPSULE_PAD: f32 = 20.0;

/// A menu card's corner radius and its inset from the card's edge.
const CARD_RADIUS: u8 = 28;
const CARD_INSET: i8 = 8;
/// A menu row's height, its side inset, icon size and the gap to its label.
const ROW_H: f32 = 48.0;
const ROW_INSET: f32 = 12.0;
const ROW_ICON: f32 = 20.0;
const ROW_GAP: f32 = 12.0;
/// The smallest and largest a menu card is drawn, and the gap before a row's value badge.
const CARD_MIN_W: f32 = 200.0;
const CARD_MAX_W: f32 = 420.0;
const VALUE_GAP: f32 = 12.0;

/// The slider's thumb radius (a 24-point thumb) and its track's thickness.
const THUMB_R: f32 = 12.0;
const TRACK_H: f32 = 4.0;

/// Whether the kit draws in this context: touch layouts only, never the desktop.
fn touch(ctx: &egui::Context) -> bool {
    crate::theme::touch_ui(ctx)
}

/// The response of a component that draws nothing here (a desktop layout): zero-sized, inert.
fn inert(ui: &mut Ui) -> Response {
    ui.allocate_exact_size(egui::Vec2::ZERO, Sense::hover()).1
}

/// The width a full-width component takes, with a fallback for an unbounded horizontal layout.
fn full_width(ui: &Ui) -> f32 {
    let w = ui.available_width();
    if w.is_finite() && w > 0.0 { w } else { 320.0 }
}

/// A neutral translucent fill: white at `white` percent on the dark glass look, the matching black
/// in a light theme, where a white fill would disappear.
fn soft(ui: &Ui, white: u8) -> Color32 {
    if ui.visuals().dark_mode { Color32::from_white_alpha(white) } else { Color32::from_black_alpha(white.saturating_mul(2) / 3) }
}

/// Secondary text: white at 62% on the dark glass look.
fn secondary(ui: &Ui, t: &Tokens) -> Color32 {
    if ui.visuals().dark_mode { Color32::from_white_alpha(SECONDARY_ALPHA) } else { t.text_dim }
}

/// The accent blue of a selected icon or label.
fn selected_ink(ui: &Ui, t: &Tokens) -> Color32 {
    if ui.visuals().dark_mode { SELECTED_BLUE } else { t.accent }
}

/// `c` at `alpha` (0-255), strengthened while hovered or pressed.
fn tinted(c: Color32, alpha: u8, pressed: bool, hovered: bool) -> Color32 {
    let alpha = if pressed {
        alpha.saturating_add(20)
    } else if hovered {
        alpha.saturating_add(10)
    } else {
        alpha
    };
    Color32::from_rgba_unmultiplied(c.r(), c.g(), c.b(), alpha)
}

/// What a capsule is for, which decides how loud it is.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Kind {
    /// The screen's one main action: filled with the accent, white bold text.
    Primary,
    /// A secondary action that belongs to the selection: a blue tint with blue text.
    Tint,
    /// Any other action: a quiet white tint.
    #[default]
    Neutral,
    /// A step that removes or erases something: a red tint.
    Destructive,
}

/// A capsule's fill and ink in `kind` for the current pointer state.
fn capsule_look(ui: &Ui, t: &Tokens, kind: Kind, pressed: bool, hovered: bool) -> (Color32, Color32) {
    let lighter = |c: Color32| crate::widgets::lerp(c, Color32::WHITE, 0.10);
    let darker = |c: Color32| crate::widgets::lerp(c, Color32::BLACK, 0.12);
    match kind {
        Kind::Primary => {
            let fill = if pressed {
                darker(t.accent)
            } else if hovered {
                lighter(t.accent)
            } else {
                t.accent
            };
            (fill, Color32::WHITE)
        }
        Kind::Tint => (tinted(t.accent, TINT_ALPHA, pressed, hovered), selected_ink(ui, t)),
        Kind::Neutral => {
            let alpha = if pressed {
                NEUTRAL_ALPHA.saturating_add(20)
            } else if hovered {
                NEUTRAL_ALPHA.saturating_add(10)
            } else {
                NEUTRAL_ALPHA
            };
            (soft(ui, alpha), t.text)
        }
        Kind::Destructive => (tinted(t.reject, DESTRUCTIVE_ALPHA, pressed, hovered), t.reject),
    }
}

/// A pill-shaped button 44 points tall, at least 44 wide, with `label` announced to screen readers.
pub fn capsule_button(ui: &mut Ui, label: &str, kind: Kind) -> Response {
    if !touch(ui.ctx()) {
        return inert(ui);
    }
    let t = Tokens::get(ui.ctx());
    let label = crate::i18n::tr(label);
    let font = if kind == Kind::Primary { t.semibold(15.0) } else { t.font(15.0) };
    let avail = ui.available_width();
    let max_text = if avail.is_finite() { (avail - 2.0 * CAPSULE_PAD).max(1.0) } else { f32::INFINITY };
    let galley = crate::widgets::one_line(ui.painter(), label, font, Color32::WHITE, max_text);
    let natural = (galley.size().x + 2.0 * CAPSULE_PAD).max(CONTROL_H);
    let w = if avail.is_finite() { natural.min(avail.max(CONTROL_H)) } else { natural };
    let (rect, resp) = ui.allocate_exact_size(vec2(w, CONTROL_H), Sense::click());
    crate::widgets::announce(&resp, label);
    if ui.is_rect_visible(rect) {
        let (fill, ink) = capsule_look(ui, &t, kind, resp.is_pointer_button_down_on(), resp.hovered());
        let p = ui.painter();
        p.rect_filled(rect, CONTROL_H / 2.0, fill);
        p.galley_with_override_text_color(rect.center() - galley.size() / 2.0, galley, ink);
    }
    resp
}

/// The rectangle of segment `i` of `n` in `track`: equal slots, each oval inset by
/// [`SEGMENT_INSET`]. [`Rect::NOTHING`] for no segments.
pub fn segment_rect(track: Rect, i: usize, n: usize) -> Rect {
    if n == 0 || i >= n {
        return Rect::NOTHING;
    }
    let w = track.width() / n as f32;
    let left = track.left() + w * i as f32;
    Rect::from_min_size(pos2(left, track.top()), vec2(w, track.height())).shrink2(vec2(SEGMENT_INSET, SEGMENT_INSET))
}

/// Which of `n` equal segments of `track` holds `x`; `None` outside the track.
pub fn segment_at(x: f32, track: Rect, n: usize) -> Option<usize> {
    if n == 0 || !x.is_finite() || !track.width().is_finite() || track.width() <= 0.0 {
        return None;
    }
    if x < track.left() || x > track.right() {
        return None;
    }
    let step = track.width() / n as f32;
    let i = ((x - track.left()) / step).floor().max(0.0);
    Some((i as usize).min(n - 1))
}

/// A segmented control: one 44-point capsule track, equal-width segments, the selected one a soft
/// oval with blue text. Updates `selected` on a tap and returns the track's response.
pub fn segmented(ui: &mut Ui, options: &[&str], selected: &mut usize) -> Response {
    if !touch(ui.ctx()) {
        return inert(ui);
    }
    let t = Tokens::get(ui.ctx());
    let (track, mut resp) = ui.allocate_exact_size(vec2(full_width(ui), CONTROL_H), Sense::hover());
    let n = options.len();
    if n == 0 {
        return resp;
    }
    if ui.is_rect_visible(track) {
        ui.painter().rect_filled(track, CONTROL_H / 2.0, soft(ui, TRACK_ALPHA));
    }
    let sel = (*selected).min(n - 1);
    let mut picked = None;
    for (i, label) in options.iter().enumerate() {
        let r = segment_rect(track, i, n);
        let seg = ui.interact(r, resp.id.with(("segment", i)), Sense::click());
        let label = crate::i18n::tr(label);
        crate::widgets::announce_selected(&seg, label, i == sel);
        if ui.is_rect_visible(r) {
            if i == sel {
                ui.painter().rect_filled(r, r.height() / 2.0, soft(ui, SELECTED_ALPHA));
            }
            let ink = if i == sel { selected_ink(ui, &t) } else { secondary(ui, &t) };
            let g = crate::widgets::one_line(ui.painter(), label, t.semibold(15.0), ink, r.width() - 12.0);
            ui.painter().galley(pos2(r.center().x - g.size().x / 2.0, r.center().y - g.size().y / 2.0), g, ink);
        }
        if seg.clicked() {
            picked = Some(i);
        }
    }
    if let Some(i) = picked.filter(|i| *i != *selected) {
        *selected = i;
        resp.mark_changed();
    }
    resp
}

/// [`segmented`] with icons: the same track and soft oval, each icon announced as an option.
pub fn icon_segment(ui: &mut Ui, icons: &[Icon], selected: &mut usize) -> Response {
    if !touch(ui.ctx()) {
        return inert(ui);
    }
    let (track, mut resp) = ui.allocate_exact_size(vec2(full_width(ui), CONTROL_H), Sense::hover());
    let n = icons.len();
    if n == 0 {
        return resp;
    }
    if ui.is_rect_visible(track) {
        ui.painter().rect_filled(track, CONTROL_H / 2.0, soft(ui, TRACK_ALPHA));
    }
    let t = Tokens::get(ui.ctx());
    let sel = (*selected).min(n - 1);
    let mut picked = None;
    for (i, icon) in icons.iter().enumerate() {
        let r = segment_rect(track, i, n);
        let seg = ui.interact(r, resp.id.with(("icon-segment", i)), Sense::click());
        let name = format!("{} {} / {n}", crate::i18n::tr("Option"), i + 1);
        crate::widgets::announce_selected(&seg, name, i == sel);
        if ui.is_rect_visible(r) {
            if i == sel {
                ui.painter().rect_filled(r, r.height() / 2.0, soft(ui, SELECTED_ALPHA));
            }
            let ink = if i == sel { selected_ink(ui, &t) } else { secondary(ui, &t) };
            let side = 20.0f32.min(r.height() - 8.0);
            paint(ui.painter(), Rect::from_center_size(r.center(), vec2(side, side)), *icon, ink);
        }
        if seg.clicked() {
            picked = Some(i);
        }
    }
    if let Some(i) = picked.filter(|i| *i != *selected) {
        *selected = i;
        resp.mark_changed();
    }
    resp
}

/// A 44-point search capsule: a search icon, the text field and a clear button while there is
/// text. `hint` is both the placeholder and the field's name for screen readers. Returns the
/// capsule's response, changed when the text changed.
pub fn search_capsule(ui: &mut Ui, text: &mut String, hint: &str) -> Response {
    if !touch(ui.ctx()) {
        return inert(ui);
    }
    let t = Tokens::get(ui.ctx());
    let (rect, mut resp) = ui.allocate_exact_size(vec2(full_width(ui), CONTROL_H), Sense::hover());
    // the kit has no caller id, so the field's place in the layout names it (stable while the
    // screen does not add or remove widgets above it)
    let salt = ui.next_auto_id();
    ui.skip_ahead_auto_ids(1);
    let field_id = format!("kit:search:{salt:?}");
    if ui.is_rect_visible(rect) {
        ui.painter().rect_filled(rect, CONTROL_H / 2.0, soft(ui, TRACK_ALPHA));
        let icon = Rect::from_center_size(pos2(rect.left() + 22.0, rect.center().y), vec2(18.0, 18.0));
        paint(ui.painter(), icon, Icon::Search, secondary(ui, &t));
    }
    let clear = Rect::from_center_size(pos2(rect.right() - 22.0, rect.center().y), vec2(CONTROL_H, CONTROL_H));
    let clear_resp = ui.interact(clear, resp.id.with("clear"), if text.is_empty() { Sense::hover() } else { Sense::click() });
    if !text.is_empty() {
        crate::widgets::announce(&clear_resp, crate::i18n::tr("Clear search"));
        if ui.is_rect_visible(clear) {
            let c = clear.center();
            ui.painter().circle_filled(c, 9.0, soft(ui, SELECTED_ALPHA));
            paint(ui.painter(), Rect::from_center_size(c, vec2(10.0, 10.0)), Icon::Close, secondary(ui, &t));
        }
    }
    if clear_resp.clicked() {
        text.clear();
        resp.mark_changed();
    }
    let field_rect = Rect::from_min_max(pos2(rect.left() + 40.0, rect.top() + 2.0), pos2(clear.left() - 2.0, rect.bottom() - 2.0));
    let mut child = ui.new_child(egui::UiBuilder::new().max_rect(field_rect).layout(egui::Layout::left_to_right(egui::Align::Center)));
    let field = crate::text_field::TextField::singleline(&field_id, text)
        .label(crate::i18n::tr(hint))
        .hint(crate::i18n::tr(hint))
        .frame(false)
        .width(field_rect.width())
        .font(t.font(15.0))
        .text_color(t.text)
        .show(&mut child);
    if field.response.changed() {
        resp.mark_changed();
    }
    resp
}

/// One row of a [`menu_card`]: an icon, a label, an optional right-aligned value badge and the
/// row's selected / enabled state.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MenuRow<'a> {
    pub icon: Icon,
    pub label: &'a str,
    pub value: Option<&'a str>,
    pub selected: bool,
    pub enabled: bool,
}

impl<'a> MenuRow<'a> {
    pub fn new(icon: Icon, label: &'a str) -> Self {
        Self { icon, label, value: None, selected: false, enabled: true }
    }
    /// A right-aligned value badge ("12", "On").
    pub fn value(mut self, value: &'a str) -> Self {
        self.value = Some(value);
        self
    }
    /// The selected row: a soft oval behind it.
    pub fn selected(mut self, on: bool) -> Self {
        self.selected = on;
        self
    }
    pub fn enabled(mut self, on: bool) -> Self {
        self.enabled = on;
        self
    }
}

/// A floating menu card: a rounded (28-point) card inset 8 points, with 48-point rows — a 20-point
/// icon, a 16-point label, an optional right-aligned value badge, a soft oval on the selected row
/// and no dividers. `on_pick` receives the index of a tapped row.
pub fn menu_card(ui: &mut Ui, rows: &[MenuRow<'_>], mut on_pick: impl FnMut(usize)) -> Response {
    if !touch(ui.ctx()) {
        return inert(ui);
    }
    let t = Tokens::get(ui.ctx());
    // the card fits its longest row, up to what the screen leaves
    let mut natural = CARD_MIN_W;
    for row in rows {
        let label = crate::widgets::one_line(ui.painter(), crate::i18n::tr(row.label), t.font(16.0), t.text, f32::INFINITY);
        let value = row.value.map_or(0.0, |v| {
            crate::widgets::one_line(ui.painter(), crate::i18n::tr(v), t.font(14.0), t.text_dim, f32::INFINITY).size().x + VALUE_GAP
        });
        natural = natural.max(ROW_INSET + ROW_ICON + ROW_GAP + label.size().x + value + ROW_INSET);
    }
    let avail = ui.available_width();
    let cap = if avail.is_finite() { (avail - 2.0 * f32::from(CARD_INSET)).max(CARD_MIN_W) } else { CARD_MAX_W };
    let inner_w = natural.min(cap);
    let fill = if crate::glass::active(ui.ctx()) { crate::glass::fill() } else { t.chrome };
    let out = egui::Frame::NONE
        .fill(fill)
        .corner_radius(CornerRadius::same(CARD_RADIUS))
        .shadow(crate::glass::shadow())
        .inner_margin(egui::Margin::same(CARD_INSET))
        .show(ui, |ui| {
            ui.set_width(inner_w);
            ui.spacing_mut().item_spacing.y = 2.0;
            for (i, row) in rows.iter().enumerate() {
                let sense = if row.enabled { Sense::click() } else { Sense::hover() };
                let (r, resp) = ui.allocate_exact_size(vec2(inner_w, ROW_H), sense);
                let label = crate::i18n::tr(row.label);
                crate::widgets::announce_selected(&resp, label, row.selected && row.enabled);
                if ui.is_rect_visible(r) {
                    let p = ui.painter();
                    if row.selected {
                        p.rect_filled(r, ROW_H / 2.0, soft(ui, SELECTED_ALPHA));
                    }
                    let ink = if !row.enabled {
                        t.text_disabled
                    } else if row.selected {
                        selected_ink(ui, &t)
                    } else {
                        t.text
                    };
                    let icon = Rect::from_center_size(pos2(r.left() + ROW_INSET + ROW_ICON / 2.0, r.center().y), vec2(ROW_ICON, ROW_ICON));
                    paint(p, icon, row.icon, if row.selected { ink } else { t.icon });
                    let text_left = r.left() + ROW_INSET + ROW_ICON + ROW_GAP;
                    let value = row.value.map(|v| {
                        let g = p.layout_no_wrap(crate::i18n::tr(v).to_string(), t.font(14.0), secondary(ui, &t));
                        let at = pos2(r.right() - ROW_INSET - g.size().x, r.center().y - g.size().y / 2.0);
                        (g, at)
                    });
                    let value_w = value.as_ref().map_or(0.0, |(g, _)| g.size().x + VALUE_GAP);
                    let max = (r.right() - ROW_INSET - value_w - text_left).max(1.0);
                    let g = crate::widgets::one_line(p, label, t.font(16.0), ink, max);
                    p.galley(pos2(text_left, r.center().y - g.size().y / 2.0), g, ink);
                    if let Some((g, at)) = value {
                        p.galley(at, g, secondary(ui, &t));
                    }
                }
                if resp.clicked() && row.enabled {
                    on_pick(i);
                }
            }
        });
    out.response
}

/// `value` held inside `range`; a reversed, empty or non-finite range gives its start.
pub fn clamp_value(value: f32, range: &RangeInclusive<f32>) -> f32 {
    let (lo, hi) = (*range.start(), *range.end());
    if !lo.is_finite() || !hi.is_finite() || lo > hi {
        return if lo.is_finite() { lo } else { 0.0 };
    }
    if value.is_finite() { value.clamp(lo, hi) } else { lo }
}

/// `value`'s place along a track as 0 to 1 (the middle for an empty or non-finite range).
pub fn slider_fraction(value: f32, range: &RangeInclusive<f32>) -> f32 {
    let (lo, hi) = (*range.start(), *range.end());
    let span = hi - lo;
    if !span.is_finite() || span <= 0.0 {
        return 0.5;
    }
    let f = (value - lo) / span;
    if f.is_finite() { f.clamp(0.0, 1.0) } else { 0.5 }
}

/// Where `value` sits on `track`.
pub fn slider_x(value: f32, track: Rect, range: &RangeInclusive<f32>) -> f32 {
    track.left() + slider_fraction(value, range) * track.width()
}

/// The value at `x` on `track`, clamped to `range`.
pub fn slider_value_at(x: f32, track: Rect, range: &RangeInclusive<f32>) -> f32 {
    let (lo, hi) = (*range.start(), *range.end());
    if !track.width().is_finite() || track.width() <= 0.0 || !(hi - lo).is_finite() || hi <= lo {
        return if lo.is_finite() { lo } else { 0.0 };
    }
    let f = if x.is_finite() { ((x - track.left()) / track.width()).clamp(0.0, 1.0) } else { 0.0 };
    lo + f * (hi - lo)
}

/// The accent-filled span of a slider's track: from the neutral value's position to the thumb's,
/// whichever side it is on (an empty span when the value is at neutral).
pub fn fill_span(thumb_x: f32, neutral_x: f32) -> (f32, f32) {
    (thumb_x.min(neutral_x), thumb_x.max(neutral_x))
}

/// A slider in the touch design: a thin track, a 24-point thumb with a 44-point hit area, the
/// accent filling the track from the neutral value to the thumb (so a move away from neutral reads
/// at a glance), a double tap resetting to `neutral` and arrow keys nudging while it has focus.
/// Returns the slider's response, changed when the value changed.
pub fn value_slider(ui: &mut Ui, value: &mut f32, range: RangeInclusive<f32>, neutral: f32) -> Response {
    if !touch(ui.ctx()) {
        return inert(ui);
    }
    let t = Tokens::get(ui.ctx());
    let (row, probe) = ui.allocate_exact_size(vec2(full_width(ui), CONTROL_H), Sense::hover());
    // the track keeps a thumb's width from each end, so the thumb never leaves the row
    let track =
        Rect::from_min_max(pos2(row.left() + THUMB_R, row.center().y - TRACK_H / 2.0), pos2(row.right() - THUMB_R, row.center().y + TRACK_H / 2.0));
    let mut resp = ui.interact(row, probe.id.with("value-slider"), Sense::click_and_drag());
    let (lo, hi) = (*range.start(), *range.end());
    let mut next = clamp_value(*value, &range);
    if let Some(p) = resp.interact_pointer_pos()
        && (resp.dragged() || resp.clicked())
    {
        next = slider_value_at(p.x, track, &range);
    }
    // a double tap (or the name read by a screen reader) goes back to neutral
    if resp.double_clicked() {
        next = clamp_value(neutral, &range);
    }
    if resp.has_focus() && resp.enabled() {
        let span = hi - lo;
        let step = if span.is_finite() && span > 0.0 { span / 100.0 } else { 0.0 };
        let (left, right, home, end, big) = ui.input(|i| {
            (
                i.key_pressed(egui::Key::ArrowLeft) || i.key_pressed(egui::Key::ArrowDown),
                i.key_pressed(egui::Key::ArrowRight) || i.key_pressed(egui::Key::ArrowUp),
                i.key_pressed(egui::Key::Home),
                i.key_pressed(egui::Key::End),
                i.modifiers.shift,
            )
        });
        let step = if big { step * 10.0 } else { step };
        if left {
            next = clamp_value(next - step, &range);
        }
        if right {
            next = clamp_value(next + step, &range);
        }
        if home {
            next = clamp_value(lo, &range);
        }
        if end {
            next = clamp_value(hi, &range);
        }
    }
    if next.is_finite() && next != *value {
        *value = next;
        resp.mark_changed();
    }
    // screen readers: the slider's name, its value after this frame's edit, and its range
    let name = crate::i18n::tr("Value").to_string();
    resp.widget_info(|| egui::WidgetInfo::slider(resp.enabled(), f64::from(*value), name.clone()));
    ui.ctx().accesskit_node_builder(resp.id, |node| {
        if lo.is_finite() {
            node.set_min_numeric_value(f64::from(lo));
        }
        if hi.is_finite() {
            node.set_max_numeric_value(f64::from(hi));
        }
        if resp.enabled() {
            node.add_action(egui::accesskit::Action::Increment);
            node.add_action(egui::accesskit::Action::Decrement);
        }
    });
    if ui.is_rect_visible(row) {
        let p = ui.painter();
        p.rect_filled(track, TRACK_H / 2.0, soft(ui, TRACK_ALPHA));
        let thumb_x = slider_x(*value, track, &range);
        let neutral_x = slider_x(clamp_value(neutral, &range), track, &range);
        let (from, to) = fill_span(thumb_x, neutral_x);
        if to - from > 0.5 {
            let span = Rect::from_min_max(pos2(from, track.top()), pos2(to, track.bottom()));
            p.rect_filled(span, TRACK_H / 2.0, t.accent);
        }
        let centre = pos2(thumb_x, row.center().y);
        p.circle_filled(centre + vec2(0.0, 1.0), THUMB_R, Color32::from_black_alpha(60));
        p.circle_filled(centre, THUMB_R, if resp.hovered() { t.thumb_hover } else { t.thumb });
    }
    resp
}

/// The state a [`photo_cell_badge`] draws over a thumbnail: the rating, the pick or reject flag,
/// whether the photo is edited, and why its preview is missing. A plain struct, so a screen builds
/// it from whatever it already knows and the badge draws nothing it was not told.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct CellBadge {
    /// Stars, 0 to 5.
    pub rating: u8,
    /// The photo is picked.
    pub pick: bool,
    /// The photo is rejected.
    pub reject: bool,
    /// The photo has edits.
    pub edited: bool,
    /// The original is offline (a smart preview stands in, or nothing does).
    pub offline: bool,
    /// The preview could not be decoded.
    pub undecodable: bool,
    /// The preview is still being made.
    pub loading: bool,
}

impl CellBadge {
    /// Whether there is nothing to draw or say.
    pub fn is_empty(&self) -> bool {
        self.rating == 0 && !self.pick && !self.reject && !self.edited && !self.offline && !self.undecodable && !self.loading
    }

    /// What the badge says in words, for the enclosing cell's screen-reader name.
    pub fn spoken(&self) -> String {
        let mut parts = Vec::new();
        if self.rating > 0 {
            parts.push(format!("{} {}/5", crate::i18n::tr("Rating"), self.rating.min(5)));
        }
        for (on, text) in [
            (self.pick, "Picked"),
            (self.reject, "Rejected"),
            (self.edited, "Edited"),
            (self.undecodable, "Preview unavailable"),
            (self.offline, "Original offline · no smart preview"),
            (self.loading, "Loading preview…"),
        ] {
            if on {
                parts.push(crate::i18n::tr(text).to_string());
            }
        }
        parts.join(", ")
    }
}

/// The side of one state icon on the badge strip and the gap between them.
const BADGE_ICON: f32 = 20.0;
const BADGE_GAP: f32 = 6.0;
/// The badge strip's inset from the thumbnail's edges and its height.
const BADGE_INSET: f32 = 8.0;
const BADGE_H: f32 = 20.0;
/// The smallest thumbnail the badge draws on.
const BADGE_MIN_W: f32 = 48.0;
const BADGE_MIN_H: f32 = 32.0;

/// Paint a cell's state over its thumbnail `rect` (stars, flag, edited, offline, undecodable and a
/// loading spinner), on a scrim so it reads on a bright photo. Draws only in a touch layout, never
/// allocates layout and never takes a click: the cell underneath keeps its own response and
/// announces [`CellBadge::spoken`] with its name.
pub fn photo_cell_badge(ui: &mut Ui, rect: Rect, state: &CellBadge) {
    if !touch(ui.ctx()) || state.is_empty() || !ui.is_rect_visible(rect) {
        return;
    }
    if !rect.width().is_finite() || !rect.height().is_finite() || rect.width() < BADGE_MIN_W || rect.height() < BADGE_MIN_H {
        return;
    }
    let t = Tokens::get(ui.ctx());
    let p = ui.painter();
    let strip = Rect::from_min_max(
        pos2(rect.left() + BADGE_INSET, rect.bottom() - BADGE_INSET - BADGE_H),
        pos2(rect.right() - BADGE_INSET, rect.bottom() - BADGE_INSET),
    );
    if !strip.width().is_finite() || strip.width() <= 0.0 {
        return;
    }
    // the right-hand state icons, laid out from the right edge inwards
    let mut right = strip.right();
    let mut icons: Vec<(Icon, Color32)> = Vec::new();
    if state.loading {
        icons.push((Icon::Clock, secondary(ui, &t)));
    }
    if state.undecodable {
        icons.push((Icon::Info, t.caution));
    }
    if state.offline {
        icons.push((Icon::Cloud, t.caution));
    }
    if state.edited {
        icons.push((Icon::Edited, secondary(ui, &t)));
    }
    // the left-hand group: the stars and the flag, on their own scrim
    let stars = state.rating.min(5);
    let stars_w = f32::from(stars) * crate::rating::RatingSize::Small.step();
    let flag = if state.pick {
        Some((Icon::FlagPickFilled, Color32::WHITE))
    } else if state.reject {
        Some((Icon::FlagReject, t.reject))
    } else {
        None
    };
    let flag_w = if flag.is_some() { BADGE_ICON } else { 0.0 };
    let left_w = stars_w + if flag.is_some() { BADGE_GAP + flag_w } else { 0.0 };
    // the room the icons leave for the left group
    let icons_w = icons.len() as f32 * (BADGE_ICON + BADGE_GAP);
    let room = strip.width() - icons_w;
    let left_fits = left_w > 0.0 && left_w <= room;
    if left_fits {
        let scrim = Rect::from_min_max(pos2(strip.left() - 4.0, strip.top()), pos2(strip.left() + left_w + 4.0, strip.bottom()));
        p.rect_filled(scrim, BADGE_H / 2.0, Color32::from_black_alpha(96));
    }
    if left_fits && stars > 0 {
        crate::rating::paint_rating(p, pos2(strip.left(), strip.center().y), stars, crate::rating::RatingSize::Small, t.star);
    }
    if left_fits && let Some((icon, ink)) = flag {
        let r = Rect::from_center_size(pos2(strip.left() + stars_w + BADGE_GAP + BADGE_ICON / 2.0, strip.center().y), vec2(16.0, 16.0));
        paint(p, r, icon, ink);
    }
    for (icon, ink) in icons {
        let r = Rect::from_center_size(pos2(right - BADGE_ICON / 2.0, strip.center().y), vec2(BADGE_ICON, BADGE_ICON));
        if r.left() < strip.left() + if left_fits { left_w + 4.0 } else { 0.0 } {
            break;
        }
        if icon == Icon::Clock && state.loading {
            crate::progress::paint_spinner(p, r.shrink(3.0), ink, ui.input(|i| i.time));
            ui.ctx().request_repaint_after(std::time::Duration::from_millis(100));
        } else {
            paint(p, r, icon, ink);
        }
        right -= BADGE_ICON + BADGE_GAP;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::headless::HeadlessView;
    use crate::theme::ThemeKind;

    fn track(left: f32, width: f32) -> Rect {
        Rect::from_min_size(pos2(left, 100.0), vec2(width, CONTROL_H))
    }

    #[test]
    fn segment_hit_testing_picks_the_slot_under_the_pointer() {
        let t = track(0.0, 300.0);
        assert_eq!(segment_at(10.0, t, 3), Some(0));
        assert_eq!(segment_at(100.0, t, 3), Some(1));
        assert_eq!(segment_at(299.0, t, 3), Some(2));
        assert_eq!(segment_at(-1.0, t, 3), None);
        assert_eq!(segment_at(301.0, t, 3), None);
        assert_eq!(segment_at(10.0, t, 0), None);
        assert_eq!(segment_at(f32::NAN, t, 3), None);
        // a zero-width track has no segments to hit
        assert_eq!(segment_at(0.0, track(0.0, 0.0), 3), None);
    }

    #[test]
    fn segment_rects_are_equal_slots_inset_from_each_other() {
        let t = track(20.0, 300.0);
        let r0 = segment_rect(t, 0, 3);
        let r1 = segment_rect(t, 1, 3);
        let r2 = segment_rect(t, 2, 3);
        for r in [r0, r1, r2] {
            assert!((r.width() - (100.0 - 2.0 * SEGMENT_INSET)).abs() < 0.01, "{r:?}");
            assert!(t.contains_rect(r), "{r:?} outside {t:?}");
        }
        // the ovals never touch: the inset leaves a gap between neighbouring segments
        assert!(r0.right() < r1.left());
        assert!(r1.right() < r2.left());
        assert_eq!(segment_rect(t, 3, 3), Rect::NOTHING);
        assert_eq!(segment_rect(t, 0, 0), Rect::NOTHING);
    }

    #[test]
    fn slider_value_and_position_round_trip() {
        let t = track(10.0, 200.0);
        let range = 0.0..=100.0;
        assert!((slider_x(0.0, t, &range) - 10.0).abs() < 0.01);
        assert!((slider_x(50.0, t, &range) - 110.0).abs() < 0.01);
        assert!((slider_x(100.0, t, &range) - 210.0).abs() < 0.01);
        for v in [0.0, 12.5, 50.0, 87.5, 100.0] {
            let x = slider_x(v, t, &range);
            assert!((slider_value_at(x, t, &range) - v).abs() < 0.01, "{v} -> {x}");
        }
        // a pointer outside the track clamps to its ends, never past the range
        assert_eq!(slider_value_at(-50.0, t, &range), 0.0);
        assert_eq!(slider_value_at(500.0, t, &range), 100.0);
        assert_eq!(slider_value_at(f32::NAN, t, &range), 0.0);
    }

    #[test]
    fn a_degenerate_range_stays_at_its_start() {
        let t = track(0.0, 200.0);
        let empty = 5.0..=5.0;
        assert_eq!(clamp_value(9.0, &empty), 5.0);
        assert_eq!(slider_value_at(120.0, t, &empty), 5.0);
        let reversed = 10.0..=0.0;
        assert_eq!(clamp_value(4.0, &reversed), 10.0);
        assert_eq!(clamp_value(f32::NAN, &reversed), 10.0);
        // an empty track cannot be mapped either
        assert_eq!(slider_value_at(3.0, track(0.0, 0.0), &(0.0..=1.0)), 0.0);
    }

    #[test]
    fn the_fill_spans_from_neutral_to_the_thumb_either_way() {
        assert_eq!(fill_span(70.0, 40.0), (40.0, 70.0));
        assert_eq!(fill_span(10.0, 40.0), (10.0, 40.0));
        assert_eq!(fill_span(40.0, 40.0), (40.0, 40.0));
    }

    #[test]
    fn the_glass_accent_is_the_design_blue() {
        let ctx = egui::Context::default();
        crate::theme::apply_kind(&ctx, ThemeKind::Glass);
        let t = Tokens::get(&ctx);
        assert_eq!(t.accent, Color32::from_rgb(0x0a, 0x84, 0xff));
        assert_eq!(SELECTED_BLUE, Color32::from_rgb(0x4a, 0xa3, 0xff));
    }

    #[test]
    fn the_kit_draws_nothing_outside_a_touch_layout() {
        let mut view = HeadlessView::new();
        let mut selected = 1usize;
        let mut rect = Rect::NOTHING;
        let raw = HeadlessView::raw_input(vec2(400.0, 300.0), 2.0, 0.0, vec![]);
        view.run(raw, |ui| {
            let r = segmented(ui, &["All", "Picked", "Rejected"], &mut selected);
            rect = r.rect;
            let b = capsule_button(ui, "Done", Kind::Primary);
            assert_eq!(b.rect.size(), egui::Vec2::ZERO);
        });
        assert_eq!(rect.size(), egui::Vec2::ZERO, "a desktop layout gets no segment track");
        assert_eq!(selected, 1, "and cannot change the selection");
    }

    #[test]
    fn tapping_a_segment_selects_it() {
        let mut view = HeadlessView::new();
        crate::theme::set_touch_ui(&view.ctx, true);
        crate::theme::apply_kind(&view.ctx, ThemeKind::Glass);
        let mut selected = 0usize;
        let track_rect = std::cell::Cell::new(Rect::NOTHING);
        let mut frame = 0u64;
        let mut lay_out = |view: &mut HeadlessView, selected: &mut usize, events: Vec<egui::Event>| {
            let raw = HeadlessView::raw_input(vec2(400.0, 300.0), 2.0, frame as f64 / 60.0, events);
            frame += 1;
            view.run(raw, |ui| {
                let r = segmented(ui, &["All", "Picked", "Rejected"], selected);
                track_rect.set(r.rect);
            });
        };
        lay_out(&mut view, &mut selected, vec![]);
        let t = track_rect.get();
        assert!(t.width() > 0.0, "the touch layout lays the track out");
        let at = segment_rect(t, 2, 3).center();
        lay_out(&mut view, &mut selected, vec![egui::Event::PointerMoved(at)]);
        lay_out(
            &mut view,
            &mut selected,
            vec![egui::Event::PointerButton { pos: at, button: egui::PointerButton::Primary, pressed: true, modifiers: egui::Modifiers::NONE }],
        );
        lay_out(
            &mut view,
            &mut selected,
            vec![egui::Event::PointerButton { pos: at, button: egui::PointerButton::Primary, pressed: false, modifiers: egui::Modifiers::NONE }],
        );
        assert_eq!(selected, 2, "a tap on the third segment selects it");
    }
}
