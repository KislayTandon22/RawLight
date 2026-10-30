//! Touch-first Edit inspector. The desktop panel remains in `edit.rs` unchanged.

use egui::{Color32, CornerRadius, Sense, pos2, vec2};
use lightcraft_catalog::PhotoId;
use lightcraft_develop::{Section, controls};
use serde_json::json;

use crate::{
    LightcraftApp,
    icons::{Icon, paint},
    theme::Tokens,
};

const GROUPS: [(&str, Icon, Section); 5] = [
    ("Light", Icon::Sun, Section::Light),
    ("Colour", Icon::GradeAll, Section::Color),
    ("Effects", Icon::Presets, Section::Effects),
    ("Detail", Icon::Eye, Section::Detail),
    ("Optics", Icon::Circle, Section::Optics),
];

pub(super) fn show(app: &mut LightcraftApp, ui: &mut egui::Ui, id: PhotoId) {
    if !crate::theme::touch_ui(ui.ctx()) || !crate::glass::active(ui.ctx()) {
        return;
    }
    let t = Tokens::get(ui.ctx());
    let fill = crate::glass::fill();
    let phone = crate::theme::phone(ui.ctx());
    let key = ui.scope_id().with("touch-edit-group");
    let mut group = ui.ctx().data(|d| d.get_temp::<usize>(key)).unwrap_or(0).min(4);
    let d = app.session.develop_of(id).unwrap_or_default();
    egui::Frame::NONE.fill(fill).corner_radius(CornerRadius::same(28)).inner_margin(egui::Margin::same(16)).show(ui, |ui| {
        ui.set_width(ui.available_width());
        if !phone {
            ui.horizontal(|ui| {
                ui.label(egui::RichText::new(crate::i18n::tr(GROUPS[group].0)).size(20.0).strong().color(t.text));
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                    let b = crate::ui_kit_touch::capsule_button(ui, "Reset", crate::ui_kit_touch::Kind::Neutral);
                    if b.clicked() {
                        let _ = app.run("develop.reset", json!({}));
                    }
                });
            });
            ui.add_space(8.0);
        }
        let body_h = (ui.available_height() - 66.0).max(120.0);
        egui::ScrollArea::vertical().max_height(body_h).auto_shrink([false, true]).show(ui, |ui| {
            // The existing Edit histogram owns clipping interaction and histogram rendering.
            if !phone {
                super::edit::histogram(app, ui, id);
                ui.horizontal(|ui| {
                    ui.spacing_mut().item_spacing.x = 8.0;
                    let width = ((ui.available_width() - 16.0) / 3.0).max(44.0);
                    for (label, cmd, active) in [("Auto", "auto", true), ("B&W", "bw", crate::is_bw(&d)), ("HDR", "hdr", d.hdr.enabled)] {
                        let (rect, response) = ui.allocate_exact_size(vec2(width, 44.0), Sense::click());
                        crate::widgets::announce_selected(&response, label, active);
                        ui.painter().rect_filled(
                            rect,
                            22.0,
                            if active { Color32::from_rgba_unmultiplied(10, 132, 255, 46) } else { Color32::from_white_alpha(31) },
                        );
                        ui.painter().text(
                            rect.center(),
                            egui::Align2::CENTER_CENTER,
                            label,
                            t.semibold(15.0),
                            if active { t.accent } else { t.text },
                        );
                        if response.clicked() {
                            match cmd {
                                "auto" => {
                                    let _ = app.run("develop.auto", json!({}));
                                }
                                "bw" => {
                                    let _ = app.run("develop.treatment", json!({}));
                                }
                                _ => {
                                    let _ = app.run("develop.hdr", json!({"enabled": !d.hdr.enabled}));
                                }
                            }
                        }
                    }
                });
            }
            ui.add_space(8.0);
            let profile_name = app.session.profile_info(&d.profile.id).map(|p| p.0).unwrap_or("Color");
            let (profile_rect, profile_response) = ui.allocate_exact_size(vec2(ui.available_width(), 44.0), Sense::click());
            crate::widgets::announce(&profile_response, format!("Profile, {profile_name}"));
            ui.painter().rect_filled(profile_rect, 22.0, Color32::from_white_alpha(31));
            ui.painter().text(
                pos2(profile_rect.left() + 16.0, profile_rect.center().y),
                egui::Align2::LEFT_CENTER,
                "Profile",
                t.font(14.0),
                t.text_dim,
            );
            ui.painter().text(
                pos2(profile_rect.left() + 78.0, profile_rect.center().y),
                egui::Align2::LEFT_CENTER,
                profile_name,
                t.semibold(14.0),
                t.text,
            );
            ui.painter().text(pos2(profile_rect.right() - 18.0, profile_rect.center().y), egui::Align2::CENTER_CENTER, "⌃", t.font(16.0), t.text);
            ui.add_space(8.0);
            let specs: Vec<_> = controls::in_section(GROUPS[group].2).filter(|s| !s.id.starts_with("hdr.")).collect();
            let param_key = ui.scope_id().with("touch-edit-param");
            let mut selected =
                if phone { ui.ctx().data(|data| data.get_temp::<usize>(param_key)).unwrap_or(0).min(specs.len().saturating_sub(1)) } else { 0 };
            if phone {
                egui::ScrollArea::horizontal().id_salt("touch-edit-chips").show(ui, |ui| {
                    ui.horizontal(|ui| {
                        ui.spacing_mut().item_spacing.x = 6.0;
                        for (i, spec) in specs.iter().enumerate() {
                            let label = crate::i18n::tr(spec.label);
                            let w = 28.0 + label.chars().count() as f32 * 7.5;
                            let (r, response) = ui.allocate_exact_size(vec2(w, 44.0), Sense::click());
                            crate::widgets::announce_selected(&response, label.to_string(), selected == i);
                            if selected == i {
                                ui.painter().rect_filled(r, 22.0, Color32::from_white_alpha(51));
                            }
                            ui.painter().text(
                                r.center(),
                                egui::Align2::CENTER_CENTER,
                                label,
                                t.semibold(13.0),
                                if selected == i { t.accent } else { t.text },
                            );
                            if response.clicked() {
                                selected = i;
                                ui.ctx().data_mut(|d| d.insert_temp(param_key, i));
                            }
                        }
                    });
                });
                ui.add_space(8.0);
            }
            for (i, spec) in specs.iter().enumerate() {
                if phone && i != selected {
                    continue;
                }
                let is_denoise = spec.id == "enhance.denoise";
                let denoise_on = d.enhance.denoise_enabled();
                if is_denoise {
                    let applicable = !matches!(app.session.denoise_photo_state(id), lightcraft_engine::denoise::PhotoState::NotApplicable);
                    super::denoise::detail_toggle(app, ui, id, denoise_on, applicable);
                }
                let value = controls::get(&d, spec.id).unwrap_or(spec.default);
                let mut v = value as f32;
                let response = crate::ui_kit_touch::edit_slider_row(ui, spec.label, &mut v, spec.min as f32..=spec.max as f32, spec.default as f32);
                if response.changed() {
                    if response.drag_started() {
                        let _ = app.run("develop.beginInteraction", json!({"label": spec.label}));
                    }
                    let _ = app.run("develop.set", json!({"control": spec.id, "value": v}));
                    if response.drag_stopped() {
                        let _ = app.run("develop.endInteraction", json!({}));
                    }
                }
                if is_denoise {
                    super::denoise::detail_status(app, ui, id, if denoise_on { d.enhance.denoise } else { 0.0 });
                }
                ui.add_space(4.0);
            }
            if group == 0 {
                let curve_open = app.ui.flyout_open("curve");
                let (curve, curve_response) = ui.allocate_exact_size(vec2(ui.available_width(), 44.0), Sense::click());
                crate::widgets::announce(&curve_response, "Tone curve");
                ui.painter().rect_filled(curve, 22.0, Color32::from_white_alpha(31));
                paint(
                    ui.painter(),
                    egui::Rect::from_center_size(pos2(curve.left() + 24.0, curve.center().y), vec2(18.0, 18.0)),
                    Icon::Curve,
                    t.text_dim,
                );
                ui.painter().text(pos2(curve.left() + 46.0, curve.center().y), egui::Align2::LEFT_CENTER, "Tone curve", t.semibold(14.0), t.text);
                ui.painter().text(
                    pos2(curve.right() - 18.0, curve.center().y),
                    egui::Align2::RIGHT_CENTER,
                    if curve_open { "Hide  ⌄" } else { "Adjust  ›" },
                    t.font(14.0),
                    t.text_dim,
                );
                if curve_response.clicked() {
                    app.ui.toggle_flyout("curve");
                }
                if curve_open {
                    super::edit::curve_editor(app, ui, id, &d);
                }
            }
        });
        ui.add_space(12.0);
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing.x = 0.0;
            let tab_w = ui.available_width() / 5.0;
            for (i, (label, icon, _)) in GROUPS.iter().enumerate() {
                let (r, response) = ui.allocate_exact_size(vec2(tab_w, 54.0), Sense::click());
                crate::widgets::announce_selected(&response, *label, group == i);
                if group == i {
                    ui.painter().rect_filled(r.shrink(2.0), 24.0, Color32::from_white_alpha(51));
                }
                paint(
                    ui.painter(),
                    egui::Rect::from_center_size(pos2(r.center().x, r.top() + 15.0), vec2(18.0, 18.0)),
                    *icon,
                    if group == i { t.accent } else { t.icon },
                );
                ui.painter().text(
                    pos2(r.center().x, r.bottom() - 10.0),
                    egui::Align2::CENTER_CENTER,
                    crate::i18n::tr(label),
                    t.font(12.0),
                    if group == i { t.accent } else { t.text_dim },
                );
                if response.clicked() {
                    group = i;
                    ui.ctx().data_mut(|d| d.insert_temp(key, group));
                }
            }
        });
    });
}
