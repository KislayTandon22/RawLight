import SwiftUI

/// Tone curve: a point curve per channel (RGB, R, G, B) and the parametric curve.
///
/// Point curves always include their two end points (0,0) and (1,1), like the engine's own curve:
/// a single added point on its own would otherwise leave the engine with too few points to draw
/// a curve. Press near a point to drag it, press empty space to add a point and drag it, double-tap
/// a point to remove it. The line is drawn with the same monotone spline the engine evaluates.
struct CurveEditor: View {
    @Binding var channel: String
    @Binding var points: [CGPoint]            // full list, end points included
    let histogram: [UInt32]                   // 4 x 256: r, g, b, luma
    let controls: [Control]
    let setControl: (String, Double, Bool) -> Void
    let onChange: ([CGPoint]) -> Void         // live, while dragging
    let onEnd: () -> Void                     // finger lifted
    let onBegin: () -> Void                   // a drag starts (group undo)
    @State private var dragging: Int?
    @GestureState private var isDown = false
    @State private var readout: CGPoint?

    private let channels = [("master", "RGB"), ("red", "R"), ("green", "G"), ("blue", "B"), ("parametric", "Param")]

    private var tint: Color {
        switch channel { case "red": Color(hex: "#e5484d"); case "green": Color(hex: "#3cc050"); case "blue": Color(hex: "#4a8fff"); default: .white }
    }
    private var histIndex: Int { ["red": 0, "green": 1, "blue": 2][channel] ?? 3 }

    /// The points to work with: at least the two end points, sorted by x.
    private var pts: [CGPoint] {
        let v = points.filter { $0.x.isFinite && $0.y.isFinite }.sorted { $0.x < $1.x }
        return v.count < 2 ? [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)] : v
    }

    var body: some View {
        VStack(spacing: 8) {
            Picker("Channel", selection: $channel) { ForEach(channels, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented)
            if channel == "parametric" { parametric } else { graph }
        }
    }

    // MARK: point curve

    private var graph: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let s = min(geo.size.width, geo.size.height)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.35))
                    Canvas { ctx, size in
                        drawHistogram(&ctx, size)
                        for i in 1..<4 {
                            let p = CGFloat(i) / 4
                            var g = Path()
                            g.move(to: CGPoint(x: p * size.width, y: 0)); g.addLine(to: CGPoint(x: p * size.width, y: size.height))
                            g.move(to: CGPoint(x: 0, y: p * size.height)); g.addLine(to: CGPoint(x: size.width, y: p * size.height))
                            ctx.stroke(g, with: .color(.white.opacity(0.09)), lineWidth: 1)
                        }
                        var diag = Path()
                        diag.move(to: CGPoint(x: 0, y: size.height)); diag.addLine(to: CGPoint(x: size.width, y: 0))
                        ctx.stroke(diag, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        var line = Path()
                        let curve = MonotoneCurve(pts)
                        for i in 0...96 {
                            let x = Double(i) / 96
                            let p = CGPoint(x: x * size.width, y: (1 - min(max(curve.eval(x), 0), 1)) * size.height)
                            i == 0 ? line.move(to: p) : line.addLine(to: p)
                        }
                        ctx.stroke(line, with: .color(tint), lineWidth: 2.5)
                    }
                    ForEach(Array(pts.enumerated()), id: \.offset) { i, p in
                        Circle().fill(dragging == i ? Theme.accent : tint).frame(width: dragging == i ? 20 : 14, height: dragging == i ? 20 : 14)
                            .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 1))
                            .position(x: p.x * s, y: (1 - p.y) * s)
                    }
                    if let r = readout {
                        Text("\(Int((r.x * 255).rounded())) / \(Int((r.y * 255).rounded()))").font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary).padding(6)
                    }
                }
                .frame(width: s, height: s)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .updating($isDown) { _, state, _ in state = true }
                    .onChanged { v in drag(v.startLocation, v.location, s) }
                    .onEnded { v in end(v, s) })
                .onChange(of: isDown) { _, down in
                    // the system cancelled the gesture (a scroll took over): close the interaction cleanly
                    if !down, dragIndex != nil { dragIndex = nil; dragging = nil; readout = nil; onEnd() }
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement().accessibilityIdentifier("curve.graph")
            }
            .aspectRatio(1, contentMode: .fit)
            HStack(spacing: 8) {
                Button("Reset curve") { onBegin(); onChange([]); onEnd() }
                Menu("Presets") {
                    ForEach(["Linear", "Medium Contrast", "Strong Contrast", "Lighten", "Darken"], id: \.self) { name in
                        Button(name) { NotificationCenter.default.post(name: .curvePreset, object: name) }
                    }
                }
            }
            .font(.footnote).buttonStyle(.bordered).tint(Theme.accent)
        }
    }

    private func drawHistogram(_ ctx: inout GraphicsContext, _ size: CGSize) {
        guard histogram.count == 1024 else { return }
        let base = histIndex * 256
        let peak = max(1, (3..<253).map { histogram[base + $0] }.max() ?? 1)
        var p = Path()
        p.move(to: CGPoint(x: 0, y: size.height))
        for i in 0..<256 {
            let v = min(Double(histogram[base + i]) / Double(peak), 1)
            p.addLine(to: CGPoint(x: Double(i) / 255 * size.width, y: size.height - v * size.height * 0.9))
        }
        p.addLine(to: CGPoint(x: size.width, y: size.height)); p.closeSubpath()
        ctx.fill(p, with: .color(tint.opacity(0.16)))
    }

    @State private var dragIndex: Int?
    @State private var lastTap: (CGPoint, Date)?

    private func norm(_ p: CGPoint, _ s: CGFloat) -> CGPoint { CGPoint(x: min(max(p.x / s, 0), 1), y: min(max(1 - p.y / s, 0), 1)) }

    private func drag(_ start: CGPoint, _ loc: CGPoint, _ s: CGFloat) {
        var v = pts
        if dragIndex == nil {
            // pick the point under the press (not where the finger is once the drag has started)
            let sp = norm(start, s)
            if let i = v.indices.min(by: { hypot(v[$0].x - sp.x, v[$0].y - sp.y) < hypot(v[$1].x - sp.x, v[$1].y - sp.y) }),
               hypot(v[i].x - sp.x, v[i].y - sp.y) * Double(s) < 26 {
                dragIndex = i
            } else {
                let i = v.firstIndex { $0.x > sp.x } ?? v.count
                v.insert(sp, at: i)
                dragIndex = i
            }
            dragging = dragIndex
            onBegin()
        }
        guard let i = dragIndex, i < v.count else { return }
        var p = norm(loc, s)
        let lo = i == 0 ? 0 : v[i - 1].x + 0.01, hi = i == v.count - 1 ? 1 : v[i + 1].x - 0.01
        p.x = lo <= hi ? min(max(p.x, lo), hi) : (v[max(i - 1, 0)].x + v[min(i + 1, v.count - 1)].x) / 2
        if i == 0 { p.x = min(p.x, hi) } else if i == v.count - 1 { p.x = max(p.x, lo) }
        v[i] = p
        readout = p
        onChange(v)
    }

    private func end(_ v: DragGesture.Value, _ s: CGFloat) {
        let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y)
        // double-tap on an interior point removes it
        if moved < 6, let i = dragIndex {
            let now = Date()
            if let (p, t) = lastTap, now.timeIntervalSince(t) < 0.35, hypot(p.x - v.location.x, p.y - v.location.y) < 20, i > 0, i < pts.count - 1 {
                var q = pts; q.remove(at: i); onChange(q)
                lastTap = nil
            } else { lastTap = (v.location, now) }
        }
        dragIndex = nil; dragging = nil; readout = nil
        onEnd()
    }

    // MARK: parametric

    private var parametric: some View {
        VStack(spacing: 8) {
            ForEach(["curve.highlights", "curve.lights", "curve.darks", "curve.shadows"], id: \.self) { id in slider(id) }
            Text("Region splits").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(["curve.splitShadows", "curve.splitMid", "curve.splitHighlights"], id: \.self) { id in slider(id) }
        }
    }

    private func slider(_ id: String) -> some View {
        Group {
            if let c = controls.first(where: { $0.id == id }) {
                ColorSlider(control: c, onChange: { setControl(id, $0, false) }, onEnd: { v in setControl(id, v, true) }, reset: { setControl(id, c.def, true) }, compact: true)
            }
        }
    }
}

extension Notification.Name { static let curvePreset = Notification.Name("rawlight.curvePreset") }

/// Fritsch–Carlson monotone cubic through the points: the same family of curve the engine evaluates.
struct MonotoneCurve {
    private let xs: [Double], ys: [Double], m: [Double]
    init(_ p: [CGPoint]) {
        xs = p.map { Double($0.x) }; ys = p.map { Double($0.y) }
        let n = p.count
        var d = [Double](repeating: 0, count: max(n - 1, 0))
        for i in 0..<max(n - 1, 0) { d[i] = (ys[i + 1] - ys[i]) / max(xs[i + 1] - xs[i], 1e-9) }
        var m = [Double](repeating: 0, count: n)
        if n > 1 {
            m[0] = d[0]; m[n - 1] = d[n - 2]
            for i in 1..<(n - 1) { m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2 }
            for i in 0..<(n - 1) {
                if d[i] == 0 { m[i] = 0; m[i + 1] = 0; continue }
                let a = m[i] / d[i], b = m[i + 1] / d[i], h = a * a + b * b
                if h > 9 { let t = 3 / h.squareRoot(); m[i] = t * a * d[i]; m[i + 1] = t * b * d[i] }
            }
        }
        self.m = m
    }
    func eval(_ x: Double) -> Double {
        guard xs.count > 1 else { return x }
        if x <= xs[0] { return ys[0] }
        if x >= xs[xs.count - 1] { return ys[ys.count - 1] }
        var i = 0
        while i < xs.count - 2 && x > xs[i + 1] { i += 1 }
        let h = xs[i + 1] - xs[i], t = (x - xs[i]) / h, t2 = t * t, t3 = t2 * t
        return (2 * t3 - 3 * t2 + 1) * ys[i] + (t3 - 2 * t2 + t) * h * m[i] + (-2 * t3 + 3 * t2) * ys[i + 1] + (t3 - t2) * h * m[i + 1]
    }
}
