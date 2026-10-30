//! The photo screens' top bar (touch): one floating glass capsule across the top of an open photo —
//! the way back to the grid, undo / redo, the file name with its tag, and the rating cluster (pick,
//! reject, five stars) followed by the tool's own control at the right (Sort and Share in Edit and
//! Looks, before/after and More in Crop, the overlay switch in Masking).
//!
//! It replaces the library bar ([`super::topbar_touch`]) only while a photo is open, and only on
//! touch with glass: [`show`] returns whether it drew, so every other layout keeps the library bar.

use egui::{Color32, CornerRadius, Frame, Id, Margin, Rect, Response, Sense, pos2, vec2};
use lightcraft_catalog::{Flag, Photo};
use serde_json::json;

use crate::LightcraftApp;
use crate::icons::{Icon, paint};
use crate::state::{RightPanel, ViewMode};
use crate::theme::Tokens;
use crate::widgets::{announce, announce_selected, one_line, register};

/// A control's height: the bar is 60 points tall, so a 44-point control keeps 8 points above and
/// below it inside the capsule.
const CONTROL_H: f32 = crate::ui_kit_touch::CONTROL_H;
/// The bar's height on the iPad (the glass bottom bar uses the same).
const BAR_H: f32 = crate::ui_kit_touch::BAR_H;
/// The phone's shorter bar and the rating capsule that floats under it.
const PHONE_BAR_H: f32 = 52.0;
const PHONE_PILL_H: f32 = 52.0;
/// The phone's rating capsule holds its controls this far in from either edge.
const PHONE_INSET: f32 = 4.0;
/// The gap between the controls of one group and between two groups.
const GAP: f32 = 2.0;
const GROUP_GAP: f32 = 8.0;
/// The phone's pill is as wide as its contents: the inset either side of pick, reject and the stars.
const PHONE_PILL_W: f32 = 2.0 * PHONE_INSET + CONTROL_H + GAP + CONTROL_H + 6.0 + 5.0 * STAR_CELL;
/// The pick button is a 48-point capsule (wider than a square icon button, as the design draws it).
const PICK_W: f32 = 48.0;
/// Five stars share one 180-point row, on the iPad and in the phone's pill.
const STAR_CELL: f32 = 36.0;
const STAR: f32 = 18.0;
/// Masking's Overlay / Outline / Off switch.
const MASK_SWITCH_W: f32 = 240.0;
/// Where the name sits: the text size and the smaller tag beside it.
const NAME_SIZE: f32 = 15.0;
const TAG_SIZE: f32 = 14.0;
/// White at 25%: the pick / reject tint when the flag is set.
const FLAG_TINT: u8 = 64;
/// White at 10%: the phone's rating capsule.
const PILL_ALPHA: u8 = 26;

/// Secondary text: white at 62%, the design's secondary colour on glass.
fn secondary() -> Color32 {
    Color32::from_white_alpha(158)
}

/// A translucent white fill on the glass look (the bar only draws with glass active, always dark).
fn soft(alpha: u8) -> Color32 {
    Color32::from_white_alpha(alpha)
}

/// `c` mixed towards white by `t` (0 to 1): the brighter ink a tinted flag icon uses.
fn lighter(c: Color32, t: f32) -> Color32 {
    crate::widgets::lerp(c, Color32::WHITE, t)
}

/// Whether a photo is open in the loupe: the grid keeps the library bar even while an edit tool's
/// panel stays open beside it (Back from the loupe leaves the panel in place).
fn photo_open(app: &LightcraftApp) -> bool {
    app.ui.view == ViewMode::Detail || app.ui.right.is_edit_tool()
}

/// On a wide iPad the edit panel is docked to the right of the photo canvas. Keep the floating
/// bar in that canvas rather than painting over the panel; portrait and phone layouts dock the
/// panel below the photo and therefore keep the full width.
fn right_inset(app: &LightcraftApp, ui: &egui::Ui) -> i8 {
    if !crate::theme::phone(ui.ctx()) && ui.available_width() > 1000.0 && app.ui.right.is_edit_tool() {
        (app.ui.right_width.round() as i8).saturating_add(8)
    } else {
        8
    }
}

/// The file's name without its extension, which is what the bar shows ("LC01221", not "LC01221.JPG").
fn display_name(file_name: &str) -> String {
    std::path::Path::new(file_name).file_stem().map_or_else(|| file_name.to_string(), |n| n.to_string_lossy().into_owned())
}

/// The small word after the file name: the tool while cropping (as the design shows), the Edited
/// tag for an edited photo in the other panels, nothing while masking (its switch needs the room).
fn tag(app: &LightcraftApp, photo: &Photo) -> Option<&'static str> {
    if app.ui.right == RightPanel::Crop {
        return Some("Crop");
    }
    if app.ui.right == RightPanel::Masking {
        return None;
    }
    photo.is_edited().then_some("Edited")
}

/// Draw the photo bar when a photo is open on touch + glass. Returns whether it drew: when it did
/// not, the caller draws the library bar exactly as before.
pub fn show(app: &mut LightcraftApp, ui: &mut egui::Ui) -> bool {
    let ctx = ui.ctx().clone();
    if !crate::theme::touch_ui(&ctx) || !crate::glass::active(&ctx) || !photo_open(app) {
        return false;
    }
    let Some(photo) = app.session.active().and_then(|id| app.session.catalog.photo(id).cloned()) else {
        return false;
    };
    let insets = crate::theme::safe_area_insets(&ctx);
    let safe_top = insets[0].max(28.0);
    let phone = crate::theme::phone(&ctx);
    let radius = if phone { PHONE_BAR_H / 2.0 } else { BAR_H / 2.0 };
    let bar_h = if phone { PHONE_BAR_H } else { BAR_H };
    let extra = if phone { GROUP_GAP + PHONE_PILL_H } else { 0.0 };
    let outer = Margin {
        left: 8 + insets[2].round() as i8,
        right: right_inset(app, ui).saturating_add(insets[3].round() as i8),
        top: safe_top.round() as i8 + 8,
        bottom: 8,
    };
    if phone {
        // two floating shapes: the short bar and, 8 points under it, the rating capsule
        egui::Panel::top("photo_bar").exact_size(bar_h + extra + safe_top + 16.0).frame(Frame::NONE.outer_margin(outer)).show(ui, |ui| {
            let w = ui.available_width();
            let glass = |r: f32| {
                Frame::NONE
                    .fill(crate::glass::fill())
                    .stroke(crate::glass::rim())
                    .corner_radius(CornerRadius::same(r.round() as u8))
                    .shadow(crate::glass::shadow())
            };
            glass(radius).show(ui, |ui| {
                let (rect, _) = ui.allocate_exact_size(vec2(w, bar_h), Sense::hover());
                phone_bar(app, ui, rect, &photo);
            });
            ui.add_space(GROUP_GAP);
            ui.horizontal_centered(|ui| {
                // the spacer and the pill are two items: without this, item spacing would push the
                // pill right of centre by that gap
                ui.spacing_mut().item_spacing.x = 0.0;
                ui.add_space(((ui.available_width() - PHONE_PILL_W) / 2.0).max(0.0));
                Frame::NONE.fill(soft(PILL_ALPHA)).corner_radius(CornerRadius::same((PHONE_PILL_H / 2.0).round() as u8)).show(ui, |ui| {
                    let (rect, _) = ui.allocate_exact_size(vec2(PHONE_PILL_W, PHONE_PILL_H), Sense::hover());
                    phone_rating(app, ui, rect, &photo);
                });
            });
        });
        return true;
    }
    // iPad: one long glass capsule, 60 points tall and 8 points in from the screen edge
    let frame = Frame::NONE
        .fill(crate::glass::fill())
        .stroke(crate::glass::rim())
        .corner_radius(CornerRadius::same((BAR_H / 2.0).round() as u8))
        .shadow(crate::glass::shadow())
        .inner_margin(Margin { left: 8, right: 8, top: 0, bottom: 0 })
        .outer_margin(outer);
    egui::Panel::top("photo_bar").exact_size(BAR_H + safe_top + 16.0).frame(frame).show(ui, |ui| {
        let (rect, _) = ui.allocate_exact_size(vec2(ui.available_width(), BAR_H), Sense::hover());
        ipad_bar(app, ui, rect, &photo);
    });
    true
}

/// The iPad bar's contents: the leading group, the centred name and the trailing cluster.
fn ipad_bar(app: &mut LightcraftApp, ui: &mut egui::Ui, rect: Rect, photo: &Photo) {
    let cy = rect.center().y;
    let row = |left: f32, w: f32| Rect::from_min_size(pos2(left, cy - CONTROL_H / 2.0), vec2(w, CONTROL_H));

    // the leading group: back to the grid, then undo / redo of the edit, ratings and flags
    let mut x = rect.left();
    if bar_button(ui, "back", Icon::Back, row(x, CONTROL_H), 16.0, true, "Back").clicked() {
        let _ = app.run("view.photoGrid", json!({}));
    }
    x += CONTROL_H + GAP;
    let can_undo = !app.session.undo.is_empty();
    if bar_button(ui, "undo", Icon::Undo, row(x, CONTROL_H), 21.0, can_undo, "Undo").clicked() {
        let _ = app.run("edit.undo", json!({}));
    }
    x += CONTROL_H + GAP;
    let can_redo = !app.session.redo.is_empty();
    if bar_button(ui, "redo", Icon::Redo, row(x, CONTROL_H), 21.0, can_redo, "Redo").clicked() {
        let _ = app.run("edit.redo", json!({}));
    }
    let left_end = x + CONTROL_H;

    // the trailing cluster, from the right edge inwards
    let trailing = trailing_width(app);
    let start = rect.right() - trailing;
    name_and_tag(app, ui, photo, left_end + 2.0 * GROUP_GAP, start - 2.0 * GROUP_GAP, cy);
    trailing_cluster(app, ui, photo, start, cy);
}

/// The width of the bar's trailing cluster (pick, reject, stars and the tool's own control).
fn trailing_width(app: &LightcraftApp) -> f32 {
    let last = if app.ui.right == RightPanel::Masking { MASK_SWITCH_W } else { CONTROL_H + GAP + CONTROL_H };
    PICK_W + GAP + CONTROL_H + 10.0 + 5.0 * STAR_CELL + GROUP_GAP + last
}

/// The pick flag, reject cross, five stars and the tool's control, laid out from `start`.
fn trailing_cluster(app: &mut LightcraftApp, ui: &mut egui::Ui, photo: &Photo, start: f32, cy: f32) {
    let mut x = start;
    pick_button(app, ui, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(PICK_W, CONTROL_H)), photo.flag == Flag::Pick);
    x += PICK_W + GAP;
    reject_button(app, ui, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(CONTROL_H, CONTROL_H)), photo.flag == Flag::Reject);
    x += CONTROL_H + 10.0;
    let star_row = Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(5.0 * STAR_CELL, CONTROL_H));
    stars(app, ui, star_row, photo.rating, STAR_CELL, STAR);
    x += 5.0 * STAR_CELL + GROUP_GAP;

    if app.ui.right == RightPanel::Masking {
        mask_switch(app, ui, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(MASK_SWITCH_W, CONTROL_H)));
    } else if app.ui.right == RightPanel::Crop {
        if bar_button(
            ui,
            "beforeAfter",
            Icon::BeforeAfter,
            Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(CONTROL_H, CONTROL_H)),
            20.0,
            true,
            "Before and After",
        )
        .clicked()
        {
            let _ = app.run("view.beforeAfter", json!({}));
        }
        x += CONTROL_H + GAP;
        let more =
            bar_button(ui, "more", Icon::More, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(CONTROL_H, CONTROL_H)), 20.0, true, "More");
        egui::Popup::menu(&more).show(|ui| {
            crate::widgets::touch_menu_style(ui);
            if ui.button(crate::i18n::tr("Reset Crop")).clicked() {
                let _ = app.run("crop.reset", json!({}));
                ui.close();
            }
            if ui.button(crate::i18n::tr("Rotate Crop Aspect")).clicked() {
                let _ = app.run("crop.rotateAspect", json!({}));
                ui.close();
            }
        });
    } else {
        if bar_button(ui, "sort", Icon::Sort, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(CONTROL_H, CONTROL_H)), 20.0, true, "Filters")
            .clicked()
        {
            let _ = app.run("view.filterBar", json!({}));
        }
        x += CONTROL_H + GAP;
        if bar_button(ui, "share", Icon::Share, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(CONTROL_H, CONTROL_H)), 22.0, true, "Share")
            .clicked()
        {
            let _ = app.run("dialog.export", json!({}));
        }
    }
}

/// The phone's bar: back and the centred file name (the rating cluster is its own capsule below).
fn phone_bar(app: &mut LightcraftApp, ui: &mut egui::Ui, rect: Rect, photo: &Photo) {
    let cy = rect.center().y;
    let mut x = rect.left();
    if bar_button(ui, "back", Icon::Back, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(CONTROL_H, CONTROL_H)), 16.0, true, "Back")
        .clicked()
    {
        let _ = app.run("view.photoGrid", json!({}));
    }
    x += CONTROL_H + GROUP_GAP;
    name_and_tag(app, ui, photo, x, rect.right() - GROUP_GAP, cy);
}

/// The phone's floating rating capsule: pick, reject and the five stars, inset from its edge.
fn phone_rating(app: &mut LightcraftApp, ui: &mut egui::Ui, rect: Rect, photo: &Photo) {
    let cy = rect.center().y;
    let mut x = rect.left() + PHONE_INSET;
    pick_button(app, ui, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(CONTROL_H, CONTROL_H)), photo.flag == Flag::Pick);
    x += CONTROL_H + GAP;
    reject_button(app, ui, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(CONTROL_H, CONTROL_H)), photo.flag == Flag::Reject);
    x += CONTROL_H + 6.0;
    stars(app, ui, Rect::from_min_size(pos2(x, cy - CONTROL_H / 2.0), vec2(5.0 * STAR_CELL, CONTROL_H)), photo.rating, STAR_CELL, STAR);
}

/// One 44-point bar button: its icon, a soft oval while hovered or pressed, and its screen-reader
/// name. Painted at `rect`, so the bar's layout stays exact whatever the screen width.
fn bar_button(ui: &mut egui::Ui, id: &str, icon: Icon, rect: Rect, side: f32, enabled: bool, name: &str) -> Response {
    let t = Tokens::get(ui.ctx());
    let resp = ui.interact(rect, Id::unique(("photo-bar", id)), if enabled { Sense::click() } else { Sense::hover() });
    if enabled {
        announce(&resp, crate::i18n::tr(name));
    } else {
        resp.widget_info(|| egui::WidgetInfo::labeled(egui::Role::Button, false, crate::i18n::tr(name)));
    }
    register(ui, format!("photoBar:{id}"), rect);
    if ui.is_rect_visible(rect) {
        let down = resp.is_pointer_button_down_on();
        if enabled && (resp.hovered() || down) {
            let alpha = if down { 40 } else { 24 };
            ui.painter().rect_filled(rect, rect.height() / 2.0, soft(alpha));
        }
        let ink = if !enabled {
            t.text_disabled
        } else if resp.hovered() {
            Color32::WHITE
        } else {
            t.text
        };
        paint(ui.painter(), Rect::from_center_size(rect.center(), vec2(side, side)), icon, ink);
    }
    resp
}

/// The file name, centred in `[left, right]`, with its small tag beside it in secondary ink.
fn name_and_tag(app: &LightcraftApp, ui: &mut egui::Ui, photo: &Photo, left: f32, right: f32, cy: f32) {
    let t = Tokens::get(ui.ctx());
    let room = (right - left).max(1.0);
    let name = display_name(&photo.file_name);
    let tag = tag(app, photo);
    let tag_room =
        tag.map_or(0.0, |word| one_line(ui.painter(), crate::i18n::tr(word), t.font(TAG_SIZE), secondary(), f32::INFINITY).size().x + GROUP_GAP);
    let galley = one_line(ui.painter(), &name, t.semibold(NAME_SIZE), t.text, (room - tag_room).max(1.0));
    let total = (galley.size().x + tag_room).min(room);
    let x = left + ((room - total) / 2.0).max(0.0);
    let p = ui.painter();
    p.galley(pos2(x, cy - galley.size().y / 2.0), galley.clone(), t.text);
    if let Some(word) = tag {
        let g = one_line(p, crate::i18n::tr(word), t.font(TAG_SIZE), secondary(), (room - galley.size().x - GROUP_GAP).max(1.0));
        p.galley(pos2(x + galley.size().x + GROUP_GAP, cy - g.size().y / 2.0), g, secondary());
    }
}

/// The pick flag: a green tinted capsule carrying a pennant while the photo is picked, a quiet
/// white flag otherwise. Tapping it toggles the pick (the same command as the bottom bar's rater).
fn pick_button(app: &mut LightcraftApp, ui: &mut egui::Ui, rect: Rect, picked: bool) -> Response {
    let t = Tokens::get(ui.ctx());
    let resp = ui.interact(rect, Id::unique(("photo-bar", "pick")), Sense::click());
    announce_selected(&resp, crate::i18n::tr("Pick"), picked);
    register(ui, "photoBar:pick", rect);
    if ui.is_rect_visible(rect) {
        let down = resp.is_pointer_button_down_on();
        let fill = if picked {
            let alpha = if down {
                FLAG_TINT.saturating_add(20)
            } else if resp.hovered() {
                FLAG_TINT.saturating_add(10)
            } else {
                FLAG_TINT
            };
            Color32::from_rgba_unmultiplied(t.pick.r(), t.pick.g(), t.pick.b(), alpha)
        } else if resp.hovered() || down {
            soft(if down { 40 } else { 24 })
        } else {
            Color32::TRANSPARENT
        };
        if fill.a() > 0 {
            ui.painter().rect_filled(rect, rect.height() / 2.0, fill);
        }
        let ink = if picked {
            lighter(t.pick, 0.15)
        } else if resp.hovered() {
            Color32::WHITE
        } else {
            t.text
        };
        paint(ui.painter(), Rect::from_center_size(rect.center(), vec2(20.0, 20.0)), Icon::FlagPickFilled, ink);
    }
    if resp.clicked() {
        set_flag(app, if picked { Flag::None } else { Flag::Pick });
    }
    resp
}

/// The reject cross, red as the design draws it, on a red tint once the photo is rejected. Tapping
/// it toggles the reject (the same command as the bottom bar's rater).
fn reject_button(app: &mut LightcraftApp, ui: &mut egui::Ui, rect: Rect, rejected: bool) -> Response {
    let t = Tokens::get(ui.ctx());
    let resp = ui.interact(rect, Id::unique(("photo-bar", "reject")), Sense::click());
    announce_selected(&resp, crate::i18n::tr("Reject"), rejected);
    register(ui, "photoBar:reject", rect);
    if ui.is_rect_visible(rect) {
        let down = resp.is_pointer_button_down_on();
        let fill = if rejected {
            let alpha = if down {
                FLAG_TINT.saturating_add(20)
            } else if resp.hovered() {
                FLAG_TINT.saturating_add(10)
            } else {
                FLAG_TINT
            };
            Color32::from_rgba_unmultiplied(t.reject.r(), t.reject.g(), t.reject.b(), alpha)
        } else if resp.hovered() || down {
            soft(if down { 40 } else { 24 })
        } else {
            Color32::TRANSPARENT
        };
        if fill.a() > 0 {
            ui.painter().rect_filled(rect, rect.height() / 2.0, fill);
        }
        let ink = if rejected { Color32::WHITE } else { lighter(t.reject, 0.32) };
        paint(ui.painter(), Rect::from_center_size(rect.center(), vec2(18.0, 18.0)), Icon::FlagReject, ink);
    }
    if resp.clicked() {
        set_flag(app, if rejected { Flag::None } else { Flag::Reject });
    }
    resp
}

/// Five stars in `rect`, the first `rating` filled yellow: a tap sets the rating, a tap on the
/// current rating clears it (as the bottom bar's rater does).
fn stars(app: &mut LightcraftApp, ui: &mut egui::Ui, rect: Rect, rating: u8, cell: f32, side: f32) {
    let t = Tokens::get(ui.ctx());
    let mut hovered = None;
    let mut picked = None;
    let mut cells = [Rect::NOTHING; 5];
    for (i, slot) in cells.iter_mut().enumerate() {
        let n = (i + 1) as u8;
        let r = Rect::from_min_size(pos2(rect.left() + i as f32 * cell, rect.top()), vec2(cell, rect.height()));
        let resp = ui.interact(r, Id::unique(("photo-bar-star", i)), Sense::click());
        announce_selected(&resp, format!("{n} ★"), i < usize::from(rating));
        register(ui, format!("photoBar:star{n}"), r);
        if resp.hovered() {
            hovered = Some(n);
        }
        if resp.clicked() {
            picked = Some(if rating == n { 0 } else { n });
        }
        *slot = r;
    }
    let lit = hovered.unwrap_or(rating);
    for (i, r) in cells.iter().enumerate() {
        let filled = (i + 1) as u8 <= lit;
        let ink = if filled { t.star } else { t.text_label };
        crate::rating::paint_star(ui.painter(), Rect::from_center_size(r.center(), vec2(side, side)), filled, ink);
    }
    if let Some(n) = picked {
        let mut params = json!({ "rating": n });
        crate::panels::compare::target_active(app, &mut params);
        let _ = app.run("photo.rate", params);
    }
}

/// Masking's Overlay / Outline / Off switch: the overlay, the mask as a white stencil, or nothing.
fn mask_switch(app: &mut LightcraftApp, ui: &mut egui::Ui, rect: Rect) {
    let mut selected = if !app.ui.mask_overlay {
        2
    } else if app.ui.mask_overlay_mode == "whiteOnBlack" {
        1
    } else {
        0
    };
    let mut child = ui.new_child(egui::UiBuilder::new().max_rect(rect).layout(egui::Layout::left_to_right(egui::Align::Center)));
    let resp = crate::ui_kit_touch::segmented(&mut child, &["Overlay", "Outline", "Off"], &mut selected);
    if resp.changed() {
        match selected {
            1 => {
                app.ui.mask_overlay = true;
                let _ = app.run("view.maskOverlayMode", json!({ "mode": "whiteOnBlack" }));
            }
            2 => app.ui.mask_overlay = false,
            _ => {
                app.ui.mask_overlay = true;
                let _ = app.run("view.maskOverlayMode", json!({ "mode": "color" }));
            }
        }
    }
}

/// Set the active photo's flag through the same command the bottom bar's rater uses.
fn set_flag(app: &mut LightcraftApp, flag: Flag) {
    let mut params = json!({ "flag": match flag {
        Flag::Pick => "pick",
        Flag::Reject => "reject",
        Flag::None => "none",
    } });
    crate::panels::compare::target_active(app, &mut params);
    let _ = app.run("photo.flag", params);
}

#[cfg(test)]
mod tests {
    use super::display_name;

    /// The bar shows the file's stem: the extension never appears, and nothing is lost to a bad or
    /// missing name (the bar must keep drawing for an unnamed photo).
    #[test]
    fn the_bar_shows_the_file_stem_without_an_extension() {
        for (file, shown) in [
            ("LC01221.JPG", "LC01221"),
            ("_MG_0042.CR3", "_MG_0042"),
            ("sunset.2026.edit.tiff", "sunset.2026.edit"),
            ("no_extension", "no_extension"),
            ("", ""),
        ] {
            assert_eq!(display_name(file), shown, "file name {file:?}");
        }
    }
}
