//! The Pro desktop Develop workspace: dense rows, six groups, wheel and numeric entry rules, the touch gate.

use egui::{Event, Key, Modifiers, MouseWheelUnit, PointerButton, Rect, vec2};
use lightcraft_develop::{Section, controls};

use crate::panels::edit_pro::{GROUPS, group_specs};
use crate::panels::ui_pro::ROW_H;
use crate::widgets::{SliderOut, slider, take_registry};
use crate::{LightcraftApp, Services, headless::HeadlessView};

fn dock_widgets(pro: bool, width: f32) -> Vec<(String, Rect)> {
    let mut app = LightcraftApp::new(lightcraft_engine::Session::with_demo(), Services::default());
    let photo = app.session.active().unwrap();
    let ctx = egui::Context::default();
    crate::theme::install_fonts(&ctx);
    crate::theme::apply(&ctx);
    app.ui.open_sections =
        vec!["pro.init".into(), "pro.basic".into(), "pro.tone".into(), "pro.detail".into(), "pro.optics".into(), "pro.effects".into()];
    let mut widgets = Vec::new();
    for frame in 0..3 {
        crate::theme::set_desktop_pro(&ctx, pro);
        let raw = HeadlessView::raw_input(vec2(width, 6000.0), 1.0, frame as f64 / 60.0, vec![]);
        let mut out = ctx.run_ui(raw, |ui| {
            egui::CentralPanel::default().frame(egui::Frame::NONE).show(ui, |ui| crate::panels::edit::show(&mut app, ui, photo));
        });
        out.textures_delta.clear();
        widgets = take_registry(&ctx);
    }
    widgets
}

// Feature: Pro shows six groups of 26pt rows; Classic keeps its sections and 45pt rows
#[test]
fn pro_draws_six_groups_of_dense_rows() {
    let pro = dock_widgets(true, 322.0);
    let rect = |w: &[(String, Rect)], id: &str| w.iter().find(|(n, _)| n == id).unwrap_or_else(|| panic!("{id} not drawn")).1;
    for (gid, _, _) in GROUPS {
        rect(&pro, &format!("section:{gid}"));
    }
    let (a, b) = (rect(&pro, "slider:light.highlights"), rect(&pro, "slider:light.shadows"));
    assert!((b.center().y - a.center().y - ROW_H).abs() < 0.5, "rows are {ROW_H}pt apart, got {}", b.center().y - a.center().y);
    for (id, r) in pro.iter().filter(|(id, _)| id.starts_with("slider")) {
        assert!(r.right() <= 322.0, "{id} {r:?} is cut off by the panel");
    }
    let classic = dock_widgets(false, 322.0);
    assert!(classic.iter().any(|(n, _)| n == "section:light"), "Classic is unchanged");
    assert!(!classic.iter().any(|(n, _)| n == "section:basic"), "Pro groups never show in Classic");
}

// Feature: every control sits in exactly one group (specs drive the groups)
#[test]
fn every_control_of_the_six_groups_is_in_one_group() {
    let in_groups: Vec<&str> = GROUPS.iter().flat_map(|(g, _, _)| group_specs(g)).map(|s| s.id).collect();
    for s in controls::in_section(Section::Light).filter(|s| !s.id.starts_with("hdr.")) {
        assert_eq!(in_groups.iter().filter(|i| **i == s.id).count(), 1, "{} is in exactly one group", s.id);
    }
    for section in
        [Section::Effects, Section::Vignette, Section::Grain, Section::Detail, Section::Optics, Section::Geometry, Section::Mixer, Section::Grading]
    {
        for s in controls::in_section(section) {
            assert_eq!(in_groups.iter().filter(|i| **i == s.id).count(), 1, "{} is in exactly one group", s.id);
        }
    }
}

// Feature: the layout never applies on a touch host
#[test]
fn pro_is_off_on_touch_hosts() {
    let ctx = egui::Context::default();
    crate::theme::set_desktop_pro(&ctx, true);
    assert!(crate::theme::desktop_pro(&ctx));
    crate::theme::set_touch_ui(&ctx, true);
    assert!(!crate::theme::desktop_pro(&ctx));
}

struct Row {
    view: HeadlessView,
    value: f64,
    time: f64,
    pos: egui::Pos2,
    track: Rect,
    field: Rect,
}

impl Row {
    fn new() -> Self {
        let mut r = Row { view: HeadlessView::new(), value: 0.0, time: 0.0, pos: egui::Pos2::ZERO, track: Rect::NOTHING, field: Rect::NOTHING };
        crate::theme::set_desktop_pro(&r.view.ctx, true);
        for _ in 0..3 {
            r.frame(vec![]);
        }
        r
    }
    fn frame(&mut self, events: Vec<Event>) -> SliderOut {
        self.time += 0.02;
        let spec = *controls::find("light.exposure").unwrap();
        let mut out = SliderOut::default();
        crate::theme::set_desktop_pro(&self.view.ctx, true);
        self.view.run(HeadlessView::raw_input(vec2(330.0, 100.0), 1.0, self.time, events), |ui| {
            out = slider(ui, &spec, self.value, true, None);
        });
        let registry = take_registry(&self.view.ctx);
        let find = |n: &str| registry.iter().find(|(id, _)| id == n).map(|(_, r)| *r).unwrap();
        self.track = find("slider:light.exposure");
        self.field = find("sliderValue:light.exposure");
        if let Some(v) = out.value {
            self.value = v;
        }
        out
    }
    fn mv(&mut self, p: egui::Pos2) {
        self.pos = p;
        self.frame(vec![Event::PointerMoved(p)]);
    }
    fn click(&mut self, p: egui::Pos2) {
        self.mv(p);
        let b = |pressed| Event::PointerButton { pos: p, button: PointerButton::Primary, pressed, modifiers: Modifiers::NONE };
        self.frame(vec![b(true)]);
        self.frame(vec![b(false)]);
    }
    fn wheel(&mut self) -> bool {
        let mut moved = false;
        let ev = Event::MouseWheel {
            unit: MouseWheelUnit::Line,
            delta: vec2(0.0, 1.0),
            phase: egui::TouchPhase::Move,
            source: egui::MouseWheelSource::Wheel,
            modifiers: Modifiers::NONE,
        };
        moved |= self.frame(vec![ev]).value.is_some();
        for _ in 0..40 {
            moved |= self.frame(vec![]).value.is_some();
        }
        moved
    }
}

// Feature: the wheel nudges only over the value field (or a focused slider), so scrolling the dock never edits
#[test]
fn the_wheel_edits_only_over_the_value_or_a_focused_slider() {
    let mut r = Row::new();
    r.mv(r.track.center());
    assert!(!r.wheel(), "a wheel over an unfocused track scrolls the dock instead");
    let mut r = Row::new();
    r.mv(r.field.center());
    assert!(r.wheel(), "a wheel over the value field nudges it");
    assert!(r.value > 0.0);
    // a click gives the slider keyboard focus; then the wheel over it edits
    let mut r = Row::new();
    r.click(r.track.center());
    let before = r.value;
    assert!(r.wheel(), "a wheel over a focused slider nudges it");
    assert_ne!(r.value, before);
}

// Feature: click the value, type, Enter commits as one step
#[test]
fn clicking_the_value_types_a_number() {
    let mut r = Row::new();
    r.click(r.field.center());
    for _ in 0..3 {
        r.frame(vec![]);
    }
    r.frame(vec![Event::Text("0.5".into())]);
    let out = r.frame(vec![Event::Key { key: Key::Enter, physical_key: None, pressed: true, repeat: false, modifiers: Modifiers::NONE }]);
    assert_eq!(out.value, Some(0.5));
    assert!(out.drag_started && out.drag_stopped, "one undo step");
}

// Feature: double-click the label resets
#[test]
fn double_clicking_the_label_resets() {
    let mut r = Row::new();
    r.value = 1.2;
    let label = egui::pos2(r.track.left() - 40.0, r.track.center().y);
    r.click(label);
    let b = |pressed| Event::PointerButton { pos: label, button: PointerButton::Primary, pressed, modifiers: Modifiers::NONE };
    r.frame(vec![b(true)]);
    let out = r.frame(vec![b(false)]);
    assert!(out.reset && out.value == Some(0.0));
}
