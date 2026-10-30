import SwiftUI

/// Interactive point curve for one channel. Drag points, tap to add, double-tap a point to remove.
struct CurveEditor: View {
    @Binding var channel: String
    @Binding var points: [CGPoint]
    let histogram: [UInt32]
    let onChange: ([CGPoint]) -> Void
    let onEnd: () -> Void
    @State private var dragging: Int?

    private let channels = [("master", "RGB"), ("red", "R"), ("green", "G"), ("blue", "B")]

    private var tint: Color {
        switch channel { case "red": .red; case "green": .green; case "blue": .blue; default: .white }
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Channel", selection: $channel) {
                ForEach(channels, id: \.0) { Text($0.1).tag($0.0) }
            }.pickerStyle(.segmented)
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.35))
                    Canvas { ctx, size in
                        for i in 1..<4 {
                            let p = CGFloat(i) / 4
                            var g = Path()
                            g.move(to: CGPoint(x: p * size.width, y: 0)); g.addLine(to: CGPoint(x: p * size.width, y: size.height))
                            g.move(to: CGPoint(x: 0, y: p * size.height)); g.addLine(to: CGPoint(x: size.width, y: p * size.height))
                            ctx.stroke(g, with: .color(.white.opacity(0.08)), lineWidth: 1)
                        }
                        var diag = Path()
                        diag.move(to: CGPoint(x: 0, y: size.height)); diag.addLine(to: CGPoint(x: size.width, y: 0))
                        ctx.stroke(diag, with: .color(.white.opacity(0.15)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        let pts = full.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
                        var curve = Path()
                        for (i, p) in smooth(pts, size: size).enumerated() { i == 0 ? curve.move(to: p) : curve.addLine(to: p) }
                        ctx.stroke(curve, with: .color(tint), lineWidth: 2.5)
                    }
                    ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                        Circle().fill(dragging == i ? Theme.accent : .white).frame(width: 16, height: 16)
                            .shadow(radius: 2)
                            .position(x: p.x * s, y: (1 - p.y) * s)
                    }
                }
                .frame(width: s, height: s)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = CGPoint(x: min(max(v.location.x / s, 0), 1), y: min(max(1 - v.location.y / s, 0), 1))
                        if dragging == nil {
                            if let i = points.indices.min(by: { dist(points[$0], p) < dist(points[$1], p) }), dist(points[i], p) < 0.07 {
                                dragging = i
                            } else {
                                points.append(p); points.sort { $0.x < $1.x }
                                dragging = points.firstIndex(of: p)
                            }
                        }
                        if let i = dragging, i < points.count {
                            points[i] = p
                            // keep order by clamping against neighbours
                            let lo = i > 0 ? points[i - 1].x + 0.01 : 0, hi = i < points.count - 1 ? points[i + 1].x - 0.01 : 1
                            points[i].x = min(max(p.x, lo), hi)
                            onChange(points)
                        }
                    }
                    .onEnded { _ in dragging = nil; onEnd() })
                .simultaneousGesture(TapGesture(count: 2).onEnded {
                    if let i = dragging ?? points.indices.last, !points.isEmpty { points.remove(at: i); onChange(points); onEnd() }
                })
                .frame(maxWidth: .infinity)
            }
            .aspectRatio(1, contentMode: .fit)
            Button("Reset curve") { points = []; onChange([]); onEnd() }
                .font(.footnote).buttonStyle(.bordered).tint(Theme.accent)
        }
    }

    private var full: [CGPoint] { [CGPoint(x: 0, y: 0)] + points + [CGPoint(x: 1, y: 1)] }
    private func dist(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    /// Monotone-ish smooth line through the points for display (the engine evaluates the real curve).
    private func smooth(_ pts: [CGPoint], size: CGSize) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        var out: [CGPoint] = []
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1], p3 = pts[min(i + 2, pts.count - 1)]
            for s in 0..<16 {
                let t = CGFloat(s) / 16, t2 = t * t, t3 = t2 * t
                let x = 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3)
                let y = 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
                out.append(CGPoint(x: x, y: min(max(y, 0), size.height)))
            }
        }
        out.append(pts[pts.count - 1])
        return out
    }
}
