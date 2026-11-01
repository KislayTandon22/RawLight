//! The Pro desktop layout's left dock in the Develop workspace: Navigator, Presets, Snapshots and History as
//! collapsible cards. The Library sidebar (`left.rs`) is shown in every other view.

use egui::{Align2, Color32, CornerRadius, Rect, Sense, Ui, pos2, vec2};
use lightcraft_catalog::PhotoId;
use serde_json::json;

use super::ui_pro::{self, Pal};
use crate::LightcraftApp;
use crate::icons::Icon;
use crate::render::Slot;
use crate::state::Zoom;
use crate::theme::Tokens;

/// The cards, top to bottom.
pub const CARDS: [(&str, &str); 4] = [("navigator", "Navigator"), ("presets", "Presets"), ("snapshots", "Snapshots"), ("history", "History")];

fn card_open(ui: &Ui, id: &str, default: bool) -> bool {
    ui.data(|d| d.get_temp::<bool>(egui::Id::unique(("pro-left-card", id)))).unwrap_or(default)
}

pub fn show(app: &mut LightcraftApp, ui: &mut Ui, photo: PhotoId) {
    let pal = Pal::get(ui.ctx());
    egui::Frame::NONE.fill(egui::Color32::TRANSPARENT).inner_margin(egui::Margin::same(6)).show(ui, |ui| {
        ui.spacing_mut().item_spacing.y = 6.0;
        egui::ScrollArea::vertical().id_salt("pro-left-scroll").auto_shrink([false, false]).show(ui, |ui| {
            ui.spacing_mut().item_spacing.y = 6.0;
            for (id, title) in CARDS {
                let default_open = id != "presets";
                let open = card_open(ui, id, default_open);
                let mut now_open = open;
                egui::Frame::NONE.fill(pal.glass).stroke(egui::Stroke::new(1.0, pal.rim2)).corner_radius(CornerRadius::same(ui_pro::CARD_R)).show(
                    ui,
                    |ui| {
                        ui.spacing_mut().item_spacing.y = 0.0;
                        let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), 28.0), Sense::click());
                        crate::widgets::announce_disclosure(&resp, true, open, crate::i18n::tr(title));
                        crate::widgets::register(ui, format!("leftCard:{id}"), r);
                        let t = Tokens::get(ui.ctx());
                        crate::icons::paint(
                            ui.painter(),
                            Rect::from_center_size(pos2(r.left() + 14.0, r.center().y), vec2(12.0, 12.0)),
                            if open { Icon::ChevronDown } else { Icon::ChevronRight },
                            pal.text2,
                        );
                        ui.painter().text(
                            pos2(r.left() + 28.0, r.center().y),
                            Align2::LEFT_CENTER,
                            crate::i18n::tr(title).to_uppercase(),
                            t.semibold(10.5),
                            pal.text2,
                        );
                        if resp.clicked() {
                            now_open = !open;
                        }
                        if open {
                            match id {
                                "navigator" => navigator(app, ui, photo),
                                "presets" => presets(app, ui),
                                "snapshots" => snapshots(app, ui, photo),
                                _ => history(app, ui, photo),
                            }
                            ui.add_space(6.0);
                        }
                    },
                );
                if now_open != open {
                    ui.data_mut(|d| d.insert_temp(egui::Id::unique(("pro-left-card", id)), now_open));
                }
            }
        });
    });
}

fn navigator(app: &mut LightcraftApp, ui: &mut Ui, photo: PhotoId) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let w = ui.available_width() - 16.0;
    let aspect = app.session.catalog.photo(photo).map_or(1.5, |p| (p.width.max(1) as f32 / p.height.max(1) as f32).clamp(0.3, 4.0));
    let h = (w / aspect).clamp(40.0, 140.0);
    let (outer, _) = ui.allocate_exact_size(vec2(ui.available_width(), h + 8.0), Sense::hover());
    let r = Rect::from_center_size(outer.center(), vec2((h * aspect).min(w), h));
    crate::widgets::register(ui, "navigator", r);
    ui.painter().rect_filled(r, CornerRadius::same(4), Color32::from_black_alpha(100));
    if let Some(tex) = app.renderer.textures.get(&Slot::Main).filter(|x| x.photo == photo) {
        ui.painter().image(tex.tex.id(), r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
    } else if let Some(tex) = app.renderer.textures.get(&Slot::Thumb(photo)) {
        ui.painter().image(tex.tex.id(), r, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
    }
    ui.painter().rect_stroke(r, CornerRadius::same(4), egui::Stroke::new(1.5, pal.accent), egui::StrokeKind::Inside);
    ui.horizontal(|ui| {
        ui.add_space(8.0);
        ui.spacing_mut().item_spacing.x = 6.0;
        let z = app.ui.zoom;
        for (id, label, active, cmd) in
            [("navFit", "Fit", z == Zoom::Fit, "view.zoomFit"), ("nav100", "100%", z == Zoom::Percent(100.0), "view.zoom100")]
        {
            if ui_pro::chip(ui, id, label, active).clicked() {
                let _ = app.run(cmd, json!({}));
            }
        }
        let _ = &t;
    });
}

fn presets(app: &mut LightcraftApp, ui: &mut Ui) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let list: Vec<(String, String, bool)> =
        app.session.presets.iter().filter(|p| p.favorite || p.builtin).take(40).map(|p| (p.id.clone(), p.name.clone(), p.favorite)).collect();
    if list.is_empty() {
        ui.horizontal(|ui| {
            ui.add_space(14.0);
            ui.label(egui::RichText::new(crate::i18n::tr("No presets")).size(11.0).color(pal.text3));
        });
        return;
    }
    for (id, name, fav) in list {
        let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), 22.0), Sense::click());
        crate::widgets::register(ui, format!("proPreset:{id}"), r);
        crate::widgets::announce(&resp, name.clone());
        if resp.hovered() {
            ui.painter().rect_filled(r.shrink2(vec2(6.0, 0.0)), CornerRadius::same(6), pal.field_h);
        }
        ui.painter().text(pos2(r.left() + 14.0, r.center().y), Align2::LEFT_CENTER, &name, t.font(11.5), pal.text);
        if fav {
            ui.painter().text(
                pos2(r.right() - 14.0, r.center().y),
                Align2::CENTER_CENTER,
                "\u{2605}",
                t.font(11.0),
                Color32::from_rgb(0xF2, 0xC1, 0x4E),
            );
        }
        if resp.clicked() {
            let _ = app.run("preset.apply", json!({"id": id, "amount": 100}));
        }
    }
}

fn snapshots(app: &mut LightcraftApp, ui: &mut Ui, photo: PhotoId) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let Some(p) = app.session.catalog.photo(photo).cloned() else { return };
    let rows: Vec<(usize, String, bool)> =
        p.versions.iter().enumerate().rev().filter(|(_, v)| !v.auto).map(|(i, v)| (i, v.name.clone(), *v.settings == *p.develop)).collect();
    if rows.is_empty() {
        ui.horizontal(|ui| {
            ui.add_space(14.0);
            ui.label(egui::RichText::new(crate::i18n::tr("No snapshots yet")).size(11.0).color(pal.text3));
        });
    }
    for (i, name, current) in rows {
        let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), 22.0), Sense::click());
        crate::widgets::register(ui, format!("proSnapshot:{i}"), r);
        crate::widgets::announce(&resp, name.clone());
        if resp.hovered() {
            ui.painter().rect_filled(r.shrink2(vec2(6.0, 0.0)), CornerRadius::same(6), pal.field_h);
        }
        ui.painter().text(
            pos2(r.left() + 14.0, r.center().y),
            Align2::LEFT_CENTER,
            &name,
            t.font(11.5),
            if current { pal.accent_hi } else { pal.text },
        );
        if resp.clicked() && !current {
            let _ = app.run("version.restore", json!({"index": i}));
        }
    }
    ui.horizontal(|ui| {
        ui.add_space(10.0);
        if ui_pro::chip(ui, "newSnapshot", crate::i18n::tr("+ New snapshot"), false).clicked() {
            let _ = app.run("version.create", json!({}));
        }
    });
}

fn history(app: &mut LightcraftApp, ui: &mut Ui, photo: PhotoId) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let Some(p) = app.session.catalog.photo(photo).cloned() else { return };
    if p.history.is_empty() {
        ui.horizontal(|ui| {
            ui.add_space(14.0);
            ui.label(egui::RichText::new(crate::i18n::tr("No edits yet.")).size(11.0).color(pal.text3));
        });
        return;
    }
    let cursor = p.history_index();
    for (i, h) in p.history.iter().enumerate().rev().take(60) {
        let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), 22.0), Sense::click());
        crate::widgets::register(ui, format!("history:{i}"), r);
        crate::widgets::announce(&resp, crate::i18n::tr(&h.label));
        let row = super::right::history_row(i, cursor);
        let current = row == super::right::HistoryRow::Current;
        if current {
            ui.painter().rect_filled(r.shrink2(vec2(6.0, 0.0)), CornerRadius::same(6), pal.accent_bg);
        } else if resp.hovered() {
            ui.painter().rect_filled(r.shrink2(vec2(6.0, 0.0)), CornerRadius::same(6), pal.field_h);
        }
        let undone = row == super::right::HistoryRow::Undone;
        ui.painter().circle_filled(pos2(r.left() + 16.0, r.center().y), 2.5, if current { pal.accent } else { pal.text4 });
        ui.painter().text(
            pos2(r.left() + 28.0, r.center().y),
            Align2::LEFT_CENTER,
            crate::i18n::history_label(&h.label, &app.session.presets),
            t.font(11.5),
            if undone {
                pal.text4
            } else if current {
                pal.accent_hi
            } else {
                pal.text2
            },
        );
        if resp.clicked() {
            let _ = app.run("history.restore", json!({"index": i}));
        }
    }
}
