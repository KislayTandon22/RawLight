//! The Pro desktop Export dialog: two panes. On the left the live watermark preview, the saved
//! watermarks and the portable-file buttons; on the right the existing form with collapsible
//! sections (the rows themselves are the Classic dialog's, in `panels::dialogs`). Only used when
//! [`crate::theme::desktop_pro`] is on.

use egui::{Align, Color32, CornerRadius, Layout, Pos2, Rect, RichText, Sense, Stroke, StrokeKind, Ui, vec2};
use lightcraft_engine::export::{Anchor, ExportOptions, Resize, Watermark};

use crate::LightcraftApp;
use crate::panels::dialogs as d;
use crate::pro_ui;
use crate::theme::Tokens;
use crate::watermark_store::{self, Saved};

/// Width of the left pane.
pub const LEFT_W: f32 = 470.0;
/// The least size of the Pro Export window.
pub const MIN_SIZE: egui::Vec2 = egui::vec2(980.0, 640.0);

/// The nine anchors in reading order (the grid's tab/arrow order).
pub const ANCHORS: [Anchor; 9] = [
    Anchor::TopLeft,
    Anchor::Top,
    Anchor::TopRight,
    Anchor::Left,
    Anchor::Center,
    Anchor::Right,
    Anchor::BottomLeft,
    Anchor::Bottom,
    Anchor::BottomRight,
];

/// The cell index (0..9) of `a`.
pub fn anchor_index(a: Anchor) -> usize {
    ANCHORS.iter().position(|x| *x == a).unwrap_or(8)
}

/// Where the cursor goes from cell `i` on an arrow key (clamped at the edges), `Home` = 0, `End` = 8.
pub fn grid_step(i: usize, key: egui::Key) -> usize {
    let (r, c) = (i / 3, i % 3);
    match key {
        egui::Key::ArrowLeft => r * 3 + c.saturating_sub(1),
        egui::Key::ArrowRight => r * 3 + (c + 1).min(2),
        egui::Key::ArrowUp => r.saturating_sub(1) * 3 + c,
        egui::Key::ArrowDown => (r + 1).min(2) * 3 + c,
        egui::Key::Home => 0,
        egui::Key::End => 8,
        _ => i,
    }
}

/// Why Export can't start (shown under the watermark text and disabling the default button).
pub fn invalid(opts: &ExportOptions) -> Option<&'static str> {
    let wm = opts.watermark.as_ref()?;
    if wm.image.trim().is_empty() {
        (wm.text.trim().is_empty() && wm.background_opacity <= 0.0 && wm.border_width <= 0.0).then_some("Add text or switch to Graphic")
    } else {
        (!std::path::Path::new(wm.image.trim()).is_file()).then_some("File not found")
    }
}

/// The dialog body: left pane, right pane. `pane_h` is the height both get.
#[allow(clippy::too_many_arguments)]
pub fn layout(
    app: &mut LightcraftApp,
    ui: &mut Ui,
    t: &Tokens,
    pane_h: f32,
    opts: &mut ExportOptions,
    full_size: &mut bool,
    resize: &mut Resize,
    preset_name: &mut String,
    limit_kb: &mut u32,
    dir: &mut String,
) {
    ui.horizontal_top(|ui| {
        ui.spacing_mut().item_spacing.x = 14.0;
        ui.allocate_ui_with_layout(vec2(LEFT_W, pane_h), Layout::top_down(Align::Min), |ui| {
            ui.set_width(LEFT_W);
            left_pane(app, ui, pane_h, opts, *full_size, *resize);
        });
        let w = ui.available_width().max(300.0);
        ui.allocate_ui_with_layout(vec2(w, pane_h), Layout::top_down(Align::Min), |ui| {
            egui::ScrollArea::vertical().id_salt("export-pro-form").max_height(pane_h).auto_shrink([false, false]).show(ui, |ui| {
                ui.set_width(w - 14.0);
                d::export_body(app, ui, t, opts, full_size, resize, preset_name, limit_kb, dir);
            });
        });
    });
}

fn sample_id() -> egui::Id {
    egui::Id::unique("lightcraft-export-wm-sample")
}

fn saved_id() -> egui::Id {
    egui::Id::unique("lightcraft-export-wm-saved")
}

/// The saved watermarks, read from disk once and again after a change.
fn saved_list(ctx: &egui::Context) -> std::sync::Arc<Vec<Saved>> {
    if let Some(list) = ctx.data(|d| d.get_temp::<std::sync::Arc<Vec<Saved>>>(saved_id())) {
        return list;
    }
    let list = std::sync::Arc::new(watermark_store::dir().map(|d| watermark_store::list_in(&d)).unwrap_or_default());
    ctx.data_mut(|d| d.insert_temp(saved_id(), list.clone()));
    list
}

/// Forget the cached list (after a save, delete or import).
pub fn refresh_saved(ctx: &egui::Context) {
    ctx.data_mut(|d| d.remove_temp::<std::sync::Arc<Vec<Saved>>>(saved_id()));
}

fn left_pane(app: &mut LightcraftApp, ui: &mut Ui, pane_h: f32, opts: &mut ExportOptions, full_size: bool, resize: Resize) {
    let t = Tokens::get(ui.ctx());
    pro_ui::caps(ui, "Live preview");
    let n_samples = app.session.selected().len().clamp(1, 3);
    let mut sample: usize = ui.data(|d| d.get_temp(sample_id())).unwrap_or(0);
    if sample >= n_samples {
        sample = 0;
    }
    let shown = opts.watermark.clone().unwrap_or_else(|| Watermark { text: String::new(), ..Default::default() });
    let before = ui.cursor().top();
    d::watermark_preview(app, ui, &shown, (!full_size).then_some(resize), sample, (pane_h * 0.40).max(180.0));
    let preview_h = ui.cursor().top() - before;
    ui.horizontal(|ui| {
        let name =
            app.session.selected().get(sample).and_then(|id| app.session.catalog.photo(*id)).map(|p| p.file_name.to_string()).unwrap_or_default();
        ui.label(RichText::new(crate::i18n::tr_format!("Sample {} of {} · {}", sample + 1, n_samples, name)).size(11.5).color(t.text_dim));
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            if n_samples > 1 {
                if crate::widgets::text_button(ui, "exportWmSampleNext", "▶", false).on_hover_text(crate::i18n::tr("Next sample photo")).clicked() {
                    sample = (sample + 1) % n_samples;
                }
                if crate::widgets::text_button(ui, "exportWmSamplePrev", "◀", false).on_hover_text(crate::i18n::tr("Previous sample photo")).clicked()
                {
                    sample = (sample + n_samples - 1) % n_samples;
                }
            }
        });
    });
    if n_samples > 1 {
        let (prev, next) = ui.input_mut(|i| {
            (i.consume_key(egui::Modifiers::COMMAND, egui::Key::OpenBracket), i.consume_key(egui::Modifiers::COMMAND, egui::Key::CloseBracket))
        });
        if next {
            sample = (sample + 1) % n_samples;
        }
        if prev {
            sample = (sample + n_samples - 1) % n_samples;
        }
    }
    ui.data_mut(|d| d.insert_temp(sample_id(), sample));
    ui.add_space(4.0);
    let card_h = (pane_h - preview_h - 70.0).max(150.0);
    egui::Frame::NONE
        .fill(t.inset)
        .stroke(Stroke::new(1.0, t.divider))
        .corner_radius(CornerRadius::same(10))
        .inner_margin(egui::Margin::symmetric(12, 10))
        .show(ui, |ui| {
            ui.set_width(LEFT_W - 26.0);
            ui.set_min_height(card_h - 20.0);
            saved_card(app, ui, &t, card_h - 20.0, opts);
        });
}

fn saved_card(app: &mut LightcraftApp, ui: &mut Ui, t: &Tokens, h: f32, opts: &mut ExportOptions) {
    let ctx = ui.ctx().clone();
    let list = saved_list(&ctx);
    let name_id = egui::Id::unique("lightcraft-export-wm-save-name");
    let naming_id = egui::Id::unique("lightcraft-export-wm-naming");
    let mut naming: bool = ctx.data(|d| d.get_temp(naming_id)).unwrap_or(false);
    let mut name: String = ctx.data(|d| d.get_temp(name_id)).unwrap_or_default();
    ui.horizontal(|ui| {
        ui.label(RichText::new(crate::i18n::tr("Saved watermarks")).font(t.semibold(13.0)).color(t.text));
        pro_ui::chip(ui, &list.len().to_string(), t.text_label);
        ui.with_layout(Layout::right_to_left(Align::Center), |ui| {
            if crate::widgets::text_button(ui, "exportWmSaveCurrent", crate::i18n::tr("Save current…"), naming).clicked() {
                naming = !naming;
            }
        });
    });
    if naming {
        ui.horizontal(|ui| {
            let r = ui.add(egui::TextEdit::singleline(&mut name).hint_text(crate::i18n::tr("Name")).desired_width(ui.available_width() - 70.0));
            crate::widgets::register(ui, "field:exportWmSaveName", r.rect);
            r.request_focus();
            let commit = r.lost_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter));
            if (crate::widgets::text_button(ui, "exportWmSaveOk", "Save", false).clicked() || commit)
                && let Some(wm) = opts.watermark.as_ref()
            {
                match watermark_store::dir()
                    .ok_or_else(|| "No settings folder to save into".to_string())
                    .and_then(|dir| watermark_store::save_in(&dir, &name, wm))
                {
                    Ok(_) => {
                        app.toast(&ctx, crate::i18n::tr_format!("Saved watermark “{}”", name.trim()));
                        name.clear();
                        naming = false;
                        refresh_saved(&ctx);
                    }
                    Err(e) => app.toast(&ctx, e),
                }
            }
        });
    }
    ctx.data_mut(|d| {
        d.insert_temp(naming_id, naming);
        d.insert_temp(name_id, name);
    });
    let list_h = (h - 96.0).max(60.0);
    egui::ScrollArea::vertical().id_salt("export-wm-saved").max_height(list_h).min_scrolled_height(list_h).auto_shrink([false, false]).show(
        ui,
        |ui| {
            ui.spacing_mut().item_spacing.y = 4.0;
            if list.is_empty() {
                ui.label(
                    RichText::new(crate::i18n::tr("No saved watermarks yet. Set one up on the right, then Save current…"))
                        .size(11.5)
                        .color(t.text_dim),
                );
            }
            let mut load: Option<Watermark> = None;
            let mut delete: Option<String> = None;
            let mut duplicate: Option<usize> = None;
            for (i, s) in list.iter().enumerate() {
                let on = opts.watermark.as_ref() == Some(&s.watermark);
                let (rect, resp) = ui.allocate_exact_size(vec2(ui.available_width(), 48.0), Sense::click());
                crate::widgets::register(ui, format!("button:exportWmSaved-{i}"), rect);
                let p = ui.painter();
                if on || resp.hovered() || resp.has_focus() {
                    p.rect(
                        rect,
                        CornerRadius::same(8),
                        if on { t.accent.gamma_multiply(0.16) } else { t.hover },
                        Stroke::new(if resp.has_focus() { 2.0 } else { 1.0 }, if on || resp.has_focus() { t.accent } else { t.divider }),
                        StrokeKind::Inside,
                    );
                }
                paint_thumb(p, Rect::from_min_size(rect.min + vec2(8.0, 7.0), vec2(64.0, 34.0)), &s.watermark, t);
                let tx = rect.left() + 82.0;
                p.text(Pos2::new(tx, rect.top() + 16.0), egui::Align2::LEFT_CENTER, &s.name, t.semibold(13.0), t.text);
                p.text(Pos2::new(tx, rect.top() + 33.0), egui::Align2::LEFT_CENTER, watermark_store::summary(&s.watermark), t.font(11.0), t.text_dim);
                let dots = Rect::from_center_size(Pos2::new(rect.right() - 18.0, rect.center().y), vec2(26.0, 26.0));
                let dr = ui.interact(dots, egui::Id::unique("lightcraft-export-wm-dots").with(i), Sense::click());
                crate::widgets::register(ui, format!("button:exportWmMenu-{i}"), dots);
                ui.painter().text(dots.center(), egui::Align2::CENTER_CENTER, "…", t.semibold(15.0), t.text_label);
                egui::Popup::menu(&dr).show(|ui| {
                    if ui.button(crate::i18n::tr("Duplicate")).clicked() {
                        duplicate = Some(i);
                    }
                    if ui.button(crate::i18n::tr("Delete")).clicked() {
                        delete = Some(s.name.clone());
                    }
                });
                if !dr.hovered() && (resp.clicked() || (resp.has_focus() && ui.input(|i| i.key_pressed(egui::Key::Enter)))) {
                    load = Some(s.watermark.clone());
                }
                if resp.has_focus() && ui.input(|i| i.key_pressed(egui::Key::Delete)) {
                    delete = Some(s.name.clone());
                }
            }
            let ctx = ui.ctx().clone();
            if let Some(wm) = load {
                opts.watermark = Some(wm);
            }
            if let Some(dir) = watermark_store::dir() {
                if let Some(i) = duplicate
                    && let Some(s) = list.get(i)
                {
                    let taken: Vec<String> = list.iter().map(|s| s.name.clone()).collect();
                    match watermark_store::save_in(&dir, &watermark_store::copy_name(&s.name, &taken), &s.watermark) {
                        Ok(_) => refresh_saved(&ctx),
                        Err(e) => app.toast(&ctx, e),
                    }
                }
                if let Some(n) = delete {
                    match watermark_store::delete_in(&dir, &n) {
                        Ok(()) => {
                            app.toast(&ctx, crate::i18n::tr_format!("Deleted watermark “{}”", n));
                            refresh_saved(&ctx);
                        }
                        Err(e) => app.toast(&ctx, e),
                    }
                }
            }
        },
    );
    ui.separator();
    // portable files: the Classic dialog's buttons; an import turns the watermark on
    let mut cur = opts.watermark.clone().unwrap_or_default();
    let had = opts.watermark.clone();
    d::watermark_file_buttons(app, ui, &mut cur);
    if had.as_ref() != Some(&cur) && (had.is_some() || cur != Watermark::default()) {
        opts.watermark = Some(cur);
        refresh_saved(&ctx);
    }
}

/// A 64x38 thumbnail of how the watermark sits on a photo.
fn paint_thumb(p: &egui::Painter, rect: Rect, wm: &Watermark, t: &Tokens) {
    p.rect_filled(rect, CornerRadius::same(4), Color32::from_rgb(70, 78, 96));
    p.rect_filled(
        Rect::from_min_max(rect.center_top() + vec2(-6.0, 0.0), rect.right_bottom()),
        CornerRadius::same(4),
        Color32::from_rgb(98, 104, 120),
    );
    let label: String = if wm.image.trim().is_empty() { wm.text.chars().take(5).collect() } else { "◎".into() };
    let size = vec2((label.chars().count() as f32 * 5.0 + 6.0).min(40.0), 12.0);
    let (r, c) = (anchor_index(wm.anchor) / 3, anchor_index(wm.anchor) % 3);
    let x = rect.left() + 3.0 + (rect.width() - size.x - 6.0) * c as f32 / 2.0;
    let y = rect.top() + 3.0 + (rect.height() - size.y - 6.0) * r as f32 / 2.0;
    let box_r = Rect::from_min_size(Pos2::new(x, y), size);
    if wm.background_opacity > 0.0 {
        p.rect_filled(box_r, CornerRadius::same(3), Color32::from_black_alpha((wm.background_opacity * 200.0) as u8));
    }
    if wm.border_width > 0.0 {
        p.rect_stroke(
            box_r,
            CornerRadius::same(3),
            Stroke::new(1.0, Color32::from_rgb(wm.border_color[0], wm.border_color[1], wm.border_color[2])),
            StrokeKind::Inside,
        );
    }
    p.text(box_r.center(), egui::Align2::CENTER_CENTER, label, t.font(8.5), Color32::from_rgb(wm.color[0], wm.color[1], wm.color[2]));
}

/// The 3x3 anchor picker: one tab stop, arrows move the cursor, Space/Enter or a click choose.
/// Cells register as `button:exportWmAnchor-{i}`.
pub fn anchor_grid(ui: &mut Ui, anchor: &mut Anchor) {
    let t = Tokens::get(ui.ctx());
    let (cw, ch, gap) = (36.0, 28.0, 4.0);
    let size = vec2(cw * 3.0 + gap * 2.0, ch * 3.0 + gap * 2.0);
    let (rect, resp) = ui.allocate_exact_size(size, Sense::click());
    let cursor_id = egui::Id::unique("lightcraft-export-wm-anchor-cursor");
    let mut cursor: usize = ui.data(|d| d.get_temp(cursor_id)).unwrap_or_else(|| anchor_index(*anchor));
    let cell = |i: usize| Rect::from_min_size(rect.min + vec2((i % 3) as f32 * (cw + gap), (i / 3) as f32 * (ch + gap)), vec2(cw, ch));
    if resp.clicked()
        && let Some(pos) = resp.interact_pointer_pos()
        && let Some(i) = (0..9).find(|i| cell(*i).contains(pos))
    {
        *anchor = ANCHORS[i];
        cursor = i;
    }
    if resp.has_focus() {
        for key in [egui::Key::ArrowLeft, egui::Key::ArrowRight, egui::Key::ArrowUp, egui::Key::ArrowDown, egui::Key::Home, egui::Key::End] {
            if ui.input_mut(|i| i.consume_key(egui::Modifiers::NONE, key)) {
                cursor = grid_step(cursor, key);
            }
        }
        if ui.input_mut(|i| i.consume_key(egui::Modifiers::NONE, egui::Key::Space) || i.consume_key(egui::Modifiers::NONE, egui::Key::Enter)) {
            *anchor = ANCHORS[cursor.min(8)];
        }
    }
    ui.data_mut(|d| d.insert_temp(cursor_id, cursor));
    let selected = anchor_index(*anchor);
    for i in 0..9 {
        let r = cell(i);
        crate::widgets::register(ui, format!("button:exportWmAnchor-{i}"), r);
        let on = i == selected;
        let hover = resp.hovered() && ui.input(|inp| inp.pointer.hover_pos()).is_some_and(|p| r.contains(p));
        let p = ui.painter();
        p.rect(
            r,
            CornerRadius::same(5),
            if on {
                t.accent
            } else if hover {
                t.hover
            } else {
                t.field
            },
            Stroke::new(
                if resp.has_focus() && i == cursor { 2.0 } else { 1.0 },
                if resp.has_focus() && i == cursor { t.accent } else { t.button_border },
            ),
            StrokeKind::Inside,
        );
        // arrow towards the corner or edge it names; a dot in the middle
        let c = r.center();
        let ink = if on { Color32::WHITE } else { t.text_label };
        let (dx, dy) = (((i % 3) as f32 - 1.0) * 4.0, ((i / 3) as f32 - 1.0) * 4.0);
        if i == 4 {
            p.circle_filled(c, 2.5, ink);
        } else {
            // a shaft towards the cell's side of the photo, and a two-stroke head
            let dir = vec2(dx, dy).normalized();
            let side = vec2(-dir.y, dir.x);
            let tip = c + dir * 5.5;
            p.line_segment([c - dir * 5.0, tip], Stroke::new(1.6, ink));
            p.line_segment([tip, tip - dir * 4.0 + side * 3.0], Stroke::new(1.6, ink));
            p.line_segment([tip, tip - dir * 4.0 - side * 3.0], Stroke::new(1.6, ink));
        }
    }
    resp.widget_info(|| egui::WidgetInfo::labeled(egui::Role::RadioGroup, true, crate::i18n::tr("Anchor")));
}

/// The Watermark section of the right pane: header with its switch, body when it is on.
pub fn watermark_section(app: &mut LightcraftApp, ui: &mut Ui, opts: &mut ExportOptions, full_size: bool, resize: &Resize) {
    let _ = (full_size, resize);
    let mut on = opts.watermark.is_some();
    let was = on;
    let summary = opts.watermark.as_ref().map_or("Off".to_string(), watermark_store::summary);
    let open_by_default = on;
    let id = "exportWatermark";
    // a watermark that was just switched on shows its rows
    if !pro_ui::is_open(ui.ctx(), id, open_by_default) && on && !was {
        ui.data_mut(|d| d.insert_temp(egui::Id::unique("lightcraft-pro-section").with(id), true));
    }
    pro_ui::section(ui, id, "Watermark", &summary, open_by_default, Some(&mut on), |ui| {
        if let Some(wm) = opts.watermark.as_mut() {
            watermark_body(app, ui, wm);
        }
    });
    if on != was {
        opts.watermark = on.then(|| Watermark { text: "© ".into(), ..Default::default() });
    }
    if let Some(msg) = invalid(opts) {
        ui.label(RichText::new(crate::i18n::tr(msg)).size(11.0).color(Color32::from_rgb(240, 85, 90)));
    }
}

/// The watermark rows in the spec's order: style, text or graphic, placement, appearance, frame and box.
fn watermark_body(app: &mut LightcraftApp, ui: &mut Ui, wm: &mut Watermark) {
    let t = Tokens::get(ui.ctx());
    let mut graphic = !wm.image.is_empty() || ui.data(|d| d.get_temp::<bool>(egui::Id::unique("wm-graphic"))).unwrap_or(false);
    let before = graphic;
    // Cmd/Ctrl+1 and +2 switch the style
    if ui.input_mut(|i| i.consume_key(egui::Modifiers::COMMAND, egui::Key::Num1)) {
        graphic = false;
    }
    if ui.input_mut(|i| i.consume_key(egui::Modifiers::COMMAND, egui::Key::Num2)) {
        graphic = true;
    }
    d::choices(ui, "Style", "exportWmStyle", &[(false, "Text"), (true, "Graphic")], &mut graphic);
    if graphic != before {
        ui.data_mut(|d| d.insert_temp(egui::Id::unique("wm-graphic"), graphic));
        if !graphic {
            wm.image.clear();
        }
    }
    if graphic {
        d::field(ui, "Graphic", |ui| {
            d::trailing_button_row(ui, |ui| {
                if app.services.pick_files.is_some()
                    && crate::widgets::text_button(ui, "exportWmChoose", crate::i18n::tr("Choose…"), false).clicked()
                    && let Some(f) = app.services.pick_files.as_mut().and_then(|pick| pick().into_iter().next())
                {
                    wm.image = f;
                }
                crate::widgets::named(
                    ui.add(egui::TextEdit::singleline(&mut wm.image).hint_text("logo.png").desired_width(ui.available_width())),
                    crate::i18n::tr("Image"),
                );
            });
        });
        let mut width = wm.image_width as f64 * 100.0;
        if d::num(ui, &d::WM_IMAGE_WIDTH, &mut width) {
            wm.image_width = (width / 100.0) as f32;
        }
    } else {
        d::field(ui, "Text", |ui| {
            crate::widgets::named(
                ui.add(
                    egui::TextEdit::multiline(&mut wm.text).desired_rows(2).hint_text(crate::i18n::tr("© Your Name")).desired_width(f32::INFINITY),
                ),
                crate::i18n::tr("Text"),
            )
        });
        d::field(ui, "", |ui| pro_ui::switch(ui, "exportWmVertical", &mut wm.vertical, "Vertical lettering"));
    }
    ui.add_space(2.0);
    pro_ui::caps(ui, "Placement");
    ui.horizontal_top(|ui| {
        ui.allocate_ui_with_layout(vec2(d::LABEL_W, 24.0), Layout::left_to_right(Align::Min), |ui| {
            ui.label(RichText::new(crate::i18n::tr("Anchor")).color(t.text_label));
        });
        anchor_grid(ui, &mut wm.anchor);
        ui.add_space(8.0);
        ui.vertical(|ui| {
            use lightcraft_engine::export::Anchor as P;
            let across = !matches!(wm.anchor, P::Top | P::Center | P::Bottom);
            if let Some(v) = crate::widgets::slider(ui, &d::WM_INSET_X, wm.inset_x as f64 * 100.0, across, None).value {
                wm.inset_x = (v / 100.0) as f32;
            }
            let down = !matches!(wm.anchor, P::Left | P::Center | P::Right);
            if let Some(v) = crate::widgets::slider(ui, &d::WM_INSET_Y, wm.inset_y as f64 * 100.0, down, None).value {
                wm.inset_y = (v / 100.0) as f32;
            }
        });
    });
    d::choices(ui, "Rotation", "exportWmRotation", &[(0u16, "0°"), (90, "90°"), (180, "180°"), (270, "270°")], &mut wm.rotation);
    ui.add_space(2.0);
    pro_ui::caps(ui, "Appearance");
    if !graphic {
        let mut size = wm.size as f64 * 100.0;
        if d::num(ui, &d::WM_SIZE, &mut size) {
            wm.size = (size / 100.0) as f32;
        }
    }
    let mut op = wm.opacity as f64 * 100.0;
    if d::num(ui, &d::WM_OPACITY, &mut op) {
        wm.opacity = (op / 100.0) as f32;
    }
    if !graphic {
        d::field(ui, "Colour", |ui| ui.color_edit_button_srgb(&mut wm.color));
        d::field(ui, "Shadow", |ui| pro_ui::switch(ui, "exportWmShadow", &mut wm.shadow, "Soft drop shadow"));
    }
    ui.add_space(2.0);
    ui.horizontal(|ui| {
        pro_ui::caps(ui, "Border & background box");
        pro_ui::chip(ui, "New", t.accent);
    });
    d::watermark_frame_controls(ui, wm);
}

#[cfg(test)]
mod tests {
    use super::*;
    use egui::Key;

    #[test]
    fn anchor_grid_cursor_moves_in_reading_order_and_clamps() {
        assert_eq!(grid_step(0, Key::ArrowLeft), 0);
        assert_eq!(grid_step(0, Key::ArrowRight), 1);
        assert_eq!(grid_step(2, Key::ArrowRight), 2);
        assert_eq!(grid_step(4, Key::ArrowUp), 1);
        assert_eq!(grid_step(4, Key::ArrowDown), 7);
        assert_eq!(grid_step(8, Key::ArrowDown), 8);
        assert_eq!(grid_step(5, Key::Home), 0);
        assert_eq!(grid_step(3, Key::End), 8);
        assert_eq!(grid_step(3, Key::Enter), 3);
        for (i, a) in ANCHORS.iter().enumerate() {
            assert_eq!(anchor_index(*a), i);
        }
    }

    #[test]
    fn empty_text_or_missing_file_blocks_export() {
        let mut o = ExportOptions::default();
        assert_eq!(invalid(&o), None);
        o.watermark = Some(Watermark { text: "  ".into(), ..Default::default() });
        assert_eq!(invalid(&o), Some("Add text or switch to Graphic"));
        o.watermark = Some(Watermark { text: "".into(), background_opacity: 0.4, ..Default::default() });
        assert_eq!(invalid(&o), None, "a box alone is a watermark");
        o.watermark = Some(Watermark { image: "/nonexistent/logo.png".into(), ..Default::default() });
        assert_eq!(invalid(&o), Some("File not found"));
        o.watermark = Some(Watermark { text: "© Me".into(), ..Default::default() });
        assert_eq!(invalid(&o), None);
    }
}
