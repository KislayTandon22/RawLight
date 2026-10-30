import SwiftUI
import UIKit

/// One sample of a drawn stroke: where, and how hard (0...1; a finger counts as 0.5).
struct StrokeSample { var point: CGPoint; var pressure: CGFloat }

/// A touch layer for drawing with Apple Pencil or a finger:
/// - reports every sample with pressure (coalesced touches, so fast strokes stay smooth);
/// - optional "Pencil only": fingers are ignored, so they never leave a mark;
/// - two-finger tap = undo, three-finger tap = redo;
/// - Pencil double-tap and Pencil Pro squeeze call `onPencilTap`.
struct PencilCanvas: UIViewRepresentable {
    var pencilOnly: Bool
    var onBegan: (StrokeSample) -> Void
    var onMoved: ([StrokeSample]) -> Void
    var onEnded: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onPencilTap: () -> Void

    func makeUIView(context: Context) -> CanvasView {
        let v = CanvasView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true
        let two = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.undo))
        two.numberOfTouchesRequired = 2
        two.cancelsTouchesInView = false
        let three = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.redo))
        three.numberOfTouchesRequired = 3
        three.cancelsTouchesInView = false
        v.addGestureRecognizer(two); v.addGestureRecognizer(three)
        let pencil = UIPencilInteraction()
        pencil.delegate = context.coordinator
        v.addInteraction(pencil)
        return v
    }

    func updateUIView(_ v: CanvasView, context: Context) {
        v.pencilOnly = pencilOnly
        v.onBegan = onBegan; v.onMoved = onMoved; v.onEnded = onEnded
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIPencilInteractionDelegate {
        var parent: PencilCanvas
        init(_ p: PencilCanvas) { parent = p }
        @objc func undo() { parent.onUndo() }
        @objc func redo() { parent.onRedo() }
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveTap tap: UIPencilInteraction.Tap) { parent.onPencilTap() }
        func pencilInteraction(_ interaction: UIPencilInteraction, didReceiveSqueeze squeeze: UIPencilInteraction.Squeeze) {
            if squeeze.phase == .ended { parent.onPencilTap() }
        }
    }

    final class CanvasView: UIView {
        var pencilOnly = false
        var onBegan: (StrokeSample) -> Void = { _ in }
        var onMoved: ([StrokeSample]) -> Void = { _ in }
        var onEnded: () -> Void = {}
        private var active: UITouch?

        private func sample(_ t: UITouch) -> StrokeSample {
            let p = t.location(in: self)
            if t.type == .pencil, t.maximumPossibleForce > 0 { return StrokeSample(point: p, pressure: min(max(t.force / t.maximumPossibleForce, 0.05), 1)) }
            return StrokeSample(point: p, pressure: 0.5)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard active == nil, event?.allTouches?.count ?? 1 == 1, let t = touches.first, !(pencilOnly && t.type != .pencil) else { return }
            active = t
            onBegan(sample(t))
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = active, touches.contains(t) else { return }
            // a second finger landing means a gesture (undo/redo), not drawing
            if (event?.allTouches?.count ?? 1) > 1 { cancel(); return }
            onMoved((event?.coalescedTouches(for: t) ?? [t]).map(sample))
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = active, touches.contains(t) else { return }
            active = nil
            onEnded()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { cancel() }

        private func cancel() { if active != nil { active = nil; onEnded() } }
    }
}
