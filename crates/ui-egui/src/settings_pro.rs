//! The Pro desktop Settings window: a left navigation (General, Appearance, Performance,
//! Shortcuts, Color & Display, then the other pages) and a dense page on the right. The pages are
//! the Classic Settings pages (`panels::settings`); Shortcuts is the keymap editor. Changes apply at
//! once, as in Classic; the footer button is "Done".

use egui::{Align2, CornerRadius, Pos2, RichText, Sense, Stroke, StrokeKind, vec2};

use crate::LightcraftApp;
use crate::pro_ui;
use crate::theme::Tokens;

/// (tab id, label) of the pages, in navigation order. The first five are the design's; the rest
/// are pages LightCraft has that the design doesn't show.
pub const PAGES: &[(&str, &str)] = &[
    ("general", "General"),
    ("interface", "Appearance"),
    ("performance", "Performance"),
    ("shortcuts", "Shortcuts"),
    ("display", "Color & Display"),
    ("import", "Import"),
    ("slideshow", "Slideshow"),
    ("faces", "Faces"),
    ("denoise", "AI Denoise"),
];

/// How many of [`PAGES`] come before the "More" heading.
const CORE: usize = 5;

/// Width of the left navigation.
pub const NAV_W: f32 = 184.0;
/// The Settings window's inner size (page area): never less than the design's 760x480 minimum.
pub const PAGE_W: f32 = 600.0;

/// The page after (`step` 1) or before (`step` -1) `tab`, wrapping.
pub fn step_page(tab: &str, step: i32) -> &'static str {
    let i = PAGES.iter().position(|(id, _)| *id == tab).unwrap_or(0) as i32;
    let n = PAGES.len() as i32;
    PAGES.get((i + step).rem_euclid(n) as usize).map_or("general", |p| p.0)
}

/// The tab a Cmd/Ctrl+digit selects (1..=5), if any.
pub fn page_for_digit(n: usize) -> Option<&'static str> {
    n.checked_sub(1).filter(|i| *i < CORE).and_then(|i| PAGES.get(i)).map(|p| p.0)
}

/// The Pro Settings content: navigation at the left, the page of `tab` at the right.
pub fn window(app: &mut LightcraftApp, ui: &mut egui::Ui, tab: &mut String, max_height: f32) {
    let t = Tokens::get(ui.ctx());
    let screen_w = ui.ctx().content_rect().width();
    let total_w = (screen_w - 64.0).clamp(480.0, NAV_W + PAGE_W + 18.0);
    ui.set_width(total_w);
    let h = (max_height - 8.0).clamp(300.0, 560.0);
    if !tab.is_empty() && !PAGES.iter().any(|(id, _)| id == tab) {
        *tab = "general".into();
    }
    // Cmd/Ctrl+1..5 pick a page while no text field has the keyboard
    if !ui.ctx().egui_wants_keyboard_input() {
        let keys = [egui::Key::Num1, egui::Key::Num2, egui::Key::Num3, egui::Key::Num4, egui::Key::Num5];
        for (n, key) in keys.iter().enumerate() {
            if ui.input_mut(|i| i.consume_key(egui::Modifiers::COMMAND, *key))
                && let Some(page) = page_for_digit(n + 1)
            {
                *tab = page.to_string();
            }
        }
    }
    ui.horizontal_top(|ui| {
        ui.spacing_mut().item_spacing.x = 14.0;
        ui.allocate_ui_with_layout(vec2(NAV_W, h), egui::Layout::top_down(egui::Align::Min), |ui| {
            ui.set_width(NAV_W);
            nav(ui, &t, tab);
        });
        // a hairline between navigation and page
        let x = ui.cursor().left() - 7.0;
        let top = ui.min_rect().top();
        ui.painter().line_segment([Pos2::new(x, top), Pos2::new(x, top + h)], Stroke::new(1.0, t.divider));
        let page_w = ui.available_width();
        ui.allocate_ui_with_layout(vec2(page_w, h), egui::Layout::top_down(egui::Align::Min), |ui| {
            ui.set_width(page_w);
            let title = PAGES.iter().find(|(id, _)| id == tab).map_or("Settings", |p| p.1);
            ui.label(RichText::new(crate::i18n::tr(title)).font(t.semibold(17.0)).color(t.text));
            ui.add_space(2.0);
            // denser than Classic: 26 pt controls, tighter rows
            ui.spacing_mut().item_spacing.y = 5.0;
            ui.spacing_mut().interact_size.y = 26.0;
            let tab_id = tab.clone();
            egui::ScrollArea::vertical()
                .id_salt(("settings-pro-page", tab_id.as_str()))
                .max_height(h - 34.0)
                .min_scrolled_height(h - 34.0)
                .auto_shrink([false, false])
                .show(ui, |ui| {
                    ui.add_space(2.0);
                    crate::panels::settings::body(app, ui, &tab_id);
                    crate::widgets::register(ui, "settings:page", ui.min_rect());
                });
        });
    });
}

fn nav(ui: &mut egui::Ui, t: &Tokens, tab: &mut String) {
    let mut rows: Vec<(usize, &'static str, &'static str)> = Vec::new();
    for (i, (id, label)) in PAGES.iter().enumerate() {
        rows.push((i, id, label));
    }
    let focus_after: std::cell::Cell<Option<usize>> = std::cell::Cell::new(None);
    for (i, id, label) in rows {
        if i == CORE {
            ui.add_space(8.0);
            pro_ui::caps(ui, "More");
            ui.add_space(2.0);
        }
        let (rect, resp) = ui.allocate_exact_size(vec2(NAV_W, 30.0), Sense::click());
        crate::widgets::register(ui, format!("button:settingsTab-{id}"), rect);
        let on = tab == id;
        if resp.clicked() {
            *tab = id.to_string();
        }
        if resp.has_focus() {
            let (down, up) = ui.input_mut(|inp| {
                (inp.consume_key(egui::Modifiers::NONE, egui::Key::ArrowDown), inp.consume_key(egui::Modifiers::NONE, egui::Key::ArrowUp))
            });
            if down || up {
                let next = step_page(id, if down { 1 } else { -1 });
                *tab = next.to_string();
                focus_after.set(PAGES.iter().position(|(p, _)| *p == next));
            }
        }
        let p = ui.painter();
        if on {
            p.rect_filled(rect, CornerRadius::same(7), t.accent.gamma_multiply(0.18));
        } else if resp.hovered() {
            p.rect_filled(rect, CornerRadius::same(7), t.hover);
        }
        if resp.has_focus() {
            p.rect_stroke(rect, CornerRadius::same(7), Stroke::new(2.0, t.accent), StrokeKind::Inside);
        }
        let color = if on { t.text } else { t.text_label };
        p.text(
            Pos2::new(rect.left() + 12.0, rect.center().y),
            Align2::LEFT_CENTER,
            crate::i18n::tr(label),
            if on { t.semibold(13.0) } else { t.font(13.0) },
            color,
        );
        if i < CORE {
            let hint = format!("{}{}", if ui.ctx().os() == egui::os::OperatingSystem::Mac { "⌘" } else { "Ctrl+" }, i + 1);
            ui.painter().text(Pos2::new(rect.right() - 10.0, rect.center().y), Align2::RIGHT_CENTER, hint, t.font(10.5), t.text_dim);
        }
        // remember the row ids so Up/Down can hand the focus on
        ui.ctx().data_mut(|d| d.insert_temp(egui::Id::unique("settings-pro-nav").with(i), resp.id));
    }
    if let Some(i) = focus_after.get()
        && let Some(id) = ui.ctx().data(|d| d.get_temp::<egui::Id>(egui::Id::unique("settings-pro-nav").with(i)))
    {
        ui.ctx().memory_mut(|m| m.request_focus(id));
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pages_cycle_and_digits_pick_the_core_five() {
        assert_eq!(step_page("general", 1), "interface");
        assert_eq!(step_page("general", -1), "denoise");
        assert_eq!(step_page("denoise", 1), "general");
        assert_eq!(page_for_digit(1), Some("general"));
        assert_eq!(page_for_digit(4), Some("shortcuts"));
        assert_eq!(page_for_digit(5), Some("display"));
        assert_eq!(page_for_digit(6), None);
        assert_eq!(page_for_digit(0), None);
    }
}
