//! Chrome of the Pro desktop layout's Develop workspace: the tool strip on the left of the canvas, the contextual
//! option bar under it and the window's status bar. Only runs when `theme::desktop_pro` is on and a photo is open
//! in Detail view.

use egui::{Align, Align2, Color32, CornerRadius, Sense, Stroke, Ui, pos2, vec2};
use serde_json::json;

use super::ui_pro::{self, Pal};
use crate::LightcraftApp;
use crate::icons::Icon;
use crate::render::Slot;
use crate::state::{RightPanel, ViewMode, Zoom};
use crate::theme::Tokens;

/// Whether the Develop workspace chrome applies to this frame.
pub fn active(app: &LightcraftApp, ctx: &egui::Context) -> bool {
    crate::theme::desktop_pro(ctx) && app.ui.view == ViewMode::Detail && app.session.active().is_some()
}

/// The tools of the strip, top to bottom: command id, icon, panel the tool owns, tooltip.
pub const TOOLS: [(&str, Icon, RightPanel, &str); 5] = [
    ("edit", Icon::Sliders, RightPanel::Edit, "Develop (E)"),
    ("crop", Icon::Crop, RightPanel::Crop, "Crop & Rotate (C)"),
    ("remove", Icon::Eraser, RightPanel::Remove, "Heal & Clone (H)"),
    ("masking", Icon::Mask, RightPanel::Masking, "Masks (M)"),
    ("redeye", Icon::Eye, RightPanel::RedEye, "Red Eye"),
];

/// The 38pt tool strip, a glass capsule on the canvas column's left edge.
pub fn tool_strip(app: &mut LightcraftApp, ui: &mut Ui) {
    let pal = Pal::get(ui.ctx());
    egui::Panel::left("pro_tool_strip")
        .exact_size(ui_pro::TOOL_STRIP_W)
        .resizable(false)
        .frame(egui::Frame::NONE.fill(pal.glass).stroke(Stroke::new(1.0, pal.rim2)).inner_margin(egui::Margin {
            left: 3,
            right: 3,
            top: 6,
            bottom: 6,
        }))
        .show(ui, |ui| {
            ui.spacing_mut().item_spacing.y = 4.0;
            for (id, icon, panel, tip) in TOOLS {
                let on = app.ui.right == panel || (panel == RightPanel::Edit && app.ui.right == RightPanel::Profiles);
                if ui_pro::icon_button(ui, &format!("tool-{id}"), icon, ui_pro::TOOL_SIZE, on, crate::i18n::tr(tip)).clicked() {
                    let _ = app.run(&format!("panel.{id}"), json!({}));
                }
                if id == "edit" {
                    let (r, _) = ui.allocate_exact_size(vec2(ui_pro::TOOL_SIZE, 1.0), Sense::hover());
                    ui.painter().rect_filled(r, 0.0, pal.rim2);
                }
            }
        });
}

/// The 32pt contextual option bar under the stage.
pub fn option_bar(app: &mut LightcraftApp, ui: &mut Ui) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    egui::Panel::bottom("pro_option_bar")
        .exact_size(ui_pro::OPTION_BAR_H)
        .resizable(false)
        .frame(egui::Frame::NONE.fill(pal.glass).stroke(Stroke::new(1.0, pal.rim2)).inner_margin(egui::Margin::symmetric(10, 0)))
        .show(ui, |ui| {
            ui.spacing_mut().item_spacing.x = 6.0;
            let hint = match app.ui.right {
                RightPanel::Crop => "Drag a handle to resize \u{b7} drag outside to rotate \u{b7} Enter applies, Esc cancels",
                RightPanel::Masking => "Click the photo to place a mask \u{b7} O toggles the overlay",
                RightPanel::Remove => "Click a blemish to heal it \u{b7} [ ] size",
                RightPanel::RedEye => "Click an eye",
                _ => "Alt fine \u{b7} Shift coarse \u{b7} double-click a label to reset",
            };
            ui.horizontal_centered(|ui| {
                match app.ui.right {
                    RightPanel::Crop => {
                        let locked = app.session.active().and_then(|id| app.session.develop_of(id)).is_some_and(|d| d.crop.aspect.is_some());
                        if ui_pro::chip(ui, "optLock", crate::i18n::tr("Lock aspect"), locked).clicked() {
                            let _ = app.run("crop.aspect", json!({"aspect": "toggle"}));
                        }
                        if ui_pro::chip(ui, "optCropReset", crate::i18n::tr("Reset"), false).clicked() {
                            let _ = app.run("crop.reset", json!({}));
                        }
                        if ui_pro::chip(ui, "optCropCancel", crate::i18n::tr("Cancel"), false).clicked() {
                            let _ = app.run("panel.edit", json!({}));
                        }
                        if ui_pro::button(ui, "optCropDone", crate::i18n::tr("Done"), true).clicked() {
                            let _ = app.run("tool.done", json!({}));
                        }
                    }
                    RightPanel::Masking => {
                        for (id, label) in [("radial", "Radial"), ("linear", "Linear"), ("brush", "Brush")] {
                            let on = app.ui.tool == id;
                            if ui_pro::chip(ui, &format!("opt-{id}"), crate::i18n::tr(label), on).clicked() {
                                let _ = app.run(&format!("tool.{id}"), json!({}));
                            }
                        }
                        let overlay = app.ui.mask_overlay;
                        if ui_pro::chip(ui, "optOverlay", crate::i18n::tr("Overlay"), overlay).clicked() {
                            let _ = app.run("view.maskOverlay", json!({}));
                        }
                    }
                    RightPanel::Remove => {
                        let on = app.ui.visualize_spots;
                        if ui_pro::chip(ui, "optSpots", crate::i18n::tr("Visualise spots"), on).clicked() {
                            let _ = app.run("view.visualizeSpots", json!({}));
                        }
                    }
                    RightPanel::Edit | RightPanel::Profiles => {
                        let proof = app.ui.soft_proof;
                        if ui_pro::chip(ui, "optSoftProof", crate::i18n::tr("Soft proof"), proof).clicked() {
                            let _ = app.run("view.softProof", json!({}));
                        }
                        let clip = app.ui.show_clipping;
                        if ui_pro::chip(ui, "optClipping", crate::i18n::tr("Clipping"), clip).clicked() {
                            let _ = app.run("view.clipping", json!({}));
                        }
                    }
                    _ => {}
                }
                ui.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
                    ui.label(egui::RichText::new(crate::i18n::tr(hint)).font(t.font(11.0)).color(pal.text3));
                });
            });
        });
}

/// The window's 24pt status bar: file and camera on the left, render time, colour space and zoom on the right.
pub fn status_bar(app: &mut LightcraftApp, ui: &mut Ui) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let Some(id) = app.session.active() else { return };
    let (left, camera) = match app.session.catalog.photo(id) {
        Some(p) => {
            let mp = f64::from(p.width) * f64::from(p.height) / 1.0e6;
            (format!("{}  \u{b7}  {}\u{d7}{}  \u{b7}  {mp:.1} MP", p.file_name, p.width, p.height), p.meta.camera.clone())
        }
        None => (String::new(), String::new()),
    };
    let ms = app.renderer.textures.get(&Slot::Main).filter(|x| x.photo == id).map(|x| x.ms);
    let zoom = match app.ui.zoom {
        Zoom::Fit => "Fit".to_string(),
        Zoom::Fill => "Fill".to_string(),
        Zoom::Percent(p) => format!("{p:.0}%"),
    };
    let unsaved = app.session.interaction.is_some();
    egui::Panel::bottom("pro_status_bar")
        .exact_size(ui_pro::STATUS_H)
        .resizable(false)
        .frame(
            egui::Frame::NONE
                .fill(Color32::from_rgb(0x1B, 0x1B, 0x1D))
                .stroke(Stroke::new(1.0, pal.rim2))
                .inner_margin(egui::Margin::symmetric(12, 0)),
        )
        .show(ui, |ui| {
            let r = ui.max_rect();
            let p = ui.painter();
            let dot = if unsaved { Color32::from_rgb(0xE3, 0xA8, 0x3C) } else { Color32::from_rgb(0x30, 0xD1, 0x58) };
            p.circle_filled(pos2(r.left() + 4.0, r.center().y), 3.0, dot);
            p.text(pos2(r.left() + 16.0, r.center().y), Align2::LEFT_CENTER, &left, t.font(11.0), pal.text2);
            let mut right = format!("sRGB  \u{b7}  {zoom}");
            if let Some(ms) = ms {
                right = format!("{ms:.0} ms  \u{b7}  {right}");
            }
            p.text(pos2(r.right(), r.center().y), Align2::RIGHT_CENTER, right, t.font(11.0), pal.text2);
            if !camera.is_empty() {
                p.text(pos2(r.center().x, r.center().y), Align2::CENTER_CENTER, camera, t.font(11.0), pal.text3);
            }
            crate::widgets::register(ui, "statusBar", r);
        });
    let _ = CornerRadius::ZERO;
}
