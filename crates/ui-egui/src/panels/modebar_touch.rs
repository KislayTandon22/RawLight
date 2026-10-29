//! Touch-only bottom mode capsule. Library selects `PhotoGrid` and clears the right panel;
//! Edit/Crop/Heal/Mask/History select their corresponding `RightPanel`, while Looks dispatches
//! `panel.presets`. Selection is always derived from the current view and panel state.

use egui::{Align, Color32, Layout, Rect, UiBuilder, pos2, vec2};
use serde_json::json;

use crate::{
    LightcraftApp,
    icons::Icon,
    state::{RightPanel, ViewMode},
    theme::Tokens,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Tab {
    Library,
    Edit,
    Crop,
    Heal,
    Mask,
    Looks,
    History,
    More,
}

impl Tab {
    fn label(self) -> &'static str {
        match self {
            Self::Library => "Library",
            Self::Edit => "Edit",
            Self::Crop => "Crop",
            Self::Heal => "Heal",
            Self::Mask => "Mask",
            Self::Looks => "Looks",
            Self::History => "History",
            Self::More => "More",
        }
    }

    fn icon(self) -> Icon {
        match self {
            Self::Library => Icon::GridPhoto,
            Self::Edit => Icon::Sliders,
            Self::Crop => Icon::Crop,
            Self::Heal => Icon::Eraser,
            Self::Mask => Icon::Mask,
            Self::Looks => Icon::Presets,
            Self::History => Icon::Activity,
            Self::More => Icon::More,
        }
    }
}

fn selected(view: ViewMode, panel: RightPanel, presets: bool) -> Tab {
    if presets {
        return Tab::Looks;
    }
    match panel {
        RightPanel::Edit | RightPanel::Profiles | RightPanel::QuickDevelop => Tab::Edit,
        RightPanel::Crop => Tab::Crop,
        RightPanel::Remove | RightPanel::RedEye => Tab::Heal,
        RightPanel::Masking => Tab::Mask,
        RightPanel::Activity => Tab::History,
        RightPanel::None if view == ViewMode::PhotoGrid => Tab::Library,
        _ => Tab::Library,
    }
}

fn dispatch(app: &mut LightcraftApp, tab: Tab) {
    match tab {
        Tab::Library => {
            app.ui.view = ViewMode::PhotoGrid;
            app.ui.right = RightPanel::None;
            app.ui.presets = false;
        }
        Tab::Edit => {
            app.ui.view = ViewMode::Detail;
            let _ = app.run("panel.edit", json!({}));
        }
        Tab::Crop => {
            app.ui.view = ViewMode::Detail;
            let _ = app.run("panel.crop", json!({}));
        }
        Tab::Heal => {
            app.ui.view = ViewMode::Detail;
            let _ = app.run("panel.remove", json!({}));
        }
        Tab::Mask => {
            app.ui.view = ViewMode::Detail;
            let _ = app.run("panel.masking", json!({}));
        }
        Tab::Looks => {
            app.ui.view = ViewMode::Detail;
            let _ = app.run("panel.presets", json!({}));
        }
        Tab::History => {
            let _ = app.run("panel.activity", json!({}));
        }
        Tab::More => {}
    }
}

fn tab_width(available: f32, tab_count: usize) -> f32 {
    if tab_count == 0 {
        return 0.0;
    }
    ((available - 16.0).max(0.0) / tab_count as f32).clamp(44.0, 66.0)
}

fn capsule_width(tab_count: usize, item_width: f32) -> f32 {
    tab_count as f32 * item_width + 16.0
}

pub fn show(app: &mut LightcraftApp, ui: &mut egui::Ui) {
    let ctx = ui.ctx().clone();
    if !crate::theme::touch_ui(&ctx) || !crate::glass::active(&ctx) {
        return;
    }
    let insets = crate::theme::safe_area_insets(&ctx);
    let safe = insets[1].max(20.0);
    let full = ui.available_width() >= 700.0;
    let tabs: &[Tab] = if full {
        &[Tab::Library, Tab::Edit, Tab::Crop, Tab::Heal, Tab::Mask, Tab::Looks, Tab::History]
    } else {
        &[Tab::Library, Tab::Edit, Tab::Crop, Tab::Mask, Tab::Looks, Tab::More]
    };
    let active = app.session.active().is_some();
    let current = selected(app.ui.view, app.ui.right, app.ui.presets);
    let panel_width = ui.available_width().min(ctx.content_rect().width());
    let item_width = tab_width(panel_width, tabs.len());
    let width = capsule_width(tabs.len(), item_width);
    egui::Panel::bottom("touch_mode_capsule").exact_size(62.0 + 8.0 + 8.0 + safe).frame(egui::Frame::NONE).show(ui, |ui| {
        let panel_rect = ui.max_rect();
        let capsule_rect = Rect::from_min_size(pos2(panel_rect.center().x - width / 2.0, panel_rect.bottom() - safe - 8.0 - 62.0), vec2(width, 62.0));
        let capsule_ui = ui.scope_builder(UiBuilder::new().max_rect(capsule_rect).layout(Layout::left_to_right(Align::Center)), |ui| {
            crate::glass::shell(egui::Margin::symmetric(8, 0), egui::Margin::ZERO).stroke(egui::Stroke::NONE).show(ui, |ui| {
                ui.spacing_mut().item_spacing.x = 0.0;
                for &tab in tabs {
                    if tab == Tab::More {
                        let response = ui.allocate_response(vec2(item_width, 54.0), egui::Sense::click());
                        crate::widgets::register(ui, "mode:more", response.rect);
                        crate::widgets::announce(&response, "More modes".to_owned());
                        let t = Tokens::get(ui.ctx());
                        crate::icons::paint(
                            ui.painter(),
                            egui::Rect::from_center_size(pos2(response.rect.center().x, response.rect.top() + 17.0), vec2(20.0, 20.0)),
                            Icon::More,
                            t.text,
                        );
                        ui.painter().text(
                            pos2(response.rect.center().x, response.rect.bottom() - 7.0),
                            egui::Align2::CENTER_CENTER,
                            tab.label(),
                            t.font(12.0),
                            t.text,
                        );
                        egui::Popup::menu(&response).show(|ui| {
                            crate::widgets::touch_menu_style(ui);
                            ui.spacing_mut().item_spacing.y = 0.0;
                            for item in [Tab::Heal, Tab::History] {
                                if ui.add_sized([160.0, 48.0], egui::Button::new(item.label()).frame(false)).clicked() {
                                    dispatch(app, item);
                                    ui.close();
                                }
                            }
                        });
                        continue;
                    }
                    let enabled = tab == Tab::Library || tab == Tab::History || active;
                    let response = ui.allocate_response(vec2(item_width, 54.0), egui::Sense::click());
                    crate::widgets::register(ui, format!("mode:{}", tab.label().to_lowercase()), response.rect);
                    crate::widgets::announce(&response, tab.label().to_owned());
                    let t = Tokens::get(ui.ctx());
                    let chosen = current == tab;
                    if chosen {
                        let pill = Rect::from_center_size(response.rect.center(), vec2((item_width - 4.0).max(0.0), 50.0));
                        ui.painter().rect_filled(pill, pill.height() / 2.0, Color32::from_white_alpha(41));
                    }
                    let color = if !enabled {
                        Color32::from_white_alpha(77)
                    } else if chosen {
                        t.accent
                    } else {
                        t.text.gamma_multiply(0.62)
                    };
                    crate::icons::paint(
                        ui.painter(),
                        egui::Rect::from_center_size(pos2(response.rect.center().x, response.rect.center().y - 10.0), vec2(20.0, 20.0)),
                        tab.icon(),
                        color,
                    );
                    ui.painter().text(
                        pos2(response.rect.center().x, response.rect.center().y + 14.5),
                        egui::Align2::CENTER_CENTER,
                        tab.label(),
                        t.font(12.0),
                        color,
                    );
                    if response.clicked() && enabled {
                        dispatch(app, tab);
                    }
                }
            });
        });
        capsule_ui.response
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mode_selection_follows_view_and_panel() {
        assert_eq!(selected(ViewMode::PhotoGrid, RightPanel::None, false), Tab::Library);
        assert_eq!(selected(ViewMode::Detail, RightPanel::Edit, false), Tab::Edit);
        assert_eq!(selected(ViewMode::Detail, RightPanel::Masking, false), Tab::Mask);
        assert_eq!(selected(ViewMode::PhotoGrid, RightPanel::None, true), Tab::Looks);
    }

    #[test]
    fn capsule_tab_width_fits_target_screens() {
        let ipad = tab_width(744.0, 7);
        assert_eq!(ipad, 66.0);
        assert_eq!(capsule_width(7, ipad), 478.0);
        let phone = tab_width(375.0, 6);
        assert!((capsule_width(6, phone) - 375.0).abs() < f32::EPSILON);
        assert_eq!(tab_width(50.0, 6), 44.0);
        assert_eq!(tab_width(700.0, 7), 66.0);
    }
}
