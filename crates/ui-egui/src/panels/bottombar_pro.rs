//! The desktop "Pro" status bar under the Library grid: how many photos are shown and selected, the
//! sort, background activity, and the thumbnail-size slider. Reached from `bottombar::show` only when
//! [`crate::theme::desktop_pro`] is on and a grid is showing.

use egui::{Align2, Color32, Rect, Sense, Stroke, pos2, vec2};

use super::chrome_pro::{self as pro, STATUS_H};
use crate::LightcraftApp;
use crate::icons::{Icon, paint};
use crate::state::{THUMB_SIZE_MAX, THUMB_SIZE_MIN};
use crate::theme::Tokens;
use crate::widgets::register;

/// `1248` → `1,248`.
pub fn thousands(n: usize) -> String {
    let digits = n.to_string();
    let mut out = String::with_capacity(digits.len() + digits.len() / 3);
    for (i, c) in digits.chars().enumerate() {
        if i > 0 && (digits.len() - i).is_multiple_of(3) {
            out.push(',');
        }
        out.push(c);
    }
    out
}

/// The sort in words: "Capture date, newest first".
pub fn sort_text(sort: lightcraft_catalog::Sort) -> String {
    use lightcraft_catalog::SortKey::*;
    let (name, up, down) = match sort.key {
        CaptureDate => ("Capture date", "oldest first", "newest first"),
        ImportDate => ("Added", "oldest first", "newest first"),
        EditDate => ("Modified", "oldest first", "newest first"),
        FileName => ("File name", "A to Z", "Z to A"),
        Rating => ("Rating", "lowest first", "highest first"),
        FileSize => ("File size", "smallest first", "largest first"),
        Random => return crate::i18n::tr("Sort: Random").to_string(),
    };
    format!("{} {}, {}", crate::i18n::tr("Sort:"), crate::i18n::tr(name), crate::i18n::tr(if sort.ascending { up } else { down }))
}

pub fn show(app: &mut LightcraftApp, ui: &mut egui::Ui) {
    let t = Tokens::get(ui.ctx());
    egui::Panel::bottom("bottom_bar")
        .exact_size(STATUS_H)
        .frame(egui::Frame::NONE.fill(t.chrome).inner_margin(egui::Margin { left: 12, right: 12, top: 0, bottom: 0 }))
        .show(ui, |ui| {
            let full = ui.max_rect();
            let cy = full.center().y;
            let bar = Rect::from_min_max(pos2(full.left() - 12.0, full.top()), pos2(full.right() + 12.0, full.bottom()));
            ui.painter().hline(bar.x_range(), bar.top() + 0.5, Stroke::new(1.0, t.divider));
            register(ui, "bar:status", bar);
            let shown = app.session.visible_shared().1.len();
            let total = app.session.source_total().unwrap_or(shown);
            let selected = app.session.selection.ids.len();

            // ---- right: thumbnail size
            let readout = format!("{} px", app.ui.thumb_size.round() as i32);
            let rw = pro::text_w(ui, "480 px", t.font(11.0));
            ui.painter().text(pos2(full.right(), cy), Align2::RIGHT_CENTER, &readout, t.font(11.0), t.text_dim);
            let big = Rect::from_center_size(pos2(full.right() - rw - 14.0, cy), vec2(14.0, 14.0));
            paint(ui.painter(), big, Icon::GridPhoto, t.icon);
            let track = Rect::from_min_size(pos2(big.left() - 10.0 - 120.0, cy - 8.0), vec2(120.0, 16.0));
            let small = Rect::from_center_size(pos2(track.left() - 10.0, cy), vec2(12.0, 12.0));
            paint(ui.painter(), small, Icon::GridSquare, t.icon);
            slider(app, ui, track, &t);
            let right_edge = small.left() - 12.0;

            // ---- left: counts and sort
            let font = t.font(11.0);
            let bold = t.semibold(11.0);
            let mut x = full.left();
            let put = |ui: &egui::Ui, text: &str, f: egui::FontId, col: Color32, x: &mut f32| {
                let r = ui.painter().text(pos2(*x, cy), Align2::LEFT_CENTER, text, f, col);
                *x = r.right();
            };
            put(ui, &thousands(shown), bold.clone(), t.text, &mut x);
            if total != shown {
                put(ui, &format!(" {} ", crate::i18n::tr("of")), font.clone(), t.text_dim, &mut x);
                put(ui, &thousands(total), bold.clone(), t.text, &mut x);
            }
            put(ui, &format!(" {}", crate::i18n::tr("photos")), font.clone(), t.text_dim, &mut x);
            x += 16.0;
            put(ui, &format!("{} ", crate::i18n::tr("Selected:")), font.clone(), t.text_dim, &mut x);
            put(ui, &selected.to_string(), bold.clone(), t.text, &mut x);
            x += 16.0;
            if x + 120.0 < right_edge {
                put(ui, &sort_text(app.session.sort), font.clone(), t.text_dim, &mut x);
            }
            // background work: the first task's name and progress
            if let Some(task) = app.session.activity.list().first() {
                let label = format!("{} {}", crate::i18n::tr(&task.label), super::activity::count_text(task));
                let w = pro::text_w(ui, &label, font.clone()) + 24.0;
                if x + 24.0 + w < right_edge {
                    let pr = pro::slot(x + 24.0, cy, w, 18.0);
                    ui.painter().rect_filled(pr, 9.0, pro::accent_bg(&t));
                    ui.painter().text(pr.center(), Align2::CENTER_CENTER, label, font, pro::accent_text(&t));
                    register(ui, "status:activity", pr);
                    ui.ctx().request_repaint();
                }
            }
        });
}

/// The 2 pt track with a 10 pt thumb; a click or drag sets `app.ui.thumb_size`.
fn slider(app: &mut LightcraftApp, ui: &mut egui::Ui, r: Rect, t: &Tokens) {
    let resp = ui.interact(r, egui::Id::unique("pro-thumb-size"), Sense::click_and_drag());
    register(ui, "slider:thumbSize", r);
    crate::widgets::announce(&resp, crate::i18n::tr("Thumbnail size"));
    let span = (r.width() - 10.0).max(1.0);
    if (resp.dragged() || resp.clicked())
        && let Some(p) = resp.interact_pointer_pos()
    {
        let f = ((p.x - r.left() - 5.0) / span).clamp(0.0, 1.0);
        app.ui.thumb_size = (THUMB_SIZE_MIN + f * (THUMB_SIZE_MAX - THUMB_SIZE_MIN)).round();
    }
    let f = ((app.ui.thumb_size - THUMB_SIZE_MIN) / (THUMB_SIZE_MAX - THUMB_SIZE_MIN)).clamp(0.0, 1.0);
    let cy = r.center().y;
    let tx = r.left() + 5.0 + f * span;
    let line = |from: f32, to: f32, col: Color32| {
        ui.painter().rect_filled(Rect::from_min_max(pos2(from, cy - 1.0), pos2(to, cy + 1.0)), 1.0, col);
    };
    line(r.left() + 5.0, r.right() - 5.0, t.track);
    line(r.left() + 5.0, tx, t.accent);
    ui.painter().circle_filled(pos2(tx, cy), if resp.hovered() || resp.dragged() { 6.0 } else { 5.0 }, Color32::WHITE);
}
