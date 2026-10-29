//! Touch Export sheet layout (V4 Liquid Glass design).
//!
//! Provides a floating glass card sheet optimized for touch devices (iPad and iPhone),
//! with photo thumbnails, format/quality controls, size options, colour spaces,
//! metadata toggles, destination capsules, and a pinned primary Export button.

use egui::{Align2, Color32, CornerRadius, Pos2, Rect, Sense, Ui, pos2, vec2};
use lightcraft_engine::export::{ExportFormat, ExportOptions, MetadataPolicy, OutputSpace, Resize, ResizeMode};
use serde_json::Value;

use crate::LightcraftApp;
use crate::icons::{Icon, paint};
use crate::state::Dialog;
use crate::theme::{Tokens, phone, touch_ui};
use crate::widgets::{announce, announce_selected, register};

/// Accent blue for selected control labels and icons (#4aa3ff).
pub const ACCENT_BLUE: Color32 = Color32::from_rgb(0x4a, 0xa3, 0xff);

/// Exactly ONE filled blue button per screen (#0a84ff).
pub const PRIMARY_BLUE: Color32 = Color32::from_rgb(0x0a, 0x84, 0xff);

/// Selected control background: soft oval with white at ~20% alpha.
pub fn selected_bg() -> Color32 {
    Color32::from_rgba_unmultiplied(255, 255, 255, 51)
}

/// Unselected control background: subtle translucent fill (white ~6% alpha).
pub fn unselected_bg() -> Color32 {
    Color32::from_rgba_unmultiplied(255, 255, 255, 16)
}

/// Secondary text color: white at 62% alpha.
pub fn secondary_text() -> Color32 {
    Color32::from_rgba_unmultiplied(255, 255, 255, 158)
}

/// Primary text color: crisp light grey (#f2f2f2).
pub const PRIMARY_TEXT: Color32 = Color32::from_rgb(242, 242, 242);

/// Formats available in the touch Export sheet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TouchFormat {
    Jpeg,
    Heic,
    Tiff,
    Png,
}

impl TouchFormat {
    pub const ALL: [TouchFormat; 4] = [TouchFormat::Jpeg, TouchFormat::Heic, TouchFormat::Tiff, TouchFormat::Png];

    pub fn label(self) -> &'static str {
        match self {
            Self::Jpeg => "JPEG",
            Self::Heic => "HEIC",
            Self::Tiff => "TIFF",
            Self::Png => "PNG",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Jpeg => "jpeg",
            Self::Heic => "heic",
            Self::Tiff => "tiff",
            Self::Png => "png",
        }
    }

    /// Whether this format shows a compression quality value slider (only JPEG and HEIC).
    pub fn shows_quality(self) -> bool {
        matches!(self, Self::Jpeg | Self::Heic)
    }

    pub fn from_export_format(fmt: ExportFormat) -> Self {
        match fmt {
            ExportFormat::Png => Self::Png,
            ExportFormat::Tiff => Self::Tiff,
            _ => Self::Jpeg,
        }
    }

    pub fn to_export_format(self) -> ExportFormat {
        match self {
            Self::Jpeg => ExportFormat::Jpeg,
            // Fall back to JPEG for now until standalone HEIC writer lands
            Self::Heic => ExportFormat::Jpeg,
            Self::Tiff => ExportFormat::Tiff,
            Self::Png => ExportFormat::Png,
        }
    }
}

/// Sizing modes available in the touch Export sheet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TouchSizeMode {
    Original,
    LongEdge,
    Percent,
}

impl TouchSizeMode {
    pub const ALL: [TouchSizeMode; 3] = [TouchSizeMode::Original, TouchSizeMode::LongEdge, TouchSizeMode::Percent];

    pub fn label(self) -> &'static str {
        match self {
            Self::Original => "Original",
            Self::LongEdge => "Long edge",
            Self::Percent => "Percent",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Original => "original",
            Self::LongEdge => "longedge",
            Self::Percent => "percent",
        }
    }

    /// Whether this sizing mode needs a numeric value field (Long edge or Percent).
    pub fn needs_numeric_field(self) -> bool {
        matches!(self, Self::LongEdge | Self::Percent)
    }

    pub fn from_settings(full_size: bool, mode: ResizeMode) -> Self {
        if full_size {
            Self::Original
        } else {
            match mode {
                ResizeMode::Percent => Self::Percent,
                _ => Self::LongEdge,
            }
        }
    }
}

/// Save destinations in the touch Export sheet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SaveTarget {
    Photos,
    Files,
    Share,
    Copy,
}

impl SaveTarget {
    pub const ALL: [SaveTarget; 4] = [SaveTarget::Photos, SaveTarget::Files, SaveTarget::Share, SaveTarget::Copy];

    pub fn label(self) -> &'static str {
        match self {
            Self::Photos => "Photos",
            Self::Files => "Files",
            Self::Share => "Share",
            Self::Copy => "Copy",
        }
    }

    pub fn key(self) -> &'static str {
        match self {
            Self::Photos => "photos",
            Self::Files => "files",
            Self::Share => "share",
            Self::Copy => "copy",
        }
    }

    pub fn icon(self) -> Icon {
        match self {
            Self::Photos => Icon::Photos,
            Self::Files => Icon::Folder,
            Self::Share => Icon::Share,
            Self::Copy => Icon::Versions,
        }
    }

    pub fn description(self) -> &'static str {
        match self {
            Self::Photos => "Saves to Photos in the album LightCraft Exports",
            Self::Files => "Saves to Files in the destination folder",
            Self::Share => "Opens the system share sheet",
            Self::Copy => "Copies exported photo to the clipboard",
        }
    }
}

/// Metadata toggle states for touch controls.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct MetadataToggles {
    pub camera: bool,
    pub location: bool,
    pub copyright: bool,
    pub keywords: bool,
}

impl MetadataToggles {
    pub fn from_options(opts: &ExportOptions) -> Self {
        let camera = !matches!(opts.metadata, MetadataPolicy::AllExceptCamera | MetadataPolicy::Copyright | MetadataPolicy::None);
        let location = !opts.remove_location && !matches!(opts.metadata, MetadataPolicy::None | MetadataPolicy::Copyright);
        let copyright = !matches!(opts.metadata, MetadataPolicy::None);
        let keywords = !matches!(opts.metadata, MetadataPolicy::None | MetadataPolicy::Copyright);
        Self { camera, location, copyright, keywords }
    }

    pub fn apply_to_options(&self, opts: &mut ExportOptions) {
        opts.metadata = match (self.camera, self.copyright || self.keywords) {
            (true, _) => MetadataPolicy::All,
            (false, true) => MetadataPolicy::AllExceptCamera,
            (false, false) => MetadataPolicy::None,
        };
        opts.remove_location = !self.location;
    }
}

/// Number of additional photos represented by the "+N" overlay on the last visible tile.
///
/// When `total` photos exceed `max_tiles`, the first `max_tiles - 1` tiles show individual photos,
/// and the `max_tiles`-th tile displays a "+N" overlay where N is the remaining photos.
/// Returns `None` when `total <= max_tiles`.
pub fn plus_n_count(total: usize, max_tiles: usize) -> Option<usize> {
    if total > max_tiles && max_tiles > 0 { Some(total - (max_tiles - 1)) } else { None }
}

/// Number of thumbnail tiles to render in the multi-photo strip.
pub fn visible_tile_count(total: usize, max_tiles: usize) -> usize {
    total.min(max_tiles)
}

/// Calculate the floating glass sheet rectangle for a given screen rect and safe area insets.
pub fn sheet_card_rect(screen: Rect, safe_insets: [f32; 4], is_phone: bool) -> Rect {
    let safe_top = safe_insets[0];
    let safe_bottom = safe_insets[1].max(if is_phone { 20.0 } else { 0.0 });
    let safe_left = safe_insets[2];
    let safe_right = safe_insets[3];

    let inset = 8.0;
    if is_phone {
        // iPhone: floating glass sheet 8pt from screen edges
        let left = screen.left() + inset + safe_left;
        let right = screen.right() - inset - safe_right;
        let bottom = screen.bottom() - inset - safe_bottom;
        let available_h = (screen.height() - safe_top - safe_bottom - 2.0 * inset).max(100.0);
        let card_h = 700.0f32.min(available_h);
        let top = bottom - card_h;
        Rect::from_min_max(pos2(left, top), pos2(right, bottom))
    } else {
        // iPad: centered floating glass card, max width 540pt
        let max_w = 540.0f32.min(screen.width() - 32.0 - safe_left - safe_right).max(320.0);
        let max_h = 760.0f32.min(screen.height() - 48.0 - safe_top - safe_bottom).max(200.0);
        let cx = screen.center().x;
        let cy = screen.center().y;
        Rect::from_center_size(pos2(cx, cy), vec2(max_w, max_h))
    }
}

/// Convert current export options to JSON parameters for `app.export`.
fn export_params(opts: &ExportOptions, full_size: bool, resize: &Resize, limit_kb: u32, dir: &str) -> Value {
    let o = ExportOptions { resize: (!full_size).then_some(*resize), limit_kb: (limit_kb > 0).then_some(limit_kb), ..opts.clone() };
    let mut p = o.to_json();
    p["dir"] = serde_json::json!(dir);
    p["background"] = serde_json::json!(true);
    p
}

/// Touch Export sheet layout (V4 Liquid Glass design).
///
/// Only runs on touch devices with the glass theme active (`touch_ui` && `glass::active`).
/// The dialog router will call this on touch in a later step.
#[allow(dead_code)]
pub fn show(app: &mut LightcraftApp, ui: &mut Ui) {
    if !touch_ui(ui.ctx()) || !crate::glass::active(ui.ctx()) {
        return;
    }

    // Take dialog state during rendering so app can be borrowed for thumbnails and commands
    let mut dlg = app.ui.dialog.take();
    if !matches!(dlg, Some(Dialog::Export { .. })) {
        let prev = app.session.last_export.clone().unwrap_or_default();
        let opts = ExportOptions::from_json(&ExportOptions::known_keys_only(&prev));
        let full_size = opts.resize.is_none() && ExportOptions::has_size_param(&prev);
        let resize = opts.resize.unwrap_or_default();
        let dir = prev.get("dir").and_then(Value::as_str).map(str::to_string).unwrap_or_else(crate::control::default_export_dir);
        dlg = Some(Dialog::Export { opts, full_size, resize, preset_name: String::new(), limit_kb: 0, dir });
    }

    let Some(Dialog::Export { opts, full_size, resize, limit_kb, dir, .. }) = dlg.as_mut() else {
        app.ui.dialog = dlg;
        return;
    };

    let t = Tokens::get(ui.ctx());
    let screen = ui.ctx().content_rect();
    let insets = crate::theme::safe_area_insets(ui.ctx());
    let is_phone = phone(ui.ctx());
    let card_rect = sheet_card_rect(screen, insets, is_phone);

    let mut should_close = false;

    // Dimmed canvas backdrop (tapping outside dismisses the sheet)
    let painter = ui.painter();
    painter.rect_filled(screen, 0.0, Color32::from_black_alpha(90));
    let backdrop_resp = ui.interact(screen, egui::Id::unique("export-backdrop"), Sense::click());
    if backdrop_resp.clicked() && !card_rect.contains(backdrop_resp.interact_pointer_pos().unwrap_or(Pos2::ZERO)) {
        should_close = true;
    }

    // Floating glass sheet card (radius 30, shadow, translucent dark fill, no outlines)
    let shadow = crate::glass::shadow();
    painter.add(shadow.as_shape(card_rect, CornerRadius::same(30)));
    painter.rect_filled(card_rect, CornerRadius::same(30), Color32::from_rgba_unmultiplied(18, 18, 22, 235));

    // Layout margins: 16pt screen margins
    let inner_rect = card_rect.shrink2(vec2(16.0, 16.0));

    // Pinned bottom Export capsule button (44pt tall)
    let button_h = 44.0;
    let bottom_button_rect =
        Rect::from_min_max(pos2(inner_rect.left(), inner_rect.bottom() - button_h), pos2(inner_rect.right(), inner_rect.bottom()));

    // Scrollable body above the pinned button (16pt gap between groups)
    let body_rect = Rect::from_min_max(pos2(inner_rect.left(), inner_rect.top()), pos2(inner_rect.right(), bottom_button_rect.top() - 16.0));

    let n = app.session.selection.ids.len().max(1);
    let sel_ids = app.session.selection.ids.clone();

    // Fetch thumbnails before entering closure
    let thumbs: Vec<Option<(egui::TextureId, [usize; 2])>> = sel_ids
        .iter()
        .take(5)
        .map(|id| {
            super::grid::request_thumb(app, *id, 128, 8);
            app.renderer.thumb(*id).map(|tex| (tex.tex.id(), tex.size))
        })
        .collect();

    // --------------------------------------------------------------------------------------
    // Scrollable Sheet Content
    // --------------------------------------------------------------------------------------
    let mut body_ui = ui.new_child(egui::UiBuilder::new().max_rect(body_rect).layout(egui::Layout::top_down(egui::Align::Min)));

    egui::ScrollArea::vertical()
        .id_salt("export-touch-scroll")
        .scroll_bar_visibility(egui::scroll_area::ScrollBarVisibility::AlwaysHidden)
        .auto_shrink([false, false])
        .show(&mut body_ui, |ui| {
            ui.spacing_mut().item_spacing = vec2(8.0, 8.0);

            // 1. Title Row ("Export" with photo count and close button)
            let (title_rect, _) = ui.allocate_exact_size(vec2(ui.available_width(), 44.0), Sense::hover());
            let title_text = if n == 1 { "Export 1 photo".to_string() } else { format!("Export {n} photos") };
            ui.painter().text(pos2(title_rect.left(), title_rect.center().y - 8.0), Align2::LEFT_CENTER, &title_text, t.semibold(17.0), PRIMARY_TEXT);
            ui.painter().text(
                pos2(title_rect.left(), title_rect.center().y + 10.0),
                Align2::LEFT_CENTER,
                format!("{n} file{}", if n == 1 { "" } else { "s" }),
                t.font(12.0),
                secondary_text(),
            );

            // Round close button on the right (44pt hit area)
            let mut close_ui = ui.new_child(
                egui::UiBuilder::new()
                    .max_rect(Rect::from_min_max(pos2(title_rect.right() - 44.0, title_rect.top()), title_rect.right_bottom()))
                    .layout(egui::Layout::centered_and_justified(egui::Direction::LeftToRight)),
            );
            let close_btn = crate::glass::close_button(&mut close_ui);
            register(ui, "button:exportClose", close_btn.rect);
            if close_btn.clicked() {
                should_close = true;
            }

            // 2. Thumbnail Strip (when several photos are chosen: up to 5 tiles with "+N" overlay on 5th)
            if sel_ids.len() > 1 {
                ui.add_space(8.0);
                let tile_count = visible_tile_count(sel_ids.len(), 5);
                let gap = 8.0;
                let avail_w = ui.available_width();
                let tile_w = ((avail_w - gap * (tile_count as f32 - 1.0)) / tile_count as f32).max(44.0);
                let tile_h = tile_w.min(64.0);
                let (strip_rect, _) = ui.allocate_exact_size(vec2(avail_w, tile_h), Sense::hover());

                for i in 0..tile_count {
                    let tile_r = Rect::from_min_size(pos2(strip_rect.left() + i as f32 * (tile_w + gap), strip_rect.top()), vec2(tile_w, tile_h));
                    if let Some(Some((tex_id, size))) = thumbs.get(i) {
                        let [tw, th] = *size;
                        let s = (tile_r.width() / tw as f32).max(tile_r.height() / th as f32);
                        let fr = Rect::from_center_size(tile_r.center(), vec2(tw as f32 * s, th as f32 * s));
                        ui.painter().image(*tex_id, fr, Rect::from_min_max(pos2(0.0, 0.0), pos2(1.0, 1.0)), Color32::WHITE);
                    } else {
                        ui.painter().rect_filled(tile_r, CornerRadius::same(12), t.skeleton);
                    }

                    // "+N" overlay on the 5th tile if more photos remain
                    if i == 4
                        && let Some(rem) = plus_n_count(sel_ids.len(), 5)
                    {
                        ui.painter().rect_filled(tile_r, CornerRadius::same(12), Color32::from_black_alpha(150));
                        ui.painter().text(tile_r.center(), Align2::CENTER_CENTER, format!("+{rem}"), t.semibold(16.0), Color32::WHITE);
                    }
                }
            }

            ui.add_space(16.0);

            // 3. Format Section (JPEG, HEIC, TIFF, PNG)
            section_label(ui, &t, "Format");
            let format_id = egui::Id::unique("touch-export-format");
            let mut current_format =
                ui.data(|d| d.get_temp::<TouchFormat>(format_id)).unwrap_or_else(|| TouchFormat::from_export_format(opts.format));

            let format_items: Vec<(TouchFormat, &str, &str)> = TouchFormat::ALL.iter().map(|f| (*f, f.label(), f.key())).collect();

            if let Some(new_fmt) = touch_segmented(ui, &t, "exportFormat", &format_items, current_format) {
                current_format = new_fmt;
                opts.format = new_fmt.to_export_format();
                ui.data_mut(|d| d.insert_temp(format_id, current_format));
            }

            // 4. Quality Value Slider (only for JPEG/HEIC)
            if current_format.shows_quality() {
                ui.add_space(8.0);
                quality_slider_row(ui, &t, &mut opts.quality);
            }

            ui.add_space(16.0);

            // 5. Size Row (Original / Long edge / Percent)
            section_label(ui, &t, "Size");
            let mut current_size_mode = TouchSizeMode::from_settings(*full_size, resize.mode);
            let size_items: Vec<(TouchSizeMode, &str, &str)> = TouchSizeMode::ALL.iter().map(|s| (*s, s.label(), s.key())).collect();

            if let Some(new_mode) = touch_segmented(ui, &t, "exportSize", &size_items, current_size_mode) {
                current_size_mode = new_mode;
                match new_mode {
                    TouchSizeMode::Original => {
                        *full_size = true;
                    }
                    TouchSizeMode::LongEdge => {
                        *full_size = false;
                        resize.mode = ResizeMode::LongEdge;
                        if resize.value < 10.0 {
                            resize.value = 2048.0;
                        }
                    }
                    TouchSizeMode::Percent => {
                        *full_size = false;
                        resize.mode = ResizeMode::Percent;
                        if resize.value > 100.0 || resize.value < 1.0 {
                            resize.value = 100.0;
                        }
                    }
                }
            }

            // Numeric field row when needed
            if current_size_mode.needs_numeric_field() {
                ui.add_space(8.0);
                size_numeric_row(ui, &t, current_size_mode, resize);
            }

            ui.add_space(16.0);

            // 6. Colour Space Section (sRGB, Display P3, Adobe RGB)
            section_label(ui, &t, "Color space");
            let space_items = [
                (OutputSpace::Srgb, "sRGB", "srgb"),
                (OutputSpace::DisplayP3, "Display P3", "displayp3"),
                (OutputSpace::AdobeRgb, "Adobe RGB", "adobergb"),
            ];

            let active_space = match opts.color_space {
                OutputSpace::DisplayP3 => OutputSpace::DisplayP3,
                OutputSpace::AdobeRgb => OutputSpace::AdobeRgb,
                _ => OutputSpace::Srgb,
            };

            if let Some(new_space) = touch_segmented(ui, &t, "exportColorSpace", &space_items, active_space) {
                opts.color_space = new_space;
            }

            ui.add_space(16.0);

            // 7. Metadata Toggles (Camera, Location, Copyright, Keywords)
            section_label(ui, &t, "Metadata");
            let mut meta_state = MetadataToggles::from_options(opts);
            metadata_toggles_group(ui, &t, &mut meta_state);
            meta_state.apply_to_options(opts);

            ui.add_space(16.0);

            // 8. Save to Row (Photos, Files, Share, Copy)
            section_label(ui, &t, "Save to");
            let save_id = egui::Id::unique("touch-export-save-target");
            let mut save_target =
                ui.data(|d| d.get_temp::<SaveTarget>(save_id)).unwrap_or(if opts.add_to_photos { SaveTarget::Photos } else { SaveTarget::Files });

            save_to_group(ui, &t, &mut save_target);
            ui.data_mut(|d| d.insert_temp(save_id, save_target));
            opts.add_to_photos = save_target == SaveTarget::Photos;

            // Helper subtitle below Save to row
            let desc = save_target.description();
            ui.painter().text(
                pos2(ui.available_rect_before_wrap().left(), ui.cursor().top()),
                Align2::LEFT_TOP,
                desc,
                t.font(12.0),
                secondary_text(),
            );
            ui.add_space(16.0);
        });

    // --------------------------------------------------------------------------------------
    // Pinned Bottom Button: Exactly ONE filled blue (#0a84ff) 44pt capsule button
    // --------------------------------------------------------------------------------------
    let is_exporting = app.export.is_some();
    let (rect, resp) = ui.allocate_exact_size(vec2(bottom_button_rect.width(), button_h), Sense::click());

    if is_exporting {
        // Progress state replaces the button label with a progress bar while exporting
        let (done, _) = app.export.as_ref().and_then(|t| t.progress.lock().ok().map(|g| g.clone())).unwrap_or_default();
        let total = app.export.as_ref().map_or(1, |t| t.total.max(1));
        let fraction = (done as f32 / total as f32).clamp(0.0, 1.0);
        let pct = (fraction * 100.0) as u32;

        // Background track
        ui.painter().rect_filled(rect, CornerRadius::same(22), Color32::from_rgba_unmultiplied(10, 132, 255, 60));

        // Progress bar fill
        let fill_w = (rect.width() * fraction).max(if fraction > 0.0 { 22.0 } else { 0.0 });
        let prog_r = Rect::from_min_size(rect.min, vec2(fill_w, rect.height()));
        ui.painter().rect_filled(prog_r, CornerRadius::same(22), PRIMARY_BLUE);

        // Progress label
        let label = if done >= total { crate::i18n::tr("Finishing…").to_string() } else { format!("Exporting… {pct}% ({done}/{total})") };
        ui.painter().text(rect.center(), Align2::CENTER_CENTER, &label, t.semibold(15.0), Color32::WHITE);

        announce(&resp, &label);
        register(ui, "progress:exportProgress", rect);
        ui.ctx().request_repaint();
    } else {
        // Normal state: ONE filled blue 44pt capsule button
        let btn_label = if n == 1 { "Export 1 photo".to_string() } else { format!("Export {n} photos") };

        let fill = if resp.is_pointer_button_down_on() {
            PRIMARY_BLUE.gamma_multiply(0.8)
        } else if resp.hovered() {
            PRIMARY_BLUE.gamma_multiply(0.9)
        } else {
            PRIMARY_BLUE
        };

        ui.painter().rect_filled(rect, CornerRadius::same(22), fill);
        ui.painter().text(rect.center(), Align2::CENTER_CENTER, &btn_label, t.semibold(16.0), Color32::WHITE);

        announce(&resp, &btn_label);
        register(ui, "button:exportRun", rect);

        if resp.clicked() {
            let p = export_params(opts, *full_size, resize, *limit_kb, dir);
            match app.run("app.export", p) {
                Ok(_) => {
                    ui.ctx().request_repaint();
                }
                Err(e) => {
                    app.toast(ui.ctx(), e);
                }
            }
        }
    }

    if should_close {
        app.ui.dialog = None;
    } else {
        app.ui.dialog = dlg;
    }
}

// ------------------------------------------------------------------------------------------
// UI Helper Widgets
// ------------------------------------------------------------------------------------------

/// Section label header (13pt semibold, secondary text).
fn section_label(ui: &mut Ui, t: &Tokens, text: &str) {
    let (rect, _) = ui.allocate_exact_size(vec2(ui.available_width(), 20.0), Sense::hover());
    ui.painter().text(pos2(rect.left(), rect.center().y), Align2::LEFT_CENTER, crate::i18n::tr(text), t.semibold(13.0), secondary_text());
}

/// A 44pt tall touch segmented control with soft-oval selection and no outlines.
fn touch_segmented<T: Copy + PartialEq>(ui: &mut Ui, t: &Tokens, id: &str, items: &[(T, &str, &str)], selected: T) -> Option<T> {
    let row_h = 44.0;
    let avail_w = ui.available_width();
    let count = items.len().max(1);
    let gap = 4.0;
    let seg_w = ((avail_w - gap * (count as f32 - 1.0)) / count as f32).max(44.0);

    let (container_rect, _) = ui.allocate_exact_size(vec2(avail_w, row_h), Sense::hover());
    ui.painter().rect_filled(container_rect, CornerRadius::same(22), Color32::from_rgba_unmultiplied(255, 255, 255, 12));

    let mut chosen = None;

    for (i, (val, label, key)) in items.iter().enumerate() {
        let is_sel = *val == selected;
        let r = Rect::from_min_size(pos2(container_rect.left() + i as f32 * (seg_w + gap), container_rect.top()), vec2(seg_w, row_h));
        let resp = ui.interact(r, egui::Id::unique((id, *key)), Sense::click());
        announce_selected(&resp, *label, is_sel);
        register(ui, format!("button:{id}-{key}"), r);

        let bg = if is_sel {
            selected_bg()
        } else if resp.is_pointer_button_down_on() {
            Color32::from_rgba_unmultiplied(255, 255, 255, 30)
        } else {
            Color32::TRANSPARENT
        };

        ui.painter().rect_filled(r, CornerRadius::same(22), bg);

        let text_color = if is_sel { ACCENT_BLUE } else { PRIMARY_TEXT };
        ui.painter().text(r.center(), Align2::CENTER_CENTER, crate::i18n::tr(label), t.semibold(13.5), text_color);

        if resp.clicked() {
            chosen = Some(*val);
        }
    }

    chosen
}

/// Quality value slider row (44pt tall touch hit area).
fn quality_slider_row(ui: &mut Ui, t: &Tokens, quality: &mut u8) {
    let row_h = 44.0;
    let avail_w = ui.available_width();
    let (row_rect, _) = ui.allocate_exact_size(vec2(avail_w, row_h), Sense::hover());

    ui.painter().rect_filled(row_rect, CornerRadius::same(22), Color32::from_rgba_unmultiplied(255, 255, 255, 12));

    let label_w = 70.0;
    let value_w = 40.0;
    let pad = 16.0;

    // "Quality" label
    ui.painter().text(
        pos2(row_rect.left() + pad, row_rect.center().y),
        Align2::LEFT_CENTER,
        crate::i18n::tr("Quality"),
        t.semibold(14.0),
        PRIMARY_TEXT,
    );

    // Track area
    let track_left = row_rect.left() + pad + label_w;
    let track_right = row_rect.right() - pad - value_w;
    let track_w = (track_right - track_left).max(60.0);
    let track_rect = Rect::from_center_size(pos2(track_left + track_w / 2.0, row_rect.center().y), vec2(track_w, 4.0));

    // Track background
    ui.painter().rect_filled(track_rect, CornerRadius::same(2), Color32::from_rgba_unmultiplied(255, 255, 255, 56));

    let q_norm = (*quality as f32 / 100.0).clamp(0.0, 1.0);
    let fill_rect = Rect::from_min_max(track_rect.left_top(), pos2(track_rect.left() + track_w * q_norm, track_rect.bottom()));
    ui.painter().rect_filled(fill_rect, CornerRadius::same(2), PRIMARY_BLUE);

    // Thumb (28pt diameter circle)
    let thumb_center = pos2(track_rect.left() + track_w * q_norm, row_rect.center().y);
    ui.painter().circle_filled(thumb_center, 14.0, Color32::WHITE);

    // Touch interaction over track area
    let touch_track_rect = Rect::from_center_size(track_rect.center(), vec2(track_w + 28.0, row_h));
    let resp = ui.interact(touch_track_rect, egui::Id::unique("touch-quality-slider"), Sense::click_and_drag());
    announce(&resp, format!("Quality: {quality}"));
    register(ui, "slider:exportQuality", touch_track_rect);

    if (resp.dragged() || resp.clicked())
        && let Some(pos) = resp.interact_pointer_pos()
    {
        let frac = ((pos.x - track_rect.left()) / track_w).clamp(0.01, 1.0);
        *quality = (frac * 100.0).round() as u8;
    }

    // Value display
    ui.painter().text(pos2(row_rect.right() - pad, row_rect.center().y), Align2::RIGHT_CENTER, quality.to_string(), t.semibold(14.0), PRIMARY_TEXT);
}

/// Sizing numeric values row (44pt tall touch control).
fn size_numeric_row(ui: &mut Ui, t: &Tokens, mode: TouchSizeMode, resize: &mut Resize) {
    let row_h = 44.0;
    let avail_w = ui.available_width();
    let (rect, _) = ui.allocate_exact_size(vec2(avail_w, row_h), Sense::hover());

    ui.painter().rect_filled(rect, CornerRadius::same(22), Color32::from_rgba_unmultiplied(255, 255, 255, 12));

    let pad = 16.0;
    let label = match mode {
        TouchSizeMode::LongEdge => crate::i18n::tr("Dimension"),
        TouchSizeMode::Percent => crate::i18n::tr("Scale"),
        TouchSizeMode::Original => "",
    };

    ui.painter().text(pos2(rect.left() + pad, rect.center().y), Align2::LEFT_CENTER, label, t.semibold(13.5), secondary_text());

    // Quick preset values as touch pills
    let values: &[f32] = match mode {
        TouchSizeMode::LongEdge => &[1024.0, 2048.0, 4096.0],
        TouchSizeMode::Percent => &[25.0, 50.0, 75.0, 100.0],
        TouchSizeMode::Original => &[],
    };

    let suffix = match mode {
        TouchSizeMode::LongEdge => "px",
        TouchSizeMode::Percent => "%",
        TouchSizeMode::Original => "",
    };

    let pill_w = 64.0;
    let pill_gap = 6.0;
    let total_pills_w = values.len() as f32 * pill_w + (values.len().saturating_sub(1)) as f32 * pill_gap;
    let pills_left = rect.right() - pad - total_pills_w;

    for (i, &v) in values.iter().enumerate() {
        let pill_r = Rect::from_min_size(pos2(pills_left + i as f32 * (pill_w + pill_gap), rect.top() + 6.0), vec2(pill_w, 32.0));
        let active = (resize.value - v).abs() < 0.5;
        let pill_resp = ui.interact(pill_r, egui::Id::unique(("size-val", i)), Sense::click());
        announce_selected(&pill_resp, format!("{v} {suffix}"), active);
        register(ui, format!("button:exportSizeVal-{v}"), pill_r);

        let bg = if active { selected_bg() } else { Color32::TRANSPARENT };
        ui.painter().rect_filled(pill_r, CornerRadius::same(16), bg);
        let tc = if active { ACCENT_BLUE } else { PRIMARY_TEXT };
        ui.painter().text(pill_r.center(), Align2::CENTER_CENTER, format!("{v:.0} {suffix}"), t.semibold(12.5), tc);

        if pill_resp.clicked() {
            resize.value = v;
        }
    }
}

/// Metadata toggles laid out as two horizontal rows of two capsules each (height 48pt).
fn metadata_toggles_group(ui: &mut Ui, t: &Tokens, state: &mut MetadataToggles) {
    let avail_w = ui.available_width();
    let gap = 8.0;
    let col_w = ((avail_w - gap) / 2.0).max(100.0);
    let row_h = 48.0;

    let items = [
        ("Camera", if state.camera { "EXIF kept" } else { "Stripped" }, Icon::Photos, state.camera, "metaCamera"),
        ("Location", if state.location { "GPS kept" } else { "Removed" }, Icon::Info, state.location, "metaLocation"),
        ("Copyright", if state.copyright { "Included" } else { "None" }, Icon::Check, state.copyright, "metaCopyright"),
        ("Keywords", if state.keywords { "Tags kept" } else { "None" }, Icon::Tag, state.keywords, "metaKeywords"),
    ];

    for row_idx in 0..2 {
        let (row_rect, _) = ui.allocate_exact_size(vec2(avail_w, row_h), Sense::hover());
        for col_idx in 0..2 {
            let item_idx = row_idx * 2 + col_idx;
            if let Some(&(title, sub, icon, on, key)) = items.get(item_idx) {
                let r = Rect::from_min_size(pos2(row_rect.left() + col_idx as f32 * (col_w + gap), row_rect.top()), vec2(col_w, row_h));
                let resp = ui.interact(r, egui::Id::unique(key), Sense::click());
                announce_selected(&resp, title, on);
                register(ui, format!("button:{key}"), r);

                let bg = if on { selected_bg() } else { unselected_bg() };
                ui.painter().rect_filled(r, CornerRadius::same(24), bg);

                let icon_color = if on { ACCENT_BLUE } else { secondary_text() };
                let icon_rect = Rect::from_center_size(pos2(r.left() + 24.0, r.center().y), vec2(20.0, 20.0));
                paint(ui.painter(), icon_rect, icon, icon_color);

                let text_color = if on { ACCENT_BLUE } else { PRIMARY_TEXT };
                ui.painter().text(
                    pos2(r.left() + 42.0, r.center().y - 7.0),
                    Align2::LEFT_CENTER,
                    crate::i18n::tr(title),
                    t.semibold(13.0),
                    text_color,
                );
                let sub_color = if on { ACCENT_BLUE } else { secondary_text() };
                ui.painter().text(pos2(r.left() + 42.0, r.center().y + 8.0), Align2::LEFT_CENTER, crate::i18n::tr(sub), t.font(12.0), sub_color);

                if resp.clicked() {
                    match item_idx {
                        0 => state.camera = !state.camera,
                        1 => state.location = !state.location,
                        2 => state.copyright = !state.copyright,
                        3 => state.keywords = !state.keywords,
                        _ => {}
                    }
                }
            }
        }
        if row_idx == 0 {
            ui.add_space(gap);
        }
    }
}

/// Save to row: 4 icon capsules (Photos, Files, Share, Copy). Height 48pt.
fn save_to_group(ui: &mut Ui, t: &Tokens, target: &mut SaveTarget) {
    let avail_w = ui.available_width();
    let gap = 4.0;
    let count = SaveTarget::ALL.len();
    let cap_w = ((avail_w - gap * (count as f32 - 1.0)) / count as f32).max(44.0);
    let cap_h = 48.0;

    let (container_rect, _) = ui.allocate_exact_size(vec2(avail_w, cap_h), Sense::hover());
    ui.painter().rect_filled(container_rect, CornerRadius::same(24), Color32::from_rgba_unmultiplied(255, 255, 255, 12));

    for (i, &st) in SaveTarget::ALL.iter().enumerate() {
        let is_sel = st == *target;
        let r = Rect::from_min_size(pos2(container_rect.left() + i as f32 * (cap_w + gap), container_rect.top()), vec2(cap_w, cap_h));
        let resp = ui.interact(r, egui::Id::unique(("save-to", st.key())), Sense::click());
        announce_selected(&resp, st.label(), is_sel);
        register(ui, format!("button:exportSaveTo-{}", st.key()), r);

        let bg = if is_sel {
            selected_bg()
        } else if resp.is_pointer_button_down_on() {
            Color32::from_rgba_unmultiplied(255, 255, 255, 30)
        } else {
            Color32::TRANSPARENT
        };

        ui.painter().rect_filled(r, CornerRadius::same(24), bg);

        let color = if is_sel { ACCENT_BLUE } else { secondary_text() };
        let icon_rect = Rect::from_center_size(pos2(r.center().x, r.top() + 16.0), vec2(18.0, 18.0));
        paint(ui.painter(), icon_rect, st.icon(), color);

        ui.painter().text(pos2(r.center().x, r.bottom() - 11.0), Align2::CENTER_CENTER, crate::i18n::tr(st.label()), t.semibold(12.0), color);

        if resp.clicked() {
            *target = st;
        }
    }
}

// ------------------------------------------------------------------------------------------
// Unit Tests (pure logic)
// ------------------------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_plus_n_count() {
        // <= max_tiles gives no overlay
        assert_eq!(plus_n_count(0, 5), None);
        assert_eq!(plus_n_count(1, 5), None);
        assert_eq!(plus_n_count(3, 5), None);
        assert_eq!(plus_n_count(5, 5), None);

        // > max_tiles overlays the remaining photos count on the 5th tile
        assert_eq!(plus_n_count(6, 5), Some(2));
        assert_eq!(plus_n_count(12, 5), Some(8));
        assert_eq!(plus_n_count(100, 5), Some(96));

        // Different tile limit
        assert_eq!(plus_n_count(10, 3), Some(8));
        assert_eq!(plus_n_count(5, 0), None);
    }

    #[test]
    fn test_visible_tile_count() {
        assert_eq!(visible_tile_count(0, 5), 0);
        assert_eq!(visible_tile_count(1, 5), 1);
        assert_eq!(visible_tile_count(4, 5), 4);
        assert_eq!(visible_tile_count(5, 5), 5);
        assert_eq!(visible_tile_count(12, 5), 5);
    }

    #[test]
    fn test_format_shows_quality() {
        // Only JPEG and HEIC have quality sliders
        assert!(TouchFormat::Jpeg.shows_quality());
        assert!(TouchFormat::Heic.shows_quality());
        assert!(!TouchFormat::Tiff.shows_quality());
        assert!(!TouchFormat::Png.shows_quality());
    }

    #[test]
    fn test_format_conversion() {
        assert_eq!(TouchFormat::Jpeg.to_export_format(), ExportFormat::Jpeg);
        assert_eq!(TouchFormat::Tiff.to_export_format(), ExportFormat::Tiff);
        assert_eq!(TouchFormat::Png.to_export_format(), ExportFormat::Png);

        assert_eq!(TouchFormat::from_export_format(ExportFormat::Jpeg), TouchFormat::Jpeg);
        assert_eq!(TouchFormat::from_export_format(ExportFormat::Tiff), TouchFormat::Tiff);
        assert_eq!(TouchFormat::from_export_format(ExportFormat::Png), TouchFormat::Png);
    }

    #[test]
    fn test_size_mode_needs_numeric_field() {
        assert!(!TouchSizeMode::Original.needs_numeric_field());
        assert!(TouchSizeMode::LongEdge.needs_numeric_field());
        assert!(TouchSizeMode::Percent.needs_numeric_field());
    }

    #[test]
    fn test_size_mode_from_settings() {
        assert_eq!(TouchSizeMode::from_settings(true, ResizeMode::LongEdge), TouchSizeMode::Original);
        assert_eq!(TouchSizeMode::from_settings(false, ResizeMode::LongEdge), TouchSizeMode::LongEdge);
        assert_eq!(TouchSizeMode::from_settings(false, ResizeMode::Percent), TouchSizeMode::Percent);
        assert_eq!(TouchSizeMode::from_settings(false, ResizeMode::Width), TouchSizeMode::LongEdge);
    }

    #[test]
    fn test_metadata_toggles_logic() {
        let mut opts = ExportOptions::default();
        let toggles = MetadataToggles { camera: true, location: true, copyright: true, keywords: true };
        toggles.apply_to_options(&mut opts);
        assert_eq!(opts.metadata, MetadataPolicy::All);
        assert!(!opts.remove_location);

        let toggles_no_cam = MetadataToggles { camera: false, location: false, copyright: true, keywords: true };
        toggles_no_cam.apply_to_options(&mut opts);
        assert_eq!(opts.metadata, MetadataPolicy::AllExceptCamera);
        assert!(opts.remove_location);

        let roundtrip = MetadataToggles::from_options(&opts);
        assert!(!roundtrip.camera);
        assert!(!roundtrip.location);
    }

    #[test]
    fn test_layout_math_iphone_12_mini() {
        // iPhone 12 mini: 375 x 812 pt
        let screen = Rect::from_min_size(Pos2::ZERO, vec2(375.0, 812.0));
        let insets = [44.0, 34.0, 0.0, 0.0];
        let card = sheet_card_rect(screen, insets, true);

        // 8pt inset from edges
        assert_eq!(card.left(), 8.0);
        assert_eq!(card.right(), 367.0);
        assert_eq!(card.width(), 359.0);
        // Bottom above home bar safe area (34 + 8 = 42 from bottom of screen)
        assert_eq!(card.bottom(), 812.0 - 42.0);
        // Top below status bar
        assert!(card.top() >= 44.0);
        // Card fits within screen
        assert!(screen.contains_rect(card));
    }

    #[test]
    fn test_layout_math_ipad_mini_6() {
        // iPad mini 6 portrait: 744 x 1133 pt
        let screen = Rect::from_min_size(Pos2::ZERO, vec2(744.0, 1133.0));
        let insets = [24.0, 20.0, 0.0, 0.0];
        let card = sheet_card_rect(screen, insets, false);

        assert!(card.width() <= 540.0);
        assert_eq!(card.center().x, 372.0);
        assert!(screen.contains_rect(card));

        // iPad mini 6 landscape: 1133 x 744 pt
        let screen_land = Rect::from_min_size(Pos2::ZERO, vec2(1133.0, 744.0));
        let card_land = sheet_card_rect(screen_land, insets, false);

        assert!(card_land.width() <= 540.0);
        assert_eq!(card_land.center().x, 566.5);
        assert!(screen_land.contains_rect(card_land));
    }
}
