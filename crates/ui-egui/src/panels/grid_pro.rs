//! The desktop "Pro" Library grid: rounded square tiles with a bottom scrim, star / flag / colour
//! label overlays and the selection states, marquee selection, and the right-click menu. Every entry
//! point is reached from `grid.rs` only when [`crate::theme::desktop_pro`] is on.

use egui::epaint::{Mesh, Vertex, WHITE_UV};
use egui::{Color32, Pos2, Rect, Response, Sense, Stroke, StrokeKind, pos2, vec2};
use lightcraft_catalog::{Flag, Photo, PhotoId};
use lightcraft_engine::SelectionState;
use serde_json::json;

use super::chrome_pro::{self as pro, TILE_RADIUS};
use crate::LightcraftApp;
use crate::icons::{Icon, paint};
use crate::theme::{Tokens, label_color};
use crate::widgets::register;

/// Extra side padding the layout adds to its own 4 pt (10 pt in all).
pub const INSET: f32 = 6.0;
/// Date header height.
pub const HEADER_H: f32 = 34.0;
/// Tiles narrower than this show their overlays only on hover.
const OVERLAY_MIN: f32 = 100.0;
/// Width of one star slot in the tile's rating row.
const STAR_PITCH: f32 = 12.0;

/// The part of a texture `size` that fills `r` without stretching (centred crop), as a UV rect.
pub fn cover_uv(size: [usize; 2], r: Rect) -> Rect {
    let (tw, th) = (size[0] as f32, size[1] as f32);
    let full = Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0));
    if tw < 1.0 || th < 1.0 || r.width() < 1.0 || r.height() < 1.0 {
        return full;
    }
    let (ta, ra) = (tw / th, r.width() / r.height());
    if ta > ra {
        let w = ra / ta;
        Rect::from_min_max(pos2((1.0 - w) / 2.0, 0.0), pos2((1.0 + w) / 2.0, 1.0))
    } else {
        let h = ta / ra;
        Rect::from_min_max(pos2(0.0, (1.0 - h) / 2.0), pos2(1.0, (1.0 + h) / 2.0))
    }
}

/// A black-to-transparent scrim over the bottom `h` of a rounded tile.
fn scrim(p: &egui::Painter, r: Rect, h: f32, alpha: u8) {
    let strip = 2.0;
    let n = (h / strip).ceil().max(1.0) as usize;
    let mut mesh = Mesh::default();
    let radius = TILE_RADIUS;
    let colour = |y: f32| {
        let f = ((y - (r.bottom() - h)) / h).clamp(0.0, 1.0);
        Color32::from_black_alpha((f * f.sqrt() * alpha as f32) as u8)
    };
    // how far the rounded corner pulls the tile's edge in at height `y`
    let inset = |y: f32| {
        let d = y - (r.bottom() - radius);
        if d <= 0.0 { 0.0 } else { radius - (radius * radius - d * d).max(0.0).sqrt() }
    };
    for i in 0..n {
        let y0 = r.bottom() - h + i as f32 * strip;
        let y1 = (y0 + strip).min(r.bottom());
        let (i0, i1) = (inset(y0), inset(y1));
        let base = mesh.vertices.len() as u32;
        for (x, y, c) in
            [(r.left() + i0, y0, colour(y0)), (r.right() - i0, y0, colour(y0)), (r.right() - i1, y1, colour(y1)), (r.left() + i1, y1, colour(y1))]
        {
            mesh.vertices.push(Vertex { pos: pos2(x, y), uv: WHITE_UV, color: c });
        }
        mesh.indices.extend_from_slice(&[base, base + 1, base + 2, base, base + 2, base + 3]);
    }
    p.add(egui::Shape::mesh(mesh));
}

/// The row of stars at the tile's bottom left: `(first star's rect, pitch)`.
fn star_row(r: Rect) -> Rect {
    Rect::from_min_size(pos2(r.left() + 8.0, r.bottom() - 22.0), vec2(STAR_PITCH * 5.0, 18.0))
}

/// The flag's hit area at the bottom right.
fn flag_rect(r: Rect) -> Rect {
    Rect::from_min_size(pos2(r.right() - 24.0, r.bottom() - 22.0), vec2(20.0, 18.0))
}

/// Everything drawn over a tile's photo: scrim, rating, flag, colour label, file name and the
/// hover / selection outline.
pub fn tile_overlay(app: &LightcraftApp, ui: &egui::Ui, id: PhotoId, photo: &Photo, r: Rect, resp: &Response, state: SelectionState) {
    let _ = (app, id);
    let t = Tokens::get(ui.ctx());
    let p = ui.painter();
    let hovered = resp.hovered();
    let selected = state != SelectionState::NotSelected;
    let active = state == SelectionState::Active;
    let show = r.width() >= OVERLAY_MIN || hovered || selected;
    if selected {
        p.rect_filled(r, TILE_RADIUS, pro::accent_bg(&t));
    }
    if show {
        scrim(p, r, (r.height() * 0.4).max(28.0), if hovered { 120 } else { 150 });
        // rating: only when rated, or all five slots on hover
        let star_col = if selected { Color32::from_rgb(0xff, 0xd6, 0x0a) } else { Color32::WHITE };
        let row = star_row(r);
        let hover_star = if hovered { hovered_star(ui, r) } else { None };
        let lit = hover_star.unwrap_or(photo.rating as usize);
        if photo.rating > 0 || hovered {
            for i in 0..5 {
                let c = pos2(row.left() + STAR_PITCH * (i as f32 + 0.5), row.center().y);
                let sr = Rect::from_center_size(c, vec2(10.0, 10.0));
                if i < lit {
                    paint(p, sr, Icon::StarFilled, star_col);
                } else if hovered {
                    paint(p, sr, Icon::Star, Color32::from_white_alpha(110));
                }
            }
        }
        // flag
        let fr = Rect::from_center_size(flag_rect(r).center(), vec2(11.0, 11.0));
        match photo.flag {
            Flag::Pick => paint(p, fr, Icon::FlagPickFilled, Color32::WHITE),
            Flag::Reject => paint(p, fr, Icon::FlagReject, Color32::from_rgb(0xff, 0x6a, 0x60)),
            Flag::None if hovered => paint(p, fr, Icon::FlagPick, Color32::from_white_alpha(110)),
            Flag::None => {}
        }
    }
    if let Some(l) = photo.label {
        let c = pos2(r.right() - 12.0, r.top() + 12.0);
        p.circle(c, 4.5, label_color(l), Stroke::new(1.5, Color32::from_black_alpha(160)));
    }
    if hovered || selected {
        let galley = p.layout_no_wrap(photo.file_name.clone(), t.font(10.0), Color32::WHITE);
        let at = pos2(r.left() + 8.0, r.top() + 6.0);
        let shadow = p.layout_no_wrap(photo.file_name.clone(), t.font(10.0), Color32::from_black_alpha(150));
        if galley.size().x < r.width() - 30.0 {
            p.galley(at + vec2(0.5, 0.5), shadow, Color32::BLACK);
            p.galley(at, galley, Color32::WHITE);
        }
    }
    // outline: primary (anchor) 3 pt accent + 1 pt white inside, others 2 pt accent, hover 1 pt white
    if active {
        p.rect_stroke(r.shrink(1.5), TILE_RADIUS - 1.5, Stroke::new(3.0, t.accent), StrokeKind::Middle);
        p.rect_stroke(r.shrink(3.5), (TILE_RADIUS - 3.5).max(0.0), Stroke::new(1.0, Color32::WHITE), StrokeKind::Inside);
    } else if selected {
        p.rect_stroke(r.shrink(1.0), TILE_RADIUS - 1.0, Stroke::new(2.0, t.accent), StrokeKind::Middle);
    } else if hovered {
        p.rect_stroke(r, TILE_RADIUS, Stroke::new(1.0, Color32::from_white_alpha(90)), StrokeKind::Inside);
    }
}

/// The star under the pointer (1-based count of lit stars), if it is over the rating row.
fn hovered_star(ui: &egui::Ui, r: Rect) -> Option<usize> {
    let pos = ui.input(|i| i.pointer.hover_pos())?;
    let row = star_row(r);
    if !row.contains(pos) {
        return None;
    }
    let n = ((pos.x - row.left()) / STAR_PITCH).floor();
    (n >= 0.0).then(|| (n as usize + 1).min(5))
}

/// A click on a tile's hover stars or flag rates or flags that photo; true when it was one.
pub fn quick_action(app: &mut LightcraftApp, ui: &egui::Ui, photo: &Photo, r: Rect) -> bool {
    if r.width() < OVERLAY_MIN * 0.6 {
        return false;
    }
    let Some(pos) = ui.input(|i| i.pointer.interact_pos()) else { return false };
    if let Some(n) = hovered_star(ui, r) {
        let rating = if photo.rating as usize == n { 0 } else { n };
        let _ = app.run("photo.rate", json!({"ids": [photo.id.0], "rating": rating}));
        return true;
    }
    if flag_rect(r).contains(pos) {
        let flag = if photo.flag == Flag::Pick { "none" } else { "pick" };
        let _ = app.run("photo.flag", json!({"ids": [photo.id.0], "flag": flag}));
        return true;
    }
    false
}

// ------------------------------------------------------------------ marquee selection

/// What the marquee remembers while a drag is going: where it began (content coordinates), what was
/// selected before (kept when Shift / Cmd is held) and what it last selected.
#[derive(Clone, Default)]
struct MarqueeState {
    start: Pos2,
    base: Vec<u64>,
    last: Vec<u64>,
}

fn marquee_id() -> egui::Id {
    egui::Id::unique("pro-marquee-state")
}

/// The empty-space drag area behind the tiles; make it before the tiles so they win their own clicks.
pub fn marquee_begin(ui: &mut egui::Ui, area: Rect, viewport: Rect) -> Response {
    let _ = viewport;
    ui.interact(area, egui::Id::unique("pro-marquee"), Sense::drag())
}

/// Run the marquee for this frame: start, update the selection while dragging, draw, finish.
pub fn marquee_end(app: &mut LightcraftApp, ui: &mut egui::Ui, resp: Response, cells: &[Rect], ids: &[PhotoId], origin: Pos2, viewport: Rect) {
    let _ = viewport;
    let t = Tokens::get(ui.ctx());
    if resp.drag_started_by(egui::PointerButton::Primary)
        && let Some(press) = ui.input(|i| i.pointer.press_origin())
    {
        let additive = ui.input(|i| i.modifiers.shift || i.modifiers.command);
        let base = if additive { app.session.selection.ids.iter().map(|p| p.0).collect() } else { Vec::new() };
        let st = MarqueeState { start: press - origin.to_vec2(), base, last: Vec::new() };
        ui.data_mut(|d| d.insert_temp(marquee_id(), st));
        if !additive {
            let _ = app.run("library.selectNone", json!({}));
        }
    }
    if resp.drag_stopped() {
        ui.data_mut(|d| d.remove_temp::<MarqueeState>(marquee_id()));
        return;
    }
    if !resp.dragged() {
        return;
    }
    let Some(mut st) = ui.data(|d| d.get_temp::<MarqueeState>(marquee_id())) else { return };
    let Some(cur) = ui.input(|i| i.pointer.latest_pos()) else { return };
    let rect = Rect::from_two_pos(st.start, cur - origin.to_vec2());
    let mut picked = st.base.clone();
    for (cell, id) in cells.iter().zip(ids) {
        if cell.intersects(rect) && !picked.contains(&id.0) {
            picked.push(id.0);
        }
    }
    if picked != st.last {
        if picked.is_empty() {
            let _ = app.run("library.selectNone", json!({}));
        } else {
            let _ = app.run("library.select", json!({"ids": picked.clone(), "mode": "replace"}));
        }
        st.last = picked;
    }
    // near the top or bottom edge the grid scrolls
    let clip = ui.clip_rect();
    let edge = 28.0;
    let speed = if cur.y < clip.top() + edge {
        ((clip.top() + edge - cur.y) * 0.6).min(24.0)
    } else if cur.y > clip.bottom() - edge {
        -((cur.y - (clip.bottom() - edge)) * 0.6).min(24.0)
    } else {
        0.0
    };
    if speed != 0.0 {
        ui.scroll_with_delta(vec2(0.0, speed));
        ui.ctx().request_repaint();
    }
    let a = t.accent;
    let screen = rect.translate(origin.to_vec2());
    ui.painter().rect_filled(screen, 2.0, Color32::from_rgba_unmultiplied(a.r(), a.g(), a.b(), 36));
    ui.painter().rect_stroke(screen, 2.0, Stroke::new(1.0, a), StrokeKind::Inside);
    ui.data_mut(|d| d.insert_temp(marquee_id(), st));
    register(ui, "grid:marquee", screen);
}

// ------------------------------------------------------------------ right-click menu

/// A menu row with its shortcut right-aligned: the key the command is bound to now (or `fallback`).
fn item(app: &LightcraftApp, ui: &mut egui::Ui, label: &str, cmd: &str, fallback: &str, enabled: bool) -> Response {
    let mac = ui.ctx().os() == egui::os::OperatingSystem::Mac;
    let key = match crate::shortcuts::shortcut_of(&app.ui.settings.keymap, cmd) {
        Some(sc) => crate::menubar::shortcut_text(sc, mac),
        None if fallback.is_empty() => String::new(),
        None => crate::menubar::shortcut_text(fallback, mac),
    };
    let button = egui::Button::new(crate::i18n::tr(label)).shortcut_text(egui::RichText::new(key).weak());
    ui.add_enabled(enabled, button)
}

/// The Pro right-click menu for the tile `id` (the selection, once it is made).
pub fn context_menu(app: &mut LightcraftApp, ui: &mut egui::Ui, id: PhotoId) {
    if !app.session.selection.contains(id) {
        let _ = app.run("library.select", json!({"ids": [id.0]}));
    }
    ui.set_min_width(250.0);
    let n = app.session.selection.ids.len();
    if n > 1 {
        ui.add_enabled(false, egui::Button::new(crate::i18n::tr_format!("{n} photos", n = n)));
        ui.separator();
    }
    if item(app, ui, "Open in Detail", "", "Enter", true).clicked() {
        let _ = app.run("view.detail", json!({}));
    }
    if item(app, ui, "Compare", "view.compare", "Shift+C", true).clicked() {
        let _ = app.run("view.compare", json!({}));
    }
    ui.separator();
    ui.add_enabled_ui(crate::menus::ui_enabled(app, "photo.editInPhotoCraft"), |ui| {
        crate::widgets::menu_button(ui, crate::i18n::tr("Edit In"), |ui| {
            if item(app, ui, "Edit in PhotoCraft", "photo.editInPhotoCraft", "Cmd+Shift+E", true).clicked() {
                let _ = app.run("photo.editInPhotoCraft", json!({}));
            }
            if item(app, ui, "Edit in Other Editor", "photo.editInExternal", "Cmd+Alt+E", true).clicked() {
                let _ = app.run("photo.editInExternal", json!({}));
            }
            let on = crate::menus::ui_enabled(app, "photo.openOriginalInExternal");
            if item(app, ui, "Open Original in Other Editor (RAW, no copy)", "photo.openOriginalInExternal", "", on).clicked() {
                let _ = app.run("photo.openOriginalInExternal", json!({}));
            }
        });
    });
    if ui.button(crate::i18n::tr("Find Similar Photos")).clicked() {
        match app.run("library.findSimilar", json!({"id": id.0})) {
            Ok(r) => {
                let n = r["photos"].as_array().map_or(0, Vec::len);
                app.ui.view = crate::state::ViewMode::PhotoGrid;
                app.toast(
                    ui.ctx(),
                    crate::i18n::tr_format!("{n} similar photo{} · View ▸ Clear Filters to see all", if n == 1 { "" } else { "s" }, n = n),
                );
            }
            Err(e) => app.toast(ui.ctx(), e),
        }
    }
    let live = super::compare::live(app, id);
    if ui.add_enabled(live, egui::Button::new(crate::i18n::tr("Set as Reference Photo"))).clicked()
        && let Err(e) = app.run("photo.setReference", json!({"id": id.0}))
    {
        app.toast(ui.ctx(), e);
    }
    ui.separator();
    let current = app.session.catalog.photo(id).map(|p| (p.rating, p.flag));
    crate::widgets::menu_button(ui, crate::i18n::tr("Set Rating"), |ui| {
        for r in 0..=5u8 {
            let label = if r == 0 { crate::i18n::tr("No Stars").to_string() } else { "★".repeat(r as usize) };
            let on = current.is_some_and(|(cr, _)| cr == r);
            let b = egui::Button::new(label).shortcut_text(egui::RichText::new(r.to_string()).weak()).selected(on);
            if ui.add(b).clicked() {
                let _ = app.run("photo.rate", json!({"rating": r}));
            }
        }
    });
    crate::widgets::menu_button(ui, crate::i18n::tr("Set Flag"), |ui| {
        for (l, f, key, flag) in [("Pick", "pick", "P", Flag::Pick), ("Reject", "reject", "X", Flag::Reject), ("Unflagged", "none", "U", Flag::None)]
        {
            let on = current.is_some_and(|(_, cf)| cf == flag);
            let b = egui::Button::new(crate::i18n::tr(l)).shortcut_text(egui::RichText::new(key).weak()).selected(on);
            if ui.add(b).clicked() {
                let _ = app.run("photo.flag", json!({"flag": f}));
            }
        }
    });
    crate::widgets::menu_button(ui, crate::i18n::tr("Set Color Label"), |ui| super::grid::label_menu(app, ui));
    if super::grid::local_only(app, &app.session.selected()) {
        let add = ui.add_enabled(false, egui::Button::new(crate::i18n::tr("Add to Album"))).on_disabled_hover_text(super::grid::albums_hint());
        register(ui, "button:contextAddToAlbum", add.rect);
    } else {
        let add = crate::widgets::menu_button(ui, crate::i18n::tr("Add to Album"), |ui| {
            let albums: Vec<_> = app.session.catalog.albums().filter(|a| !a.folder && !a.is_smart()).map(|a| (a.id.0, a.name.clone())).collect();
            let any = !albums.is_empty();
            for (aid, name) in albums {
                let b = ui.button(name);
                register(ui, format!("button:contextAlbum:{aid}"), b.rect);
                if b.clicked() {
                    match app.run("album.addPhotos", json!({"id": aid})) {
                        Ok(r) => super::grid::toast_skipped(app, ui.ctx(), &r),
                        Err(e) => app.toast(ui.ctx(), e),
                    }
                }
            }
            if any {
                ui.separator();
            }
            if item(app, ui, "New Album…", "dialog.newAlbum", "Cmd+N", true).clicked() {
                let _ = app.run("dialog.newAlbum", json!({}));
            }
        });
        register(ui, "button:contextAddToAlbum", add.response.rect);
    }
    if item(app, ui, "Add Keywords…", "panel.addKeywords", "Cmd+K", true).clicked() {
        let _ = app.run("panel.addKeywords", json!({}));
    }
    ui.separator();
    if item(app, ui, "Copy Edit Settings…", "dialog.copySettings", "Cmd+Shift+C", true).clicked() {
        let _ = app.run("dialog.copySettings", json!({}));
    }
    let has_clip = app.session.clipboard.is_some();
    if item(app, ui, "Paste Edit Settings…", "dialog.pasteSettings", "Cmd+Shift+V", has_clip).clicked() {
        let _ = app.run("dialog.pasteSettings", json!({}));
    }
    if ui.add_enabled(n > 1, egui::Button::new(crate::i18n::tr("Sync Settings…"))).clicked() {
        let _ = app.run("develop.sync", json!({}));
    }
    ui.separator();
    if item(app, ui, "Export…", "dialog.export", "Cmd+Shift+X", true).clicked() {
        let _ = app.run("dialog.export", json!({}));
    }
    if item(app, ui, "Rename Photos…", "dialog.rename", "F2", true).clicked() {
        let _ = app.run("dialog.rename", json!({}));
    }
    let can_reveal = crate::menus::ui_enabled(app, "app.showInFinder");
    if item(app, ui, crate::menus::reveal_label(), "app.showInFinder", "Cmd+R", can_reveal).clicked() {
        let _ = app.run("app.showInFinder", json!({}));
    }
    crate::widgets::menu_button(ui, crate::i18n::tr("More"), |ui| super::grid::classic_context_menu(app, ui, id));
    ui.separator();
    let in_album = match app.session.source {
        lightcraft_engine::LibrarySource::Album(aid) if app.session.catalog.album(aid).is_some_and(|a| !a.folder && !a.is_smart()) => Some(aid),
        _ => None,
    };
    let danger = egui::Color32::from_rgb(0xff, 0x6a, 0x60);
    let (label, key) = if in_album.is_some() { ("Remove from Album", "Delete") } else { ("Remove from Library", "Delete") };
    let b = egui::Button::new(egui::RichText::new(crate::i18n::tr(label)).color(danger)).shortcut_text(egui::RichText::new(key).weak());
    let remove = ui.add(b);
    register(ui, "button:contextDeletePhoto", remove.rect);
    if remove.clicked() {
        match in_album {
            Some(aid) => {
                let _ = app.run("album.removePhotos", json!({"id": aid.0}));
            }
            None => {
                let _ = crate::menubar::run_item(app, "photo.delete", json!({}));
            }
        }
    }
}
