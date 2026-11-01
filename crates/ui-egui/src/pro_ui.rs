//! Small building blocks of the Pro desktop dialogs: collapsible sections with a one-line summary,
//! caps headings, shortcut chips, a switch, and the fuzzy matcher of the command palette.
//! Colours come from the theme [`Tokens`], so every theme gets the same structure.

use egui::{Align2, Color32, CornerRadius, Pos2, Rect, Response, RichText, Sense, Stroke, StrokeKind, Ui, vec2};

use crate::theme::Tokens;

/// Height of a section header row.
pub const HEADER_H: f32 = 30.0;

/// A small dim heading in capitals ("PLACEMENT", "SAVED WATERMARKS").
pub fn caps(ui: &mut Ui, text: &str) {
    let t = Tokens::get(ui.ctx());
    ui.label(RichText::new(crate::i18n::tr(text).to_uppercase()).size(10.5).color(t.text_dim));
}

/// A pill with `text` in `color` (status chips: "On", "New").
pub fn chip(ui: &mut Ui, text: &str, color: Color32) {
    let t = Tokens::get(ui.ctx());
    let galley = ui.painter().layout_no_wrap(text.to_string(), t.font(10.5), color);
    let (rect, _) = ui.allocate_exact_size(galley.size() + vec2(12.0, 4.0), Sense::hover());
    ui.painter().rect(rect, CornerRadius::same(8), color.gamma_multiply(0.16), Stroke::new(1.0, color.gamma_multiply(0.4)), StrokeKind::Inside);
    ui.painter().galley(rect.center() - galley.size() / 2.0, galley, color);
}

/// A keyboard shortcut as a raised key cap (`⌘K`, `Ctrl+Shift+E`).
pub fn key_cap(ui: &mut Ui, text: &str) -> Response {
    let t = Tokens::get(ui.ctx());
    let galley = ui.painter().layout_no_wrap(text.to_string(), t.font(11.0), t.text_label);
    let (rect, r) = ui.allocate_exact_size(galley.size() + vec2(10.0, 4.0), Sense::hover());
    ui.painter().rect(rect, CornerRadius::same(4), t.field, Stroke::new(1.0, t.button_border), StrokeKind::Inside);
    ui.painter().galley(rect.center() - galley.size() / 2.0, galley, t.text_label);
    r
}

/// A switch drawn at `rect`; `on` flips when `response` is clicked.
pub fn paint_switch(ui: &Ui, rect: Rect, on: bool, enabled: bool) {
    let t = Tokens::get(ui.ctx());
    let fill = if on { t.accent } else { t.track };
    let fill = if enabled { fill } else { fill.gamma_multiply(0.45) };
    ui.painter().rect_filled(rect, CornerRadius::same((rect.height() / 2.0) as u8), fill);
    let r = rect.height() / 2.0 - 2.0;
    let x = if on { rect.right() - r - 2.0 } else { rect.left() + r + 2.0 };
    ui.painter().circle_filled(Pos2::new(x, rect.center().y), r, Color32::WHITE);
}

/// A labelled switch row: returns the response; `value` flips on click or Space.
pub fn switch(ui: &mut Ui, id: &str, value: &mut bool, label: &str) -> Response {
    let t = Tokens::get(ui.ctx());
    let galley = ui.painter().layout_no_wrap(crate::i18n::tr(label).to_string(), t.font(13.0), t.text_label);
    let size = vec2(32.0 + 8.0 + galley.size().x, 22.0);
    let (rect, mut r) = ui.allocate_exact_size(size, Sense::click());
    if r.clicked() {
        *value = !*value;
        r.mark_changed();
    }
    crate::widgets::register(ui, format!("check:{id}"), rect);
    paint_switch(ui, Rect::from_min_size(rect.min + vec2(0.0, 3.0), vec2(32.0, 16.0)), *value, ui.is_enabled());
    ui.painter().galley(Pos2::new(rect.left() + 40.0, rect.center().y - galley.size().y / 2.0), galley, t.text_label);
    if r.has_focus() {
        ui.painter().rect_stroke(rect.expand(2.0), CornerRadius::same(4), Stroke::new(2.0, t.accent), StrokeKind::Outside);
    }
    r
}

fn open_id(id: &str) -> egui::Id {
    egui::Id::unique("lightcraft-pro-section").with(id)
}

/// Whether the section `id` is open now (`default_open` until the user changes it).
pub fn is_open(ctx: &egui::Context, id: &str, default_open: bool) -> bool {
    ctx.data(|d| d.get_temp::<bool>(open_id(id))).unwrap_or(default_open)
}

/// [`section`] in Pro; in Classic just `body` (the section's rows, with no header).
#[allow(clippy::too_many_arguments)]
pub fn section_if<R>(
    ui: &mut Ui,
    pro: bool,
    id: &str,
    title: &str,
    summary: &str,
    default_open: bool,
    toggle: Option<&mut bool>,
    body: impl FnOnce(&mut Ui) -> R,
) -> Option<R> {
    if pro { section(ui, id, title, summary, default_open, toggle, body) } else { Some(body(ui)) }
}

/// A collapsible section: a header (chevron, title, the one-line `summary` while collapsed, an
/// optional switch at the right) and, when open, its rows in a card. Click, Enter or Space on the
/// header toggles it, Left collapses and Right expands it. Returns what `body` returned when open.
pub fn section<R>(
    ui: &mut Ui,
    id: &str,
    title: &str,
    summary: &str,
    default_open: bool,
    mut toggle: Option<&mut bool>,
    body: impl FnOnce(&mut Ui) -> R,
) -> Option<R> {
    let t = Tokens::get(ui.ctx());
    let mut open = is_open(ui.ctx(), id, default_open);
    let (rect, resp) = ui.allocate_exact_size(vec2(ui.available_width(), HEADER_H), Sense::click());
    crate::widgets::register(ui, format!("section:{id}"), rect);
    let switch_rect = Rect::from_center_size(Pos2::new(rect.right() - 26.0, rect.center().y), vec2(32.0, 16.0));
    let mut flipped = false;
    if toggle.is_some() {
        let sr = ui.interact(switch_rect.expand2(vec2(4.0, 6.0)), egui::Id::unique("lightcraft-pro-section-switch").with(id), Sense::click());
        crate::widgets::register(ui, format!("check:{id}Switch"), switch_rect);
        if sr.clicked() {
            flipped = true;
        }
    }
    let mut toggled = resp.clicked() && !flipped;
    if resp.has_focus() {
        let (left, right, enter) = ui.input_mut(|i| {
            (
                i.consume_key(egui::Modifiers::NONE, egui::Key::ArrowLeft),
                i.consume_key(egui::Modifiers::NONE, egui::Key::ArrowRight),
                i.consume_key(egui::Modifiers::NONE, egui::Key::Enter) || i.consume_key(egui::Modifiers::NONE, egui::Key::Space),
            )
        });
        if left && open {
            open = false;
        } else if right && !open {
            open = true;
        }
        toggled |= enter;
    }
    if toggled {
        open = !open;
    }
    if flipped && let Some(v) = toggle.as_deref_mut() {
        *v = !*v;
        // turning a section on shows what it holds
        if *v {
            open = true;
        }
    }
    ui.data_mut(|d| d.insert_temp(open_id(id), open));
    let p = ui.painter();
    if resp.hovered() || resp.has_focus() {
        p.rect_filled(rect, CornerRadius::same(6), t.hover);
    }
    if resp.has_focus() {
        p.rect_stroke(rect, CornerRadius::same(6), Stroke::new(2.0, t.accent), StrokeKind::Inside);
    }
    // chevron: right when collapsed, down when open
    let c = Pos2::new(rect.left() + 14.0, rect.center().y);
    let pts = if open {
        [c + vec2(-4.0, -2.0), c + vec2(0.0, 2.5), c + vec2(4.0, -2.0)]
    } else {
        [c + vec2(-2.0, -4.0), c + vec2(2.5, 0.0), c + vec2(-2.0, 4.0)]
    };
    p.line_segment([pts[0], pts[1]], Stroke::new(1.6, t.text_label));
    p.line_segment([pts[1], pts[2]], Stroke::new(1.6, t.text_label));
    let title_galley = p.layout_no_wrap(crate::i18n::tr(title).to_string(), t.semibold(13.0), t.text);
    let tx = rect.left() + 28.0;
    let title_w = title_galley.size().x;
    p.galley(Pos2::new(tx, rect.center().y - title_galley.size().y / 2.0), title_galley, t.text);
    if let Some(v) = toggle.as_deref() {
        paint_switch(ui, switch_rect, *v, true);
        if *v {
            let g = ui.painter().layout_no_wrap("On".into(), t.font(10.5), Color32::from_rgb(52, 195, 143));
            let chip = Rect::from_min_size(Pos2::new(tx + title_w + 10.0, rect.center().y - 9.0), g.size() + vec2(12.0, 4.0));
            ui.painter().rect(
                chip,
                CornerRadius::same(8),
                Color32::from_rgb(52, 195, 143).gamma_multiply(0.16),
                Stroke::new(1.0, Color32::from_rgb(52, 195, 143).gamma_multiply(0.4)),
                StrokeKind::Inside,
            );
            ui.painter().galley(chip.center() - g.size() / 2.0, g, Color32::WHITE);
        }
    }
    if !open && !summary.is_empty() {
        let max_w = (switch_rect.left() - tx - title_w - 24.0).max(40.0);
        let mut job = egui::text::LayoutJob::single_section(summary.to_string(), egui::TextFormat::simple(t.font(11.5), t.text_dim));
        job.wrap = egui::text::TextWrapping { max_width: max_w, max_rows: 1, break_anywhere: true, overflow_character: Some('…') };
        let g = ui.painter().layout_job(job);
        ui.painter().galley(Pos2::new(tx + title_w + 12.0, rect.center().y - g.size().y / 2.0), g, t.text_dim);
    }
    if !open {
        return None;
    }
    let out = egui::Frame::NONE
        .fill(t.inset)
        .stroke(Stroke::new(1.0, t.divider))
        .corner_radius(CornerRadius::same(8))
        .inner_margin(egui::Margin::symmetric(12, 8))
        .show(ui, |ui| {
            ui.spacing_mut().item_spacing.y = 6.0;
            body(ui)
        })
        .inner;
    ui.add_space(6.0);
    Some(out)
}

/// A paint-only `text` right-aligned at the right edge of `rect` (palette rows).
pub fn paint_right(ui: &Ui, rect: Rect, text: &str, color: Color32) {
    let t = Tokens::get(ui.ctx());
    ui.painter().text(Pos2::new(rect.right() - 10.0, rect.center().y), Align2::RIGHT_CENTER, text, t.font(11.5), color);
}

/// Fuzzy match of `query` in `text`: every query letter must appear in order (case-insensitive).
/// Returns a score (higher is better: runs, word starts, early hits) and the matched character
/// positions in `text`, or `None` when it doesn't match. An empty query matches everything.
pub fn fuzzy(query: &str, text: &str) -> Option<(i32, Vec<usize>)> {
    let q: Vec<char> = query.chars().filter(|c| !c.is_whitespace()).flat_map(char::to_lowercase).collect();
    if q.is_empty() {
        return Some((0, Vec::new()));
    }
    let chars: Vec<char> = text.chars().collect();
    let lower: Vec<char> = chars.iter().map(|c| c.to_lowercase().next().unwrap_or(*c)).collect();
    // greedy from the left, then pull each hit as late as it can be while keeping runs together
    let mut pos = Vec::with_capacity(q.len());
    let mut from = 0;
    for qc in &q {
        let i = (from..lower.len()).find(|&i| lower.get(i) == Some(qc))?;
        pos.push(i);
        from = i + 1;
    }
    let mut score = 0i32;
    let mut prev: Option<usize> = None;
    for &i in &pos {
        score += 10;
        if let Some(p) = prev {
            if i == p + 1 {
                score += 15;
            } else {
                score -= (i - p - 1).min(8) as i32;
            }
        }
        let word_start = i == 0 || chars.get(i - 1).is_some_and(|c| !c.is_alphanumeric());
        if word_start {
            score += 12;
        }
        prev = Some(i);
    }
    score -= pos.first().copied().unwrap_or(0).min(20) as i32;
    // a whole-text prefix beats a scatter
    if lower.starts_with(&q) {
        score += 30;
    }
    Some((score, pos))
}

#[cfg(test)]
mod tests {
    use super::fuzzy;

    #[test]
    fn fuzzy_needs_letters_in_order_and_prefers_runs() {
        assert!(fuzzy("zzz", "Photo Grid").is_none());
        assert!(fuzzy("gp", "Photo Grid").is_none(), "letters must come in order");
        assert!(fuzzy("pg", "Photo Grid").is_some());
        let tight = fuzzy("grid", "Photo Grid").map(|r| r.0);
        let loose = fuzzy("grid", "Go Right In Detail").map(|r| r.0);
        assert!(tight > loose, "{tight:?} {loose:?}");
        assert_eq!(fuzzy("", "x").map(|r| r.1.len()), Some(0));
        assert_eq!(fuzzy("PG", "Photo Grid").map(|r| r.1), Some(vec![0, 6]));
    }
}
