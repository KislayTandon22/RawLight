//! The Liquid Glass look for the iPad's control layer: bars and panels that float, inset, over the dark
//! canvas as translucent rounded shapes with a light rim and a soft shadow. There is no real backdrop blur
//! (the photo is drawn in the same layer as the UI), so the material is approximated: a slightly lifted,
//! translucent fill, a one-point light edge, and depth from the shadow. Glass is only for controls and
//! navigation, never for photos, thumbnails or text blocks; neighbouring controls share one shell.

use egui::{Color32, CornerRadius, Frame, Margin, Stroke, epaint::Shadow};

/// Corner radius of a bar or panel shell; controls inside use smaller, concentric radii.
pub const SHELL_RADIUS: u8 = 22;
/// Gap between a floating shell and the window edge or its neighbours.
pub const GAP: i8 = 8;

/// Whether the glass look applies (the iPad's touch layout in a dark theme).
pub fn active(ctx: &egui::Context) -> bool {
    crate::theme::touch_ui(ctx) && ctx.global_style().visuals.dark_mode
}

pub fn fill() -> Color32 {
    Color32::from_rgba_unmultiplied(40, 42, 52, 214)
}

/// The light rim: a hairline brighter than the fill, as light catching a glass edge.
pub fn rim() -> Stroke {
    Stroke::new(1.0, Color32::from_rgba_unmultiplied(255, 255, 255, 40))
}

pub fn shadow() -> Shadow {
    Shadow { offset: [0, 8], blur: 28, spread: 0, color: Color32::from_black_alpha(120) }
}

/// A floating shell: `inner` is the padding around its content, `outer` the gap to what surrounds it.
pub fn shell(inner: Margin, outer: Margin) -> Frame {
    Frame::NONE.fill(fill()).stroke(rim()).corner_radius(CornerRadius::same(SHELL_RADIUS)).shadow(shadow()).inner_margin(inner).outer_margin(outer)
}

/// The surface the floating shells sit on: the canvas colour behind everything (so the gaps and the status-bar
/// strip match the photo area instead of showing the bare window).
pub fn paint_backdrop(ctx: &egui::Context) {
    if !active(ctx) {
        return;
    }
    let t = crate::theme::Tokens::get(ctx);
    ctx.layer_painter(egui::LayerId::background()).rect_filled(ctx.content_rect(), 0.0, t.canvas);
}

/// A fade from the glass colour to clear across `rect`, opaque at the left edge when `opaque_left` (else at the
/// right): drawn over the end of a scrolling strip to say that more controls lie beyond it.
pub fn fade_edge(painter: &egui::Painter, rect: egui::Rect, opaque_left: bool) {
    let (near, far) = (fill(), Color32::TRANSPARENT);
    let (c_left, c_right) = if opaque_left { (near, far) } else { (far, near) };
    let mut mesh = egui::epaint::Mesh::default();
    mesh.colored_vertex(rect.left_top(), c_left);
    mesh.colored_vertex(rect.right_top(), c_right);
    mesh.colored_vertex(rect.right_bottom(), c_right);
    mesh.colored_vertex(rect.left_bottom(), c_left);
    mesh.add_triangle(0, 1, 2);
    mesh.add_triangle(0, 2, 3);
    painter.add(egui::Shape::mesh(mesh));
}
