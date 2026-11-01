//! The Pro desktop command palette (Cmd/Ctrl+Shift+K, Edit ▸ Command Palette…) and the keyboard
//! shortcut overlay (`?`). Both are overlays (not dialogs), drawn above the app and, for the
//! palette, above Settings; both only act when [`crate::theme::desktop_pro`] is on.
//!
//! The palette lists every command by label: the menu model ([`crate::menus::menu_entries`]) plus
//! every other bindable UI and engine command ([`crate::shortcuts::bindable`]) plus the Settings
//! pages. Typing fuzzy-filters (`>` commands only, `@` Settings pages, `#` presets), Up/Down
//! choose, Enter runs, Alt+Enter says where the command is in the menus, Esc closes.

use std::collections::HashSet;

use egui::{Align, Align2, Color32, CornerRadius, Layout, Pos2, Rect, RichText, Sense, Stroke, StrokeKind, vec2};
use serde_json::json;

use crate::LightcraftApp;
use crate::pro_ui;
use crate::state::Dialog;
use crate::theme::Tokens;

/// The palette's default shortcut. Cmd/Ctrl+K (the design's choice) is Add Keywords and
/// Cmd/Ctrl+Shift+P is Create Preset; neither is taken over.
pub const SHORTCUT: &str = "Cmd+Shift+K";

/// What running an entry does.
#[derive(Clone, Debug, PartialEq)]
pub enum Kind {
    /// A UI or engine command, run through the menu path.
    Command,
    /// A Help menu item.
    Help,
    /// A Settings page (its tab id).
    Settings(&'static str),
}

/// One row of the palette.
#[derive(Clone, Debug)]
pub struct Entry {
    pub id: String,
    pub label: String,
    /// `File › Export…`, or empty for a command with no menu item.
    pub path: String,
    pub shortcut: Option<String>,
    pub enabled: bool,
    pub kind: Kind,
}

/// The open palette.
#[derive(Clone, Debug, Default)]
pub struct PaletteState {
    pub query: String,
    pub selected: usize,
    entries: Vec<Entry>,
    /// The selection moved by key since the last frame: scroll it into view.
    moved: bool,
}

impl PaletteState {
    pub fn new(app: &LightcraftApp) -> Self {
        PaletteState { entries: entries(app), ..Default::default() }
    }
}

/// Every command the palette can run, by label.
pub fn entries(app: &LightcraftApp) -> Vec<Entry> {
    let mut seen: HashSet<String> = HashSet::new();
    let mut out: Vec<Entry> = Vec::new();
    for e in crate::menus::menu_entries(app) {
        if !seen.insert(e.id.clone()) {
            continue;
        }
        let kind = if e.menu.first().map(String::as_str) == Some("Help") { Kind::Help } else { Kind::Command };
        out.push(Entry { path: e.menu.join(" › "), id: e.id, label: e.label, shortcut: e.shortcut, enabled: e.enabled, kind });
    }
    let engine: std::collections::HashMap<&str, bool> = app.session.commands().iter().map(|c| (c.id, c.enabled)).collect();
    for b in crate::shortcuts::bindable() {
        if !seen.insert(b.id.to_string()) || b.label.is_empty() {
            continue;
        }
        let enabled = engine.get(b.id).copied().unwrap_or_else(|| crate::menus::ui_enabled(app, b.id));
        let shortcut = crate::shortcuts::binding(&app.ui.settings.keymap, b.id, b.default).map(str::to_string);
        out.push(Entry { id: b.id.to_string(), label: b.label.to_string(), path: String::new(), shortcut, enabled, kind: Kind::Command });
    }
    for (tab, label) in crate::settings_pro::PAGES {
        out.push(Entry {
            id: format!("settings:{tab}"),
            label: format!("Settings: {label}"),
            path: "Settings".into(),
            shortcut: None,
            enabled: true,
            kind: Kind::Settings(tab),
        });
    }
    out
}

/// A scored result: index into the entries and the matched character positions in its label.
pub type Hit = (usize, i32, Vec<usize>);

/// The entries `query` selects, best first. `>` keeps commands, `@` Settings pages, `#` presets.
pub fn search(entries: &[Entry], query: &str) -> Vec<Hit> {
    let (mode, q) = match query.chars().next() {
        Some(c @ ('>' | '@' | '#')) => (Some(c), query.get(1..).unwrap_or("")),
        _ => (None, query),
    };
    let mut hits: Vec<Hit> = entries
        .iter()
        .enumerate()
        .filter(|(_, e)| match mode {
            Some('>') => matches!(e.kind, Kind::Command | Kind::Help),
            Some('@') => matches!(e.kind, Kind::Settings(_)),
            Some('#') => e.label.to_lowercase().contains("preset"),
            _ => true,
        })
        .filter_map(|(i, e)| {
            let label = crate::i18n::tr(&e.label);
            if let Some((score, pos)) = pro_ui::fuzzy(q, label) {
                // among equal matches the shorter label is the nearer one
                return Some((i, score + 10 - (label.chars().count() as i32 / 3).min(12), pos));
            }
            // the menu path matches too, less strongly, with no letters to mark
            pro_ui::fuzzy(q, &e.path).map(|(score, _)| (i, score - 20, Vec::new()))
        })
        .collect();
    if q.trim().is_empty() {
        // nothing typed: commands that have shortcuts first, in menu order
        hits.sort_by_key(|(i, _, _)| (entries.get(*i).is_none_or(|e| e.shortcut.is_none()), *i));
    } else {
        hits.sort_by(|a, b| b.1.cmp(&a.1).then(a.0.cmp(&b.0)));
    }
    hits.truncate(80);
    hits
}

/// Run the entry `e`: a command through the menu path, a Settings page by opening it.
pub fn run(app: &mut LightcraftApp, ctx: &egui::Context, e: &Entry) -> Result<(), String> {
    if !e.enabled {
        return Err(crate::i18n::tr("That command isn't available right now").to_string());
    }
    match &e.kind {
        Kind::Settings(tab) => {
            app.ui.dialog = Some(Dialog::Settings { tab: (*tab).to_string() });
            Ok(())
        }
        Kind::Command | Kind::Help => {
            let r = crate::menubar::run_item(app, &e.id, json!({}));
            ctx.request_repaint();
            r.map(|_| ())
        }
    }
}

/// Open the palette (Pro only; the Classic layout has none).
pub fn open(app: &mut LightcraftApp) {
    if app.ui.settings.desktop_layout == crate::state::DesktopLayout::Pro {
        app.ui.shortcut_overlay = false;
        app.ui.palette = Some(PaletteState::new(app));
    }
}

/// Show or hide the shortcut overlay (Pro only).
pub fn toggle_overlay(app: &mut LightcraftApp) {
    if app.ui.settings.desktop_layout == crate::state::DesktopLayout::Pro {
        app.ui.palette = None;
        app.ui.shortcut_overlay = !app.ui.shortcut_overlay;
    }
}

/// The keys the overlays own: `?` (when no text field has the keyboard and no dialog is open) and
/// the palette's shortcut while Settings is open (other dialogs are modal and refuse it).
pub fn handle_keys(app: &mut LightcraftApp, ctx: &egui::Context) {
    if !crate::theme::desktop_pro(ctx) {
        app.ui.palette = None;
        app.ui.shortcut_overlay = false;
        return;
    }
    let settings_open = matches!(app.ui.dialog, Some(Dialog::Settings { .. }));
    if settings_open
        && let Some(sc) = crate::shortcuts::binding(&app.ui.settings.keymap, "app.palette", Some(SHORTCUT))
        && let Some((m, k)) = crate::shortcuts::parse(sc)
        && ctx.input_mut(|i| i.consume_key(m, k))
    {
        open(app);
    }
    if app.ui.dialog.is_none() || app.ui.shortcut_overlay {
        let typed_q = ctx.input(|i| i.events.iter().any(|e| matches!(e, egui::Event::Text(t) if t == "?")));
        if typed_q && (!ctx.egui_wants_keyboard_input() || app.ui.shortcut_overlay) && app.ui.palette.is_none() {
            toggle_overlay(app);
        }
    }
}

fn highlighted(label: &str, pos: &[usize], base: Color32, hi: Color32, font: egui::FontId) -> egui::text::LayoutJob {
    let mut job = egui::text::LayoutJob::default();
    for (i, ch) in label.chars().enumerate() {
        let c = if pos.contains(&i) { hi } else { base };
        job.append(&ch.to_string(), 0.0, egui::TextFormat::simple(font.clone(), c));
    }
    job
}

fn glass(t: &Tokens) -> egui::Frame {
    egui::Frame::NONE
        .fill(t.chrome.gamma_multiply(0.97))
        .stroke(Stroke::new(1.0, t.button_border))
        .corner_radius(CornerRadius::same(12))
        .shadow(egui::epaint::Shadow { offset: [0, 12], blur: 36, spread: 0, color: Color32::from_black_alpha(130) })
}

/// Draw whichever overlay is open. Called once per frame after the dialogs.
pub fn show(app: &mut LightcraftApp, ctx: &egui::Context) {
    if !crate::theme::desktop_pro(ctx) {
        return;
    }
    // the palette is blocked by modal dialogs except Settings
    if app.ui.palette.is_some() && app.ui.dialog.as_ref().is_some_and(|d| !matches!(d, Dialog::Settings { .. })) {
        app.ui.palette = None;
    }
    if app.ui.palette.is_some() {
        show_palette(app, ctx);
    } else if app.ui.shortcut_overlay {
        show_overlay(app, ctx);
    }
}

fn show_palette(app: &mut LightcraftApp, ctx: &egui::Context) {
    let Some(mut st) = app.ui.palette.take() else { return };
    let t = Tokens::get(ctx);
    let mac = ctx.os() == egui::os::OperatingSystem::Mac;
    let screen = ctx.content_rect();
    let hits = search(&st.entries, &st.query);
    st.selected = st.selected.min(hits.len().saturating_sub(1));
    // keys first, so a key meant for the list never reaches the text field
    let (down, up, enter, alt_enter, esc) = ctx.input_mut(|i| {
        (
            i.consume_key(egui::Modifiers::NONE, egui::Key::ArrowDown),
            i.consume_key(egui::Modifiers::NONE, egui::Key::ArrowUp),
            i.consume_key(egui::Modifiers::NONE, egui::Key::Enter),
            i.consume_key(egui::Modifiers::ALT, egui::Key::Enter),
            i.consume_key(egui::Modifiers::NONE, egui::Key::Escape),
        )
    });
    if down && !hits.is_empty() {
        st.selected = (st.selected + 1) % hits.len();
        st.moved = true;
    }
    if up && !hits.is_empty() {
        st.selected = (st.selected + hits.len() - 1) % hits.len();
        st.moved = true;
    }
    let mut close = esc;
    let mut run_entry: Option<usize> = None;
    let mut reveal: Option<usize> = None;
    if enter {
        run_entry = hits.get(st.selected).map(|h| h.0);
    }
    if alt_enter {
        reveal = hits.get(st.selected).map(|h| h.0);
    }
    // a click outside closes
    egui::Area::new(egui::Id::unique("palette-scrim")).order(egui::Order::Foreground).fixed_pos(screen.min).show(ctx, |ui| {
        let r = ui.allocate_rect(screen, Sense::click());
        ui.painter().rect_filled(screen, 0.0, Color32::from_black_alpha(90));
        if r.clicked() {
            close = true;
        }
    });
    let width = 620.0_f32.min(screen.width() - 32.0);
    egui::Area::new(egui::Id::unique("palette-panel"))
        .order(egui::Order::Tooltip)
        .anchor(Align2::CENTER_TOP, [0.0, (screen.height() * 0.14).max(40.0)])
        .show(ctx, |ui| {
            glass(&t).show(ui, |ui| {
                ui.set_width(width);
                ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
                // the 48 px input
                ui.allocate_ui_with_layout(vec2(width, 48.0), Layout::left_to_right(Align::Center), |ui| {
                    ui.add_space(16.0);
                    let r = ui.add(
                        egui::TextEdit::singleline(&mut st.query)
                            .frame(egui::Frame::NONE)
                            .font(t.font(16.0))
                            .hint_text(crate::i18n::tr("Type a command, or > commands  @ settings  # presets"))
                            .desired_width(width - 32.0),
                    );
                    crate::widgets::register(ui, "field:paletteInput", r.rect);
                    r.request_focus();
                    if r.changed() {
                        st.selected = 0;
                        st.moved = true;
                    }
                });
                let (line, _) = ui.allocate_exact_size(vec2(width, 1.0), Sense::hover());
                ui.painter().rect_filled(line, 0.0, t.divider);
                let list_h = (screen.height() * 0.5).clamp(200.0, 420.0);
                egui::ScrollArea::vertical().id_salt("palette-list").max_height(list_h).auto_shrink([false, true]).show(ui, |ui| {
                    ui.set_width(width);
                    let mut last_group = "";
                    if hits.is_empty() {
                        ui.add_space(14.0);
                        ui.label(RichText::new(crate::i18n::tr("No matching commands")).color(t.text_dim));
                        ui.add_space(14.0);
                    }
                    for (rank, (idx, _, pos)) in hits.iter().enumerate() {
                        let Some(e) = st.entries.get(*idx) else { continue };
                        let group = if st.query.trim().is_empty() {
                            if e.shortcut.is_some() { "Suggested" } else { "Commands" }
                        } else if rank < 6 {
                            "Best match"
                        } else if matches!(e.kind, Kind::Settings(_) | Kind::Help) {
                            "Settings & help"
                        } else {
                            "Commands"
                        };
                        if group != last_group {
                            last_group = group;
                            ui.add_space(6.0);
                            ui.horizontal(|ui| {
                                ui.add_space(16.0);
                                pro_ui::caps(ui, group);
                            });
                            ui.add_space(2.0);
                        }
                        let (rect, resp) = ui.allocate_exact_size(vec2(width, 34.0), Sense::click());
                        crate::widgets::register(ui, format!("palette:row-{rank}"), rect);
                        let sel = rank == st.selected;
                        if resp.hovered() && ui.input(|i| i.pointer.delta() != egui::Vec2::ZERO) {
                            st.selected = rank;
                        }
                        if sel {
                            ui.painter().rect_filled(rect.shrink2(vec2(6.0, 1.0)), CornerRadius::same(7), t.accent.gamma_multiply(0.22));
                            if st.moved {
                                resp.scroll_to_me(None);
                            }
                        }
                        let base = if e.enabled { t.text } else { t.text_disabled };
                        let label = crate::i18n::tr(&e.label);
                        let job = highlighted(label, pos, base, t.accent, t.font(13.5));
                        let g = ui.painter().layout_job(job);
                        ui.painter().galley(Pos2::new(rect.left() + 18.0, rect.center().y - g.size().y / 2.0), g, base);
                        match &e.shortcut {
                            Some(sc) => {
                                let text = crate::menubar::shortcut_text(sc, mac);
                                let gal = ui.painter().layout_no_wrap(text, t.font(11.0), t.text_label);
                                let cap = Rect::from_center_size(
                                    Pos2::new(rect.right() - 18.0 - gal.size().x / 2.0 - 5.0, rect.center().y),
                                    gal.size() + vec2(10.0, 4.0),
                                );
                                ui.painter().rect(cap, CornerRadius::same(4), t.field, Stroke::new(1.0, t.button_border), StrokeKind::Inside);
                                ui.painter().galley(cap.center() - gal.size() / 2.0, gal, t.text_label);
                            }
                            None if !e.path.is_empty() => {
                                let r = Rect::from_min_max(rect.min, rect.max - vec2(8.0, 0.0));
                                pro_ui::paint_right(ui, r, &e.path, t.text_dim);
                            }
                            None => {}
                        }
                        if !e.enabled {
                            resp.clone().on_hover_text(crate::i18n::tr("That command isn't available right now"));
                        }
                        if resp.clicked() {
                            run_entry = Some(*idx);
                        }
                    }
                });
                st.moved = false;
                let (foot, _) = ui.allocate_exact_size(vec2(width, 28.0), Sense::hover());
                let hint = format!(
                    "↑↓ {}    ↵ {}    {} {}    esc {}",
                    crate::i18n::tr("choose"),
                    crate::i18n::tr("run"),
                    if mac { "⌥↵" } else { "Alt+↵" },
                    crate::i18n::tr("show in menu"),
                    crate::i18n::tr("close")
                );
                ui.painter().text(foot.left_center() + vec2(16.0, 0.0), Align2::LEFT_CENTER, hint, t.font(11.0), t.text_dim);
            });
        });
    if let Some(idx) = reveal.and_then(|i| st.entries.get(i).cloned()) {
        let msg = if idx.path.is_empty() {
            crate::i18n::tr_format!("{} has no menu item", crate::i18n::tr(&idx.label))
        } else {
            format!("{}: {}", crate::i18n::tr(&idx.label), idx.path)
        };
        app.toast(ctx, msg);
    }
    if let Some(idx) = run_entry
        && let Some(e) = st.entries.get(idx).cloned()
    {
        if e.enabled {
            close = true;
            if let Err(err) = run(app, ctx, &e) {
                app.toast(ctx, err);
            }
        } else {
            app.toast(ctx, crate::i18n::tr("That command isn't available right now"));
        }
    }
    // the command may have opened something that replaced the palette (the shortcut overlay)
    if !close && app.ui.palette.is_none() {
        app.ui.palette = Some(st);
    }
}

/// A group of the overlay: the menu title and (label, shortcut) rows.
pub fn overlay_groups(app: &LightcraftApp, enabled_only: bool) -> Vec<(String, Vec<(String, String)>)> {
    let mut groups: Vec<(String, Vec<(String, String)>)> = Vec::new();
    for e in entries(app) {
        let Some(sc) = e.shortcut.clone() else { continue };
        if !matches!(e.kind, Kind::Command | Kind::Help) || (enabled_only && !e.enabled) {
            continue;
        }
        let title = e.path.split(" › ").next().filter(|s| !s.is_empty()).unwrap_or("Other").to_string();
        match groups.iter_mut().find(|(g, _)| *g == title) {
            Some((_, rows)) => rows.push((e.label, sc)),
            None => groups.push((title, vec![(e.label, sc)])),
        }
    }
    let order = |g: &str| crate::menubar::MENUS.iter().position(|m| *m == g).unwrap_or(usize::MAX - 1);
    groups.sort_by_key(|(g, _)| order(g));
    groups
}

fn show_overlay(app: &mut LightcraftApp, ctx: &egui::Context) {
    let t = Tokens::get(ctx);
    let mac = ctx.os() == egui::os::OperatingSystem::Mac;
    let screen = ctx.content_rect();
    let esc = ctx.input_mut(|i| i.consume_key(egui::Modifiers::NONE, egui::Key::Escape));
    let mut close = esc;
    let mode_id = egui::Id::unique("shortcut-overlay-all");
    let mut all: bool = ctx.data(|d| d.get_temp(mode_id)).unwrap_or(true);
    let groups = overlay_groups(app, !all);
    egui::Area::new(egui::Id::unique("overlay-scrim")).order(egui::Order::Foreground).fixed_pos(screen.min).show(ctx, |ui| {
        let r = ui.allocate_rect(screen, Sense::click());
        ui.painter().rect_filled(screen, 0.0, Color32::from_black_alpha(110));
        if r.clicked() {
            close = true;
        }
    });
    let width = 940.0_f32.min(screen.width() - 32.0);
    let height = (screen.height() - 120.0).clamp(300.0, 620.0);
    egui::Area::new(egui::Id::unique("overlay-panel")).order(egui::Order::Tooltip).anchor(Align2::CENTER_CENTER, [0.0, 0.0]).show(ctx, |ui| {
        glass(&t).inner_margin(egui::Margin::symmetric(22, 16)).show(ui, |ui| {
            ui.set_width(width - 44.0);
            ui.horizontal(|ui| {
                ui.label(RichText::new(crate::i18n::tr("Keyboard shortcuts")).font(t.semibold(16.0)).color(t.text));
                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                    if crate::widgets::text_button(ui, "overlayThisView", "This view", !all).clicked() {
                        all = false;
                    }
                    if crate::widgets::text_button(ui, "overlayEverything", "Everything", all).clicked() {
                        all = true;
                    }
                });
            });
            ui.add_space(6.0);
            ui.separator();
            ui.add_space(6.0);
            egui::ScrollArea::vertical().id_salt("overlay-scroll").max_height(height - 90.0).auto_shrink([false, true]).show(ui, |ui| {
                // each group goes to the shortest column so far
                let mut heights = [0usize; 3];
                let mut which: Vec<usize> = Vec::new();
                for (_, rows) in &groups {
                    let c = (0..3).min_by_key(|c| heights[*c]).unwrap_or(0);
                    heights[c] += rows.len() + 2;
                    which.push(c);
                }
                ui.columns(3, |cols| {
                    for (n, (title, rows)) in groups.iter().enumerate() {
                        let Some(col) = cols.get_mut(which.get(n).copied().unwrap_or(0)) else { continue };
                        col.add_space(8.0);
                        pro_ui::caps(col, title);
                        col.add_space(2.0);
                        for (label, sc) in rows {
                            col.horizontal(|ui| {
                                ui.label(RichText::new(crate::i18n::tr(label)).size(12.5).color(t.text_label));
                                ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
                                    pro_ui::key_cap(ui, &crate::menubar::shortcut_text(sc, mac));
                                });
                            });
                        }
                    }
                });
            });
            ui.add_space(6.0);
            ui.label(RichText::new(crate::i18n::tr("Press ? or Esc to close")).size(11.0).color(t.text_dim));
        });
    });
    ctx.data_mut(|d| d.insert_temp(mode_id, all));
    if close {
        app.ui.shortcut_overlay = false;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: &str, label: &str, enabled: bool) -> Entry {
        Entry { id: id.into(), label: label.into(), path: String::new(), shortcut: None, enabled, kind: Kind::Command }
    }

    #[test]
    fn search_filters_and_ranks_by_fuzzy_label() {
        let es = vec![
            entry("a", "Photo Grid", true),
            entry("b", "Square Grid", true),
            entry("c", "Export…", true),
            entry("d", "Go Right In Detail", true),
        ];
        let hits = search(&es, "grid");
        let ids: Vec<&str> = hits.iter().map(|h| es[h.0].id.as_str()).collect();
        assert_eq!(ids.len(), 3, "{ids:?}");
        assert!(ids.contains(&"a") && ids.contains(&"b") && ids.contains(&"d"));
        assert!(search(&es, "zzzz").is_empty());
        assert_eq!(es[search(&es, "exp")[0].0].id, "c");
        assert_eq!(search(&es, "").len(), 4, "nothing typed lists everything");
    }

    #[test]
    fn prefixes_pick_a_kind_of_entry() {
        let mut es = vec![entry("a", "Export…", true), entry("b", "Settings: General", true), entry("c", "Create Preset…", true)];
        es[1].kind = Kind::Settings("general");
        let ids = |q: &str| search(&es, q).iter().map(|h| es[h.0].id.clone()).collect::<Vec<_>>();
        assert_eq!(ids("@"), ["b"]);
        assert_eq!(ids(">"), ["a", "c"]);
        assert_eq!(ids("#"), ["c"]);
        assert_eq!(ids("@gen"), ["b"]);
    }
}
