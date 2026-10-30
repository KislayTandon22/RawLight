import SwiftUI
import UIKit

/// A touch layer for slider tracks that only claims *horizontal* drags (and taps), so a vertical
/// swipe that starts on a slider still scrolls the panel instead of moving the slider.
struct SliderTouch: UIViewRepresentable {
    var onChanged: (CGFloat) -> Void   // x in points inside the track
    var onEnded: () -> Void

    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.delegate = v
        v.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:)))
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ v: TouchView, context: Context) { context.coordinator.parent = self }
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: SliderTouch
        init(_ p: SliderTouch) { parent = p }
        @objc func pan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began, .changed: parent.onChanged(g.location(in: g.view).x)
            case .ended, .cancelled, .failed: parent.onEnded()
            default: break
            }
        }
        @objc func tap(_ g: UITapGestureRecognizer) { parent.onChanged(g.location(in: g.view).x); parent.onEnded() }
    }

    final class TouchView: UIView, UIGestureRecognizerDelegate {
        override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, pan.view === self else { return true }
            let v = pan.velocity(in: self)
            return abs(v.x) > abs(v.y)
        }
    }
}
