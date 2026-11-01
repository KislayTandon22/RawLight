//! The Pro desktop Import dialog: three panes. Sources at the left, the thumbnail grid (with its
//! counts and file-type toggles) in the middle, the import options at the right in their own
//! scroll area. The grid and the options are the Classic review's (`crate::import`); only the
//! arrangement and the keyboard are new: Cmd/Ctrl+A checks all, Cmd/Ctrl+D none, Cmd/Ctrl+I inverts.

use egui::{Align, CornerRadius, Layout, RichText, Sense, Stroke, vec2};

use crate::LightcraftApp;
use crate::import::ImportDialog;
use crate::pro_ui;
use crate::theme::Tokens;

/// Width of the sources pane.
pub const SOURCES_W: f32 = 190.0;
/// Width of the options pane.
pub const OPTIONS_W: f32 = 340.0;

/// Check every importable photo, none, or the opposite of each (Cmd/Ctrl+A, +D, +I).
pub fn apply_selection_key(d: &mut ImportDialog, key: egui::Key) {
    let n = d.candidates.len();
    d.checked.resize(n, false);
    match key {
        egui::Key::A => (0..n).for_each(|i| d.checked[i] = d.checked_by_default(i)),
        egui::Key::D => d.checked.iter_mut().for_each(|c| *c = false),
        egui::Key::I => (0..n).for_each(|i| d.checked[i] = d.checked_by_default(i) && !d.checked[i]),
        _ => {}
    }
}

/// A short name for a source path: its last folder or file name.
pub fn source_name(path: &str) -> String {
    let trimmed = path.trim_end_matches(['/', '\\']);
    trimmed.rsplit(['/', '\\']).next().filter(|s| !s.is_empty()).unwrap_or(trimmed).to_string()
}

pub fn body(app: &mut LightcraftApp, ui: &mut egui::Ui, d: &mut ImportDialog) {
    let t = Tokens::get(ui.ctx());
    // the keyboard: no text field has it
    if !ui.ctx().egui_wants_keyboard_input() {
        for key in [egui::Key::A, egui::Key::D, egui::Key::I] {
            if ui.input_mut(|i| i.consume_key(egui::Modifiers::COMMAND, key)) {
                apply_selection_key(d, key);
            }
        }
    }
    let pane_h = (ui.ctx().content_rect().height() - 2.0 * 24.0 - 130.0).clamp(380.0, 640.0);
    ui.horizontal_top(|ui| {
        ui.spacing_mut().item_spacing.x = 14.0;
        ui.allocate_ui_with_layout(vec2(SOURCES_W, pane_h), Layout::top_down(Align::Min), |ui| {
            ui.set_width(SOURCES_W);
            sources(ui, &t, d);
        });
        let center = (ui.available_width() - OPTIONS_W - 14.0).max(320.0);
        ui.allocate_ui_with_layout(vec2(center, pane_h), Layout::top_down(Align::Min), |ui| {
            ui.set_width(center);
            crate::import::header_and_grid(app, ui, d, Some(pane_h - 64.0));
        });
        ui.allocate_ui_with_layout(vec2(OPTIONS_W, pane_h), Layout::top_down(Align::Min), |ui| {
            ui.set_width(OPTIONS_W);
            pro_ui::caps(ui, "Import options");
            egui::ScrollArea::vertical().id_salt("import-pro-options").max_height(pane_h - 20.0).auto_shrink([false, false]).show(ui, |ui| {
                ui.set_width(OPTIONS_W - 14.0);
                ui.spacing_mut().item_spacing.y = 6.0;
                crate::import::options(app, ui, d);
            });
        });
    });
}

fn sources(ui: &mut egui::Ui, t: &Tokens, d: &ImportDialog) {
    pro_ui::caps(ui, "Sources");
    ui.add_space(2.0);
    if d.sources.is_empty() {
        ui.label(RichText::new(crate::i18n::tr("Nothing to import from")).size(11.5).color(t.text_dim));
    }
    for (i, s) in d.sources.iter().enumerate() {
        let (rect, resp) = ui.allocate_exact_size(vec2(SOURCES_W, 44.0), Sense::hover());
        crate::widgets::register(ui, format!("label:importSource-{i}"), rect);
        ui.painter().rect(
            rect,
            CornerRadius::same(8),
            t.accent.gamma_multiply(0.14),
            Stroke::new(1.0, t.accent.gamma_multiply(0.5)),
            egui::StrokeKind::Inside,
        );
        ui.painter().text(rect.left_top() + vec2(10.0, 14.0), egui::Align2::LEFT_CENTER, source_name(s), t.semibold(13.0), t.text);
        let shown = crate::i18n::tr_format!("{} found", d.candidates.len());
        if i == 0 {
            ui.painter().text(rect.left_top() + vec2(10.0, 31.0), egui::Align2::LEFT_CENTER, shown, t.font(11.0), t.text_dim);
        }
        resp.on_hover_text(s);
        ui.add_space(4.0);
    }
    ui.add_space(8.0);
    pro_ui::caps(ui, "Keys");
    for (k, what) in [("A", "Check all"), ("D", "Check none"), ("I", "Invert")] {
        ui.horizontal(|ui| {
            pro_ui::key_cap(ui, &format!("{}{k}", if ui.ctx().os() == egui::os::OperatingSystem::Mac { "⌘" } else { "Ctrl+" }));
            ui.label(RichText::new(crate::i18n::tr(what)).size(11.5).color(t.text_dim));
        });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selection_keys_check_uncheck_and_invert() {
        let mut d = ImportDialog { candidates: vec![Default::default(); 4], checked: vec![true, false, false, true], ..Default::default() };
        apply_selection_key(&mut d, egui::Key::I);
        assert_eq!(d.checked, [false, true, true, false]);
        apply_selection_key(&mut d, egui::Key::D);
        assert_eq!(d.checked, [false; 4]);
        apply_selection_key(&mut d, egui::Key::A);
        assert_eq!(d.checked, [true; 4]);
    }

    #[test]
    fn source_names_are_the_last_part() {
        assert_eq!(source_name("/Volumes/EOS/DCIM/"), "DCIM");
        assert_eq!(source_name("C:\\Photos\\2026"), "2026");
        assert_eq!(source_name("/"), "");
    }
}
