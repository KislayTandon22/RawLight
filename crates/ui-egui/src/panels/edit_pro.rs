//! The Pro desktop layout's Develop dock (right): a pinned histogram with clipping toggles, six collapsible groups
//! of dense slider rows (Basic, Tone, Color, Detail, Optics, Effects) and a bottom action bar. The classic Edit
//! panel in `edit.rs` and the touch one in `edit_touch.rs` are untouched; this runs only when
//! `theme::desktop_pro` is on.
//!
//! The groups are built from the engine's control specs by [`group_specs`], so a control added to a section shows
//! up here without touching this file.

use std::sync::Arc;

use egui::{Align, Align2, Color32, CornerRadius, Pos2, Rect, Sense, Stroke, Ui, pos2, vec2};
use lightcraft_catalog::PhotoId;
use lightcraft_develop::{ControlSpec, DevelopSettings, Section, WbMode, controls};
use serde_json::json;

use super::edit::{control, k_to_rel, rel_to_k};
use super::ui_pro::{self, Pal};
use crate::LightcraftApp;
use crate::icons::Icon;
use crate::theme::Tokens;
use crate::widgets::{register, slider};

/// A group: id, title and the engine section whose eye (`develop.sectionEnabled`) it switches, if any.
pub const GROUPS: [(&str, &str, Option<&str>); 6] = [
    ("basic", "Basic", None),
    ("tone", "Tone", Some("light")),
    ("color", "Color", Some("color")),
    ("detail", "Detail", Some("detail")),
    ("optics", "Optics", Some("optics")),
    ("effects", "Effects", Some("effects")),
];

/// The id under which a group's open state is kept in `app.ui.open_sections`.
pub fn open_key(group: &str) -> String {
    format!("pro.{group}")
}

const BASIC_IDS: [&str; 5] = ["wb.temp", "wb.tint", "light.exposure", "color.vibrance", "color.saturation"];

/// The sections a group owns outright (reset as a whole).
fn group_sections(group: &str) -> &'static [Section] {
    match group {
        "tone" => &[Section::Curve],
        "color" => &[Section::Mixer, Section::BwMix, Section::Grading, Section::PointColor, Section::Calibration],
        "detail" => &[Section::Detail],
        "optics" => &[Section::Optics, Section::Geometry],
        "effects" => &[Section::Effects, Section::Vignette, Section::Grain],
        _ => &[],
    }
}

/// Every control of a group, from the engine's specs (the group-to-section map of the spec).
pub fn group_specs(group: &str) -> Vec<&'static ControlSpec> {
    let mut out: Vec<&'static ControlSpec> = Vec::new();
    match group {
        "basic" => {
            out.extend(BASIC_IDS.iter().filter_map(|id| controls::find(id)));
            out.extend(controls::find("profile.amount"));
        }
        "tone" => out.extend(controls::in_section(Section::Light).filter(|s| s.id != "light.exposure" && !s.id.starts_with("hdr."))),
        _ => {
            for s in group_sections(group) {
                out.extend(controls::in_section(*s));
            }
        }
    }
    out
}

/// Whether any control of the group is off its default.
pub fn group_edited(d: &DevelopSettings, group: &str) -> bool {
    group_specs(group).iter().any(|s| controls::get(d, s.id).is_some_and(|v| (v - s.default).abs() > 1e-9))
}

/// Put every control of a group back to its default as one undo step.
fn reset_group(app: &mut LightcraftApp, group: &str) {
    let _ = app.run("develop.beginInteraction", json!({"label": format!("Reset {}", group_title(group))}));
    for s in group_sections(group) {
        if let Ok(section) = serde_json::to_value(s) {
            let _ = app.run("develop.resetSection", json!({"section": section}));
        }
    }
    if matches!(group, "basic" | "tone") {
        for s in group_specs(group) {
            let _ = app.run("develop.resetControl", json!({"control": s.id}));
        }
    }
    let _ = app.run("develop.endInteraction", json!({}));
}

fn group_title(group: &str) -> &'static str {
    GROUPS.iter().find(|g| g.0 == group).map_or("", |g| g.1)
}

/// Make sure the first run shows Basic and Tone open.
fn init_open(app: &mut LightcraftApp) {
    if !app.ui.section_open("pro.init") {
        app.ui.open_sections.push("pro.init".into());
        for g in ["basic", "tone"] {
            let k = open_key(g);
            if !app.ui.section_open(&k) {
                app.ui.open_sections.push(k);
            }
        }
    }
}

/// The photo's settings as the panel shows them (Kelvin for raw files, a relative scale for rendered ones).
fn display_settings(app: &LightcraftApp, id: PhotoId) -> (Arc<DevelopSettings>, bool) {
    let mut d = app.session.develop_of(id).unwrap_or_default();
    let raw = app.session.catalog.photo(id).is_some_and(|p| p.develops_raw() && !p.relative_wb());
    if d.wb.mode == WbMode::AsShot && app.session.catalog.photo(id).is_some_and(|p| p.relative_wb()) {
        let wb = &mut Arc::make_mut(&mut d).wb;
        wb.temp = 6500.0;
        wb.tint = 0.0;
    } else if raw {
        let info = app.session.source_info(id);
        let (temp, tint) = lightcraft_engine::pipeline::local::effective_wb(&info, &d);
        let wb = &mut Arc::make_mut(&mut d).wb;
        wb.temp = temp;
        wb.tint = tint;
    }
    (d, raw)
}

/// The whole right dock in Pro: pinned histogram, scrolling groups, pinned action bar.
pub fn dock(app: &mut LightcraftApp, ui: &mut Ui, id: PhotoId) {
    init_open(app);
    let pal = Pal::get(ui.ctx());
    ui_pro::dock_style(ui);
    ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
    if app.ui.histogram {
        histogram_pro(app, ui, id);
        ui_pro::hairline(ui);
    }
    if app.ui.soft_proof {
        // (soft proofing keeps its classic strip)
        super::edit::soft_proofing(app, ui, id);
    }
    let bar_h = 40.0;
    let body_h = (ui.available_height() - bar_h).max(80.0);
    egui::ScrollArea::vertical().id_salt("pro-develop-scroll").max_height(body_h).auto_shrink([false, false]).show(ui, |ui| {
        ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
        scroll_body(app, ui, id);
    });
    ui_pro::hairline(ui);
    let (bar, _) = ui.allocate_exact_size(vec2(ui.available_width(), bar_h), Sense::hover());
    ui.painter().rect_filled(bar, 0.0, pal.glass);
    let mut child = ui.new_child(egui::UiBuilder::new().max_rect(bar.shrink2(vec2(10.0, 8.0))).layout(egui::Layout::left_to_right(Align::Center)));
    child.spacing_mut().item_spacing.x = 6.0;
    if ui_pro::button(&mut child, "proCopy", crate::i18n::tr("Copy"), false).clicked() {
        let _ = app.run("develop.copy", json!({}));
    }
    if ui_pro::button(&mut child, "proPaste", crate::i18n::tr("Paste"), false).clicked() {
        let _ = app.run("develop.paste", json!({}));
    }
    child.with_layout(egui::Layout::right_to_left(Align::Center), |ui| {
        let tip = super::edit::reset_tip(&app.ui.settings.keymap, ui.ctx().os() == egui::os::OperatingSystem::Mac);
        if ui_pro::button(ui, "reset", crate::i18n::tr("Reset all"), false).on_hover_text(tip).clicked() {
            let _ = app.run("develop.reset", json!({}));
        }
    });
}

/// The groups themselves (inside a scroll area).
pub fn scroll_body(app: &mut LightcraftApp, ui: &mut Ui, id: PhotoId) {
    init_open(app);
    ui.spacing_mut().item_spacing = vec2(0.0, 0.0);
    let (d, raw) = display_settings(app, id);
    let preview_only = app.session.catalog.photo(id).and_then(|p| p.preview_only.clone());
    if let Some(why) = &preview_only {
        let reload =
            egui::Frame::NONE.inner_margin(egui::Margin::symmetric(12, 6)).show(ui, |ui| crate::widgets::preview_only_notice(ui, "edit", why)).inner;
        if reload {
            super::edit::reload_preview_only(app, ui.ctx(), id);
        }
    }
    let n = app.session.selection.ids.len();
    if app.session.auto_sync && n > 1 {
        let pal = Pal::get(ui.ctx());
        egui::Frame::NONE.inner_margin(egui::Margin::symmetric(12, 4)).show(ui, |ui| {
            ui.horizontal(|ui| {
                ui.label(egui::RichText::new(crate::i18n::tr_format!("Auto Sync: edits apply to {n} photos", n = n)).color(pal.accent_hi).size(11.0));
            });
        });
    }
    for (gid, title, eye) in GROUPS {
        group(app, ui, &d, gid, title, eye, |app, ui| match gid {
            "basic" => basic(app, ui, &d, id, raw),
            "tone" => tone(app, ui, &d, id),
            "color" => color(app, ui, &d, id),
            "detail" => detail(app, ui, &d, id),
            "optics" => optics(app, ui, &d, id),
            _ => effects(app, ui, &d),
        });
    }
    ui.add_space(24.0);
}

// ----------------------------------------------------------------------------------------- group chrome

fn group(
    app: &mut LightcraftApp,
    ui: &mut Ui,
    d: &DevelopSettings,
    gid: &str,
    title: &str,
    eye: Option<&str>,
    body: impl FnOnce(&mut LightcraftApp, &mut Ui),
) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let key = open_key(gid);
    let open = app.ui.section_open(&key);
    let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), ui_pro::GROUP_H), Sense::click());
    let title_t = crate::i18n::tr(title);
    crate::widgets::announce_disclosure(&resp, true, open, title_t);
    register(ui, format!("section:{gid}"), r);
    if resp.hovered() {
        ui.painter().rect_filled(r, 0.0, Color32::from_white_alpha(8));
    }
    crate::icons::paint(
        ui.painter(),
        Rect::from_center_size(pos2(r.left() + 16.0, r.center().y), vec2(14.0, 14.0)),
        if open { Icon::ChevronDown } else { Icon::ChevronRight },
        pal.text2,
    );
    let edited = group_edited(d, gid);
    let galley = ui.painter().layout_no_wrap(title_t.to_string(), t.semibold(12.0), pal.text);
    let title_pos = pos2(r.left() + 28.0, r.center().y - galley.size().y / 2.0);
    let title_w = galley.size().x;
    ui.painter().galley(title_pos, galley, pal.text);
    if edited {
        ui.painter().circle_filled(pos2(title_pos.x + title_w + 8.0, r.center().y), 2.5, pal.accent);
    }
    // right side: reset (on hover) and the eye
    let enabled = eye.is_none_or(|e| d.section_enabled(e));
    let mut toggled = None;
    let mut reset = false;
    let hover = ui.rect_contains_pointer(r);
    let mut x = r.right() - 10.0;
    if let Some(e) = eye
        && (hover || !enabled)
    {
        let er = Rect::from_center_size(pos2(x - 9.0, r.center().y), vec2(18.0, 18.0));
        let resp_e = ui.interact(er, ui.scope_id().with(("pro-eye", gid)), Sense::click());
        crate::widgets::announce_selected(&resp_e, crate::i18n::tr("Show / hide"), enabled);
        register(ui, format!("sectionEye:{gid}"), er);
        let c = if enabled { pal.text2 } else { pal.text4 };
        crate::icons::paint(ui.painter(), er.shrink(1.0), Icon::Eye, c);
        if !enabled {
            ui.painter().line_segment([er.left_bottom(), er.right_top()], Stroke::new(1.5, c));
        }
        if resp_e.clicked() {
            toggled = Some((e, !enabled));
        }
        x -= 22.0;
    }
    if hover && edited {
        let rr = Rect::from_center_size(pos2(x - 9.0, r.center().y), vec2(18.0, 18.0));
        let resp_r = ui.interact(rr, ui.scope_id().with(("pro-reset", gid)), Sense::click());
        crate::widgets::announce(&resp_r, crate::i18n::tr_format!("Reset {name}", name = crate::i18n::tr(title)));
        register(ui, format!("sectionReset:{gid}"), rr);
        crate::icons::paint(ui.painter(), rr.shrink(2.0), Icon::Undo, if resp_r.hovered() { pal.text } else { pal.text2 });
        if resp_r.clicked() {
            reset = true;
        }
    }
    if let Some((section, on)) = toggled {
        let _ = app.run("develop.sectionEnabled", json!({"section": section, "enabled": on}));
    } else if reset || resp.double_clicked() {
        reset_group(app, gid);
    } else if resp.clicked() {
        if ui.input(|i| i.modifiers.alt) {
            app.ui.solo_section(&key);
        } else {
            app.ui.toggle_section(&key);
        }
    }
    if open {
        body(app, ui);
        ui.add_space(6.0);
    }
    ui_pro::hairline(ui);
}

/// A disclosure row inside a group (Tone Curve, Mixer…): 24pt, chevron and title; returns whether it is open.
fn disclosure(app: &mut LightcraftApp, ui: &mut Ui, id: &str, title: &str) -> bool {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let open = app.ui.flyout_open(id);
    let (r, resp) = ui.allocate_exact_size(vec2(ui.available_width(), 26.0), Sense::click());
    let title = crate::i18n::tr(title);
    crate::widgets::announce_disclosure(&resp, true, open, title);
    register(ui, format!("flyout:{id}"), r);
    let inner = r.shrink2(vec2(10.0, 2.0));
    ui.painter().rect_filled(inner, CornerRadius::same(ui_pro::CONTROL_R), if resp.hovered() { pal.field_h } else { pal.field });
    ui.painter().text(pos2(inner.left() + 10.0, inner.center().y), Align2::LEFT_CENTER, title, t.font(11.5), pal.text);
    crate::icons::paint(
        ui.painter(),
        Rect::from_center_size(pos2(inner.right() - 12.0, inner.center().y), vec2(14.0, 14.0)),
        if open { Icon::ChevronDown } else { Icon::ChevronRight },
        pal.text2,
    );
    if resp.clicked() {
        app.ui.toggle_flyout(id);
    }
    open
}

fn padded<R>(ui: &mut Ui, add: impl FnOnce(&mut Ui) -> R) -> R {
    egui::Frame::NONE.inner_margin(egui::Margin::symmetric(12, 3)).show(ui, add).inner
}

fn check(ui: &mut Ui, label: &str, on: bool) -> Option<bool> {
    let mut v = on;
    let changed = padded(ui, |ui| {
        ui.spacing_mut().interact_size.y = 20.0;
        ui.checkbox(&mut v, egui::RichText::new(crate::i18n::tr(label)).size(11.5)).changed()
    });
    changed.then_some(v)
}

fn pill_row(ui: &mut Ui, label: &str, add: impl FnOnce(&mut Ui)) {
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let (r, _) = ui.allocate_exact_size(vec2(ui.available_width(), ui_pro::ROW_H), Sense::hover());
    ui.painter().text(pos2(r.left() + 12.0, r.center().y), Align2::LEFT_CENTER, crate::i18n::tr(label), t.font(11.5), pal.text2);
    let mut child = ui.new_child(
        egui::UiBuilder::new()
            .max_rect(Rect::from_min_max(pos2(r.left() + 12.0 + 88.0 + 8.0, r.top()), pos2(r.right() - 10.0, r.bottom())))
            .layout(egui::Layout::left_to_right(Align::Center)),
    );
    child.spacing_mut().item_spacing.x = 6.0;
    add(&mut child);
}

// ----------------------------------------------------------------------------------------- group bodies

fn basic(app: &mut LightcraftApp, ui: &mut Ui, d: &DevelopSettings, id: PhotoId, raw: bool) {
    let bw = crate::is_bw(d);
    // treatment chips
    padded(ui, |ui| {
        ui.horizontal(|ui| {
            ui.spacing_mut().item_spacing.x = 6.0;
            if ui_pro::chip(ui, "auto", crate::i18n::tr("Auto"), false).clicked() {
                let msg = match app.run("develop.auto", json!({})) {
                    Ok(_) | Err(_) => crate::i18n::tr("Auto settings applied").to_string(),
                };
                app.toast(ui.ctx(), msg);
            }
            if ui_pro::chip(ui, "bw", crate::i18n::tr("B&W"), bw).clicked() {
                let _ = app.run("develop.treatment", json!({}));
            }
            if ui_pro::chip(ui, "hdr", crate::i18n::tr("HDR"), d.hdr.enabled)
                .on_hover_text(crate::i18n::tr("Edit in HDR: highlights above SDR white, for HDR exports and displays"))
                .clicked()
            {
                let _ = app.run("develop.hdr", json!({"enabled": !d.hdr.enabled}));
            }
        });
    });
    // profile
    let name = app.session.profile_info(&d.profile.id).map(|(name, _)| name.to_string()).unwrap_or_else(|| "Color".to_string());
    pill_row(ui, "Profile", |ui| {
        let max = ui.available_width() - 30.0;
        let t = Tokens::get(ui.ctx());
        let pal = Pal::get(ui.ctx());
        let r = crate::widgets::dropdown_within(ui, "profile", crate::i18n::profile_label(&d.profile.id, &name), t.font(11.5), pal.text, max);
        let below = r.rect.bottom();
        egui::Popup::menu(&r).show(|ui| {
            crate::widgets::touch_menu_style(ui);
            super::edit::profile_menu(app, ui, d, below)
        });
        if ui_pro::icon_button(ui, "profileBrowser", Icon::ProfileGrid, 22.0, false, crate::i18n::tr("Browse Profiles")).clicked() {
            let _ = app.run("panel.profiles", json!({}));
        }
    });
    if d.profile.id != "lc.color" {
        control(app, ui, d, "profile.amount", true);
    }
    if app.session.source_info(id).local_tone.is_some() {
        let mut on = d.profile.camera_local_tone;
        if let Some(v) = check(ui, "Camera local tone mapping", on) {
            on = v;
            let _ = app.run("develop.merge", json!({"settings": {"profile": {"camera_local_tone": on}}, "label": "Camera Local Tone Mapping"}));
        }
    }
    // white balance
    pill_row(ui, "WB", |ui| {
        let t = Tokens::get(ui.ctx());
        let pal = Pal::get(ui.ctx());
        let r = crate::widgets::dropdown(ui, "wbMode", crate::i18n::tr(d.wb.mode.label()), t.font(11.5), pal.text);
        egui::Popup::menu(&r).show(|ui| {
            crate::widgets::touch_menu_style(ui);
            for m in WbMode::ALL {
                if m == WbMode::Custom {
                    continue;
                }
                if ui.selectable_label(d.wb.mode == m, m.label()).clicked() {
                    let mode = serde_json::to_value(m).unwrap_or_default();
                    let _ = app.run("develop.wb", json!({"mode": mode}));
                }
            }
        });
        let active = app.ui.tool == "wbPicker";
        if ui_pro::icon_button(ui, "wbPicker", Icon::Picker, 22.0, active, crate::i18n::tr("White Balance Selector (W)")).clicked() {
            if active {
                app.ui.tool.clear();
            } else if let Err(e) = app.run("tool.wbPicker", json!({})) {
                app.toast(ui.ctx(), e);
            }
        }
    });
    if raw {
        control(app, ui, d, "wb.temp", true);
        control(app, ui, d, "wb.tint", true);
    } else {
        let out = slider(ui, &super::edit::REL_TEMP, k_to_rel(d.wb.temp), true, None);
        super::edit::apply_slider_out(app, &super::edit::REL_TEMP, out, |app, v| {
            app.run("develop.set", json!({"control": "wb.temp", "value": rel_to_k(v)}))
        });
        let out = slider(ui, &super::edit::REL_TINT, d.wb.tint.clamp(-100.0, 100.0), true, None);
        super::edit::apply_slider_out(app, &super::edit::REL_TINT, out, |app, v| app.run("develop.set", json!({"control": "wb.tint", "value": v})));
    }
    control(app, ui, d, "light.exposure", true);
    control(app, ui, d, "color.vibrance", true);
    control(app, ui, d, "color.saturation", true);
}

fn tone(app: &mut LightcraftApp, ui: &mut Ui, d: &DevelopSettings, id: PhotoId) {
    super::edit::hdr_row(app, ui, d);
    for c in ["light.contrast", "light.highlights", "light.shadows", "light.whites", "light.blacks"] {
        control(app, ui, d, c, true);
    }
    if d.hdr.enabled {
        for c in ["hdr.sdrBrightness", "hdr.sdrContrast", "hdr.sdrHighlights", "hdr.sdrShadows", "hdr.sdrWhites", "hdr.sdrClarity"] {
            control(app, ui, d, c, true);
        }
    }
    ui.add_space(4.0);
    if disclosure(app, ui, "curve", "Tone Curve") {
        super::edit::curve_editor(app, ui, id, d);
    }
}

fn color(app: &mut LightcraftApp, ui: &mut Ui, d: &DevelopSettings, id: PhotoId) {
    if disclosure(app, ui, "mixer", if crate::is_bw(d) { "B&W Mixer" } else { "Mixer" }) {
        super::edit::mixer(app, ui, d);
    }
    if disclosure(app, ui, "grading", "Color Grading") {
        super::edit::grading(app, ui, d, id);
    }
    if !crate::is_bw(d) && disclosure(app, ui, "pointColor", "Point Color") {
        super::edit::point_color(app, ui, d);
    }
    if disclosure(app, ui, "calibration", "Calibration") {
        ui_pro::sub_title(ui, "Shadows");
        control(app, ui, d, "calibration.shadowsTint", true);
        for (title, k) in [("Red Primary", "red"), ("Green Primary", "green"), ("Blue Primary", "blue")] {
            ui_pro::sub_title(ui, title);
            control(app, ui, d, &format!("calibration.{k}Hue"), true);
            control(app, ui, d, &format!("calibration.{k}Sat"), true);
        }
    }
}

fn detail(app: &mut LightcraftApp, ui: &mut Ui, d: &DevelopSettings, id: PhotoId) {
    ui_pro::sub_title(ui, "Sharpening");
    for c in ["detail.sharpenAmount", "detail.sharpenRadius", "detail.sharpenDetail", "detail.sharpenMasking"] {
        control(app, ui, d, c, c == "detail.sharpenAmount" || d.detail.sharpen_amount > 0.0);
    }
    ui_pro::sub_title(ui, "Noise Reduction");
    for c in ["detail.nrLuminance", "detail.nrDetail", "detail.nrContrast", "detail.nrColor", "detail.nrColorDetail", "detail.nrColorSmoothness"] {
        control(app, ui, d, c, true);
    }
    ui_pro::sub_title(ui, "AI Denoise");
    let applicable = !matches!(app.session.denoise_photo_state(id), lightcraft_engine::denoise::PhotoState::NotApplicable);
    let on = d.enhance.denoise_enabled();
    super::denoise::detail_toggle(app, ui, id, on, applicable);
    control(app, ui, d, "enhance.denoise", applicable && on);
    super::denoise::detail_status(app, ui, id, if on { d.enhance.denoise } else { 0.0 });
}

fn optics(app: &mut LightcraftApp, ui: &mut Ui, d: &DevelopSettings, id: PhotoId) {
    let has_lens = app.session.catalog.photo(id).is_some_and(|p| p.embedded_lens.is_some());
    if let Some(v) = check(ui, "Remove Chromatic Aberration", d.optics.remove_ca) {
        let _ = app.run("develop.merge", json!({"settings": {"optics": {"remove_ca": v}}, "label": "Remove CA"}));
    }
    if let Some(v) = check(ui, "Enable Lens Corrections", d.optics.lens_profile) {
        let _ = app.run("develop.merge", json!({"settings": {"optics": {"lens_profile": v}}, "label": "Lens Corrections"}));
    }
    if d.optics.lens_profile {
        for c in ["optics.profileDistortion", "optics.profileVignetting"] {
            control(app, ui, d, c, has_lens);
        }
    }
    ui_pro::sub_title(ui, "Manual");
    for c in ["optics.distortion", "optics.vignetting"] {
        control(app, ui, d, c, true);
    }
    control(app, ui, d, "optics.vignettingMidpoint", d.optics.vignetting != 0.0);
    if disclosure(app, ui, "defringe", "Defringe") {
        control(app, ui, d, "optics.defringePurple", true);
        let on = d.optics.defringe_purple_amount > 0.0;
        control(app, ui, d, "optics.defringePurpleHueLo", on);
        control(app, ui, d, "optics.defringePurpleHueHi", on);
        control(app, ui, d, "optics.defringeGreen", true);
        let on = d.optics.defringe_green_amount > 0.0;
        control(app, ui, d, "optics.defringeGreenHueLo", on);
        control(app, ui, d, "optics.defringeGreenHueHi", on);
        ui_pro::sub_title(ui, "Lateral Chromatic Aberration");
        control(app, ui, d, "optics.caRed", true);
        control(app, ui, d, "optics.caBlue", true);
    }
    ui_pro::sub_title(ui, "Geometry");
    for s in controls::in_section(Section::Geometry) {
        control(app, ui, d, s.id, true);
    }
}

fn effects(app: &mut LightcraftApp, ui: &mut Ui, d: &DevelopSettings) {
    for c in ["effects.texture", "effects.clarity", "effects.dehaze"] {
        control(app, ui, d, c, true);
    }
    ui_pro::sub_title(ui, "Vignette");
    for c in ["vignette.amount", "vignette.midpoint", "vignette.feather", "vignette.roundness", "vignette.highlights"] {
        control(app, ui, d, c, c == "vignette.amount" || d.vignette.amount != 0.0);
    }
    ui_pro::sub_title(ui, "Grain");
    for c in ["grain.amount", "grain.size", "grain.roughness"] {
        control(app, ui, d, c, c == "grain.amount" || d.grain.amount != 0.0);
    }
}

// ----------------------------------------------------------------------------------------- histogram

/// Which curves the histogram draws.
#[derive(Clone, Copy, PartialEq, Eq)]
enum HistMode {
    Rgb,
    Luma,
}

/// The pinned histogram: an 84pt plot with the tonal-zone drag of the classic one, shadow / highlight clipping
/// toggles in its corners and an RGB / Luma switch. An HDR edit keeps the classic widget (it has the SDR / HDR scale).
fn histogram_pro(app: &mut LightcraftApp, ui: &mut Ui, id: PhotoId) {
    if app.session.develop_of(id).is_some_and(|d| d.hdr.enabled) {
        super::edit::histogram(app, ui, id);
        return;
    }
    let pal = Pal::get(ui.ctx());
    let t = Tokens::get(ui.ctx());
    let hist = super::edit::preview_histogram(app, id);
    let mode_key = ui.scope_id().with("pro-hist-mode");
    let mut mode = ui.data(|d| d.get_temp::<bool>(mode_key)).map_or(HistMode::Rgb, |luma| if luma { HistMode::Luma } else { HistMode::Rgb });
    let (outer, _) = ui.allocate_exact_size(vec2(ui.available_width(), 84.0 + 24.0), Sense::hover());
    register(ui, "histogram", outer);
    let plot = Rect::from_min_max(outer.min + vec2(10.0, 8.0), pos2(outer.right() - 10.0, outer.top() + 8.0 + 76.0));
    let resp = ui.interact(plot, ui.scope_id().with("pro-hist"), Sense::click_and_drag());
    crate::widgets::announce(&resp, crate::i18n::tr("Histogram"));
    ui.painter().rect_filled(plot, CornerRadius::same(ui_pro::CONTROL_R), Color32::from_black_alpha(70));
    let zone = super::histogram::interact(app, ui, &resp, plot, id);
    let p = ui.painter().with_clip_rect(plot);
    if let Some(a) = &zone {
        super::histogram::paint_zone(&p, plot, a, &t);
    }
    if let Some(h) = &hist {
        let smooth = |v: &[u32]| -> Vec<f32> {
            (0..256usize)
                .map(|i| {
                    let (a, b) = (i.saturating_sub(2), (i + 3).min(v.len()));
                    let s = v.get(a..b).unwrap_or(&[]);
                    s.iter().map(|x| *x as f32).sum::<f32>() / s.len().max(1) as f32
                })
                .collect()
        };
        let (r, g, b, l) = (smooth(&h.r), smooth(&h.g), smooth(&h.b), smooth(&h.luma));
        let peak = [&r, &g, &b, &l].iter().flat_map(|v| v.iter().skip(2).take(252)).fold(1.0f32, |a, b| a.max(*b));
        let at = |v: &[f32], i: usize| -> Pos2 {
            let y = v.get(i).copied().unwrap_or(0.0);
            pos2(plot.left() + plot.width() * i as f32 / 255.0, plot.bottom() - (plot.height() - 2.0) * (y / peak).sqrt().min(1.0))
        };
        // luminance fill
        let mut mesh = egui::epaint::Mesh::default();
        let fill = Color32::from_white_alpha(if mode == HistMode::Luma { 70 } else { 34 });
        for i in 0..256usize {
            let top = at(&l, i);
            mesh.colored_vertex(top, fill);
            mesh.colored_vertex(pos2(top.x, plot.bottom()), fill);
            if i > 0 {
                let k = (i as u32) * 2;
                mesh.indices.extend([k - 2, k - 1, k, k - 1, k + 1, k]);
            }
        }
        p.add(egui::Shape::mesh(mesh));
        if mode == HistMode::Rgb {
            for (v, c) in
                [(&r, Color32::from_rgb(0xE0, 0x50, 0x50)), (&g, Color32::from_rgb(0x44, 0xB0, 0x72)), (&b, Color32::from_rgb(0x4A, 0x7C, 0xE8))]
            {
                let pts: Vec<Pos2> = (0..256usize).map(|i| at(v, i)).collect();
                p.add(egui::Shape::line(pts, Stroke::new(1.2, c.gamma_multiply(0.9))));
            }
        } else {
            let pts: Vec<Pos2> = (0..256usize).map(|i| at(&l, i)).collect();
            p.add(egui::Shape::line(pts, Stroke::new(1.4, Color32::from_gray(225))));
        }
    }
    // clipping toggles in the corners: a triangle that lights up where the preview clips
    let clip = hist.as_ref().map(|h| h.clipping());
    let mut toggle = false;
    for (name, label, left, color, clipped) in [
        ("shadows", "Shadow clipping", true, pal.clip_sh, clip.map(|c| c.0 > 0.003)),
        ("highlights", "Highlight clipping", false, pal.clip_hi, clip.map(|c| c.1 > 0.003)),
    ] {
        let rect = if left {
            Rect::from_min_size(plot.left_top() + vec2(3.0, 3.0), vec2(18.0, 16.0))
        } else {
            Rect::from_min_size(pos2(plot.right() - 21.0, plot.top() + 3.0), vec2(18.0, 16.0))
        };
        let r = ui.interact(rect, ui.scope_id().with(("pro-clip", name)), Sense::click());
        register(ui, format!("histogram:{name}"), rect);
        r.widget_info(|| egui::WidgetInfo::selected(egui::Role::Button, true, app.ui.show_clipping, crate::i18n::tr(label)));
        let on = app.ui.show_clipping;
        let tri = if left {
            vec![rect.left_top() + vec2(2.0, 2.0), rect.right_top() + vec2(-2.0, 2.0), rect.left_bottom() + vec2(2.0, -2.0)]
        } else {
            vec![rect.right_top() + vec2(-2.0, 2.0), rect.left_top() + vec2(2.0, 2.0), rect.right_bottom() + vec2(-2.0, -2.0)]
        };
        let lit = clipped == Some(true) || on;
        let fill = if lit {
            color
        } else if r.hovered() {
            Color32::from_white_alpha(70)
        } else {
            Color32::from_white_alpha(36)
        };
        ui.painter().add(egui::Shape::convex_polygon(tri, fill, Stroke::NONE));
        if on {
            ui.painter().rect_stroke(rect, CornerRadius::same(4), Stroke::new(1.0, color), egui::StrokeKind::Inside);
        }
        if r.clicked() {
            toggle = true;
        }
        r.on_hover_text(format!(
            "{}\n{}",
            crate::i18n::tr(label),
            crate::i18n::tr(if on {
                "Click to hide clipping warnings for shadows and highlights."
            } else {
                "Click to show clipping warnings for shadows and highlights."
            })
        ));
    }
    if toggle {
        let _ = app.run("view.clipping", json!({}));
    }
    // footer: exposure info or the zone readout, and the mode switch
    let foot_y = plot.bottom() + 12.0;
    if let Some(text) = zone.as_ref().and_then(|a| a.readout()) {
        register(ui, "histogramReadout", outer);
        ui.painter().text(pos2(plot.left() + 2.0, foot_y), Align2::LEFT_CENTER, text, t.font(10.5), pal.text2);
    } else if let Some(ph) = app.session.catalog.photo(id) {
        let m = &ph.meta;
        let parts: Vec<String> = [
            m.iso.map(|i| format!("ISO {i}")),
            m.focal_mm.map(|f| format!("{f:.0}mm")),
            m.aperture.map(|a| format!("f/{a:.1}")),
            if m.shutter.is_empty() { None } else { Some(m.shutter.clone()) },
        ]
        .into_iter()
        .flatten()
        .collect();
        if !parts.is_empty() {
            ui.painter().text(pos2(plot.left() + 2.0, foot_y), Align2::LEFT_CENTER, parts.join(" \u{b7} "), t.font(10.5), pal.text3);
        }
    }
    let chip_w = 34.0;
    for (i, (label, m)) in [("RGB", HistMode::Rgb), ("Luma", HistMode::Luma)].into_iter().enumerate().rev() {
        let x1 = plot.right() - (1 - i) as f32 * (chip_w + 4.0);
        let r = Rect::from_min_max(pos2(x1 - chip_w, foot_y - 9.0), pos2(x1, foot_y + 9.0));
        if ui_pro::chip_in(ui, &format!("hist{label}"), r, label, mode == m).clicked() {
            mode = m;
            ui.data_mut(|d| d.insert_temp(mode_key, m == HistMode::Luma));
        }
    }
}
