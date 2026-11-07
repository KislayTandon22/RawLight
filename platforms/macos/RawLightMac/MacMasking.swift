import SwiftUI

/// Everything the Mask tab draws and does on the photo: tap an Object (Include / Exclude), mask by word, paint a brush that follows
/// edges, drag the handles of a linear or radial mask, and the red overlay that shows the selected mask.
@Observable @MainActor final class MaskState {
    struct Tap: Identifiable { let id = UUID(); let x: Double, y: Double, exclude: Bool, group: Int, cmds: Int }
    var items: [MacMask] = []
    var active: Int?
    var showMask = true
    var objectPick = false
    var exclude = false
    var taps: [Tap] = []
    var objectMask: Int?
    var group = 0
    var busy = false
    var error: String?
    var readout = ""
    var brushOn = true
    var brushSize = 0.03
    var erase = false
    var edgeAware = true
    var wordSheet = false

    var activeItem: MacMask? { items.first { $0.id == active } }
    func resetObject() { taps = []; objectMask = nil; error = nil; group = 0 }
}

extension DevelopModel {
    func refreshMasks(_ engine: MacEngine) async {
        let r = await engine.masks()
        mk.items = r.items; mk.active = r.active
    }

    /// Redraws the photo (with the red mask overlay when the Mask tab shows it) and tells the library its thumbnail changed.
    func afterMaskChange(_ id: UInt64, _ engine: MacEngine) async {
        await refreshMasks(engine)
        await render(id, engine, draft: false)
        await reloadLists(engine)
        onCommit?(id)
    }

    // MARK: Object

    func startObjectTool() { mk.resetObject(); mk.objectPick = true; mk.exclude = false; mk.showMask = true }
    func stopObjectTool() { mk.objectPick = false; mk.resetObject() }

    func tapObject(x: Double, y: Double, id: UInt64, engine: MacEngine) async {
        guard mk.objectPick, !mk.busy, (0...1).contains(x), (0...1).contains(y) else { return }
        mk.busy = true; mk.error = nil; mk.group += 1
        defer { mk.busy = false }
        do {
            var cmds = 0
            // a later tap always extends the mask the first tap made
            if mk.objectMask == nil, mk.taps.contains(where: { !$0.exclude }) { mk.objectMask = (await engine.masks()).active }
            if let mid = mk.objectMask {
                _ = try await engine.execute("mask.objectPoint", ["x": x, "y": y, "exclude": mk.exclude, "id": mid]); cmds = 1
            } else if !mk.exclude {
                let r = try await engine.execute("mask.add", ["kind": "object", "points": [[x, y]]]) as? [String: Any]
                mk.objectMask = (r?["activeMask"] as? NSNumber)?.intValue; cmds = 1
            } else {
                mk.error = "Tap Include on the object first."; return
            }
            mk.taps.append(.init(x: x, y: y, exclude: mk.exclude, group: mk.group, cmds: cmds))
            mk.readout = "\(SegmenterReadout.path) · \(mk.taps.count) tap\(mk.taps.count == 1 ? "" : "s") · \(SegmenterReadout.text.components(separatedBy: " · ").last ?? "")"
        } catch { mk.error = "Couldn't pick an object there. Try the middle of it. (\(error.localizedDescription))" }
        await afterMaskChange(id, engine)
    }

    func undoObjectTap(id: UInt64, engine: MacEngine) async {
        guard let g = mk.taps.last?.group else { return }
        let n = mk.taps.filter { $0.group == g }.reduce(0) { $0 + $1.cmds }
        for _ in 0..<max(1, n) { _ = try? await engine.execute("edit.undo") }
        mk.taps.removeAll { $0.group == g }
        if mk.taps.isEmpty { mk.objectMask = nil }
        await afterMaskChange(id, engine)
    }

    func clearObject(id: UInt64, engine: MacEngine) async {
        if let mid = mk.objectMask { _ = try? await engine.execute("mask.delete", ["id": mid]) }
        mk.resetObject()
        await afterMaskChange(id, engine)
    }

    // MARK: Word

    func maskByWord(_ index: Int, _ name: String, id: UInt64, engine: MacEngine) async {
        guard !mk.busy else { return }
        mk.busy = true; mk.error = nil; defer { mk.busy = false }
        do { _ = try await engine.execute("mask.add", ["kind": "object", "points": [TextMask.point(for: index)], "label": name]); mk.showMask = true }
        catch { mk.error = "Couldn't find “\(name)” in this photo." }
        await afterMaskChange(id, engine)
    }

    // MARK: Brush and handles

    func paintBrush(_ pts: [CGPoint], id: UInt64, engine: MacEngine) async {
        guard pts.count > 1, let m = mk.active else { return }
        _ = try? await engine.execute("develop.beginInteraction", ["label": "Brush"])
        var i = 0
        while i < pts.count - 1 {
            let chunk = Array(pts[i..<min(i + 9, pts.count)])
            _ = try? await engine.execute("mask.brushStroke", ["id": m, "points": chunk.map { [Double($0.x), Double($0.y)] }, "size": mk.brushSize,
                                                              "erase": mk.erase, "autoMask": mk.edgeAware])
            i += 8
        }
        _ = try? await engine.execute("develop.endInteraction")
        await afterMaskChange(id, engine)
    }

    func updateShape(_ shape: [String: Any], id: UInt64, engine: MacEngine, final: Bool) async {
        guard let m = mk.active else { return }
        _ = try? await engine.execute("mask.update", ["id": m, "shape": shape])
        if final { await afterMaskChange(id, engine) } else { await render(id, engine, draft: true) }
    }
}

/// The interactive layer over the photo for the Mask tab. Its size is the photo's, so points are fractions of its width and height.
struct MaskCanvas: View {
    @Environment(DevelopModel.self) private var dev
    @Environment(LibraryModel.self) private var lib
    @State private var stroke: [CGPoint] = []
    @State private var drag: String?
    @State private var origin: (CGPoint, CGPoint)?

    var body: some View {
        GeometryReader { g in
            let mk = dev.mk
            let long = max(g.size.width, g.size.height)
            ZStack {
                if mk.objectPick {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { p in
                            guard let id = lib.activeID, g.size.width > 0 else { return }
                            Task { await dev.tapObject(x: p.x / g.size.width, y: p.y / g.size.height, id: id, engine: lib.engine) }
                        }
                    ForEach(mk.taps) { t in
                        Image(systemName: t.exclude ? "minus.circle.fill" : "plus.circle.fill").font(.system(size: 22))
                            .symbolRenderingMode(.palette).foregroundStyle(.white, t.exclude ? Color.red : Color.green).shadow(radius: 2)
                            .position(x: t.x * g.size.width, y: t.y * g.size.height).allowsHitTesting(false)
                    }
                } else if let m = mk.activeItem {
                    Canvas { ctx, _ in draw(m, g.size, ctx) }.allowsHitTesting(false)
                    Color.clear.contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { v in change(m, v, g.size, long) }
                            .onEnded { v in end(m, v, g.size) })
                }
            }
        }
    }

    private func pt(_ d: Any?) -> CGPoint {
        let m = d as? [String: Any]
        return CGPoint(x: (m?["x"] as? NSNumber)?.doubleValue ?? 0.5, y: (m?["y"] as? NSNumber)?.doubleValue ?? 0.5)
    }
    private func num(_ d: Any?, _ def: Double) -> Double { (d as? NSNumber)?.doubleValue ?? def }
    private func screen(_ p: CGPoint, _ s: CGSize) -> CGPoint { CGPoint(x: p.x * s.width, y: p.y * s.height) }
    private func norm(_ p: CGPoint, _ s: CGSize) -> CGPoint { CGPoint(x: min(max(p.x / s.width, 0), 1), y: min(max(p.y / s.height, 0), 1)) }
    private func radialHandle(_ c: CGPoint, _ rx: Double, _ ry: Double, _ ang: Double, side: Int) -> CGPoint {
        let (x, y) = side == 0 ? (rx, 0.0) : (0.0, ry)
        return CGPoint(x: c.x + x * cos(ang) - y * sin(ang), y: c.y + x * sin(ang) + y * cos(ang))
    }

    private func draw(_ m: MacMask, _ s: CGSize, _ ctx: GraphicsContext) {
        let accent = GraphicsContext.Shading.color(MacTheme.accent)
        let long = max(s.width, s.height)
        switch m.kind {
        case "linear":
            let a = screen(pt(m.shape["start"]), s), b = screen(pt(m.shape["end"]), s)
            var l = Path(); l.move(to: a); l.addLine(to: b); ctx.stroke(l, with: accent, lineWidth: 2)
            for p in [a, b] { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(.white)) }
        case "radial":
            let c = screen(pt(m.shape["center"]), s)
            let rx = num(m.shape["rx"], 0.3) * long, ry = num(m.shape["ry"], 0.25) * long, ang = num(m.shape["angle"], 0) * .pi / 180
            let e = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
                .applying(CGAffineTransform(rotationAngle: ang).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
            ctx.stroke(e, with: accent, lineWidth: 2)
            for p in [c, radialHandle(c, rx, ry, ang, side: 0), radialHandle(c, rx, ry, ang, side: 1)] {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 7, y: p.y - 7, width: 14, height: 14)), with: .color(.white))
            }
        case "brush":
            if stroke.count > 1 {
                var path = Path(); path.move(to: screen(stroke[0], s)); for p in stroke.dropFirst() { path.addLine(to: screen(p, s)) }
                ctx.stroke(path, with: .color(dev.mk.erase ? .black.opacity(0.5) : MacTheme.accent.opacity(0.55)),
                           style: StrokeStyle(lineWidth: 2 * dev.mk.brushSize * long, lineCap: .round, lineJoin: .round))
            }
        default: break
        }
    }

    private func change(_ m: MacMask, _ v: DragGesture.Value, _ s: CGSize, _ long: Double) {
        let p = norm(v.location, s)
        switch m.kind {
        case "brush": stroke.append(p)
        case "linear":
            if drag == nil {
                let a = screen(pt(m.shape["start"]), s), b = screen(pt(m.shape["end"]), s)
                let da = hypot(a.x - v.startLocation.x, a.y - v.startLocation.y), db = hypot(b.x - v.startLocation.x, b.y - v.startLocation.y)
                drag = min(da, db) < 30 ? (da < db ? "start" : "end") : "move"
                origin = (pt(m.shape["start"]), pt(m.shape["end"]))
            }
            guard let d = drag, let o = origin else { return }
            let delta = CGPoint(x: (v.location.x - v.startLocation.x) / s.width, y: (v.location.y - v.startLocation.y) / s.height)
            var a = o.0, b = o.1
            if d == "start" { a = p } else if d == "end" { b = p } else { a.x += delta.x; a.y += delta.y; b.x += delta.x; b.y += delta.y }
            send(["kind": "linear", "start": ["x": a.x, "y": a.y], "end": ["x": b.x, "y": b.y]], final: false)
        case "radial":
            if drag == nil {
                let c = screen(pt(m.shape["center"]), s)
                let rx = num(m.shape["rx"], 0.3) * long, ry = num(m.shape["ry"], 0.25) * long, ang = num(m.shape["angle"], 0) * .pi / 180
                let h0 = radialHandle(c, rx, ry, ang, side: 0), h1 = radialHandle(c, rx, ry, ang, side: 1)
                let d0 = hypot(h0.x - v.startLocation.x, h0.y - v.startLocation.y), d1 = hypot(h1.x - v.startLocation.x, h1.y - v.startLocation.y)
                drag = min(d0, d1) < 30 ? (d0 < d1 ? "rx" : "ry") : "move"
            }
            guard let d = drag else { return }
            var shape = m.shape
            let c = pt(m.shape["center"]), ang = num(m.shape["angle"], 0) * .pi / 180
            if d == "move" { shape["center"] = ["x": p.x, "y": p.y] }
            else {
                let dx = (p.x - c.x) * s.width, dy = (p.y - c.y) * s.height
                let along = d == "rx" ? abs(dx * cos(ang) + dy * sin(ang)) : abs(-dx * sin(ang) + dy * cos(ang))
                shape[d] = max(along / long, 0.02)
            }
            shape["center"] = shape["center"] ?? ["x": c.x, "y": c.y]
            send(shape, final: false)
        default: break
        }
    }

    private func end(_ m: MacMask, _ v: DragGesture.Value, _ s: CGSize) {
        guard let id = lib.activeID else { return }
        if m.kind == "brush" {
            let pts = stroke; stroke = []
            Task { await dev.paintBrush(pts, id: id, engine: lib.engine) }
        } else if drag != nil {
            drag = nil
            Task { await dev.afterMaskChange(id, lib.engine) }
        }
    }

    private func send(_ shape: [String: Any], final: Bool) {
        guard let id = lib.activeID else { return }
        Task { await dev.updateShape(shape, id: id, engine: lib.engine, final: final) }
    }
}

/// Pick a word; the mask is whatever it names in the photo.
struct WordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (Int, String) -> Void
    private var matches: [(Int, String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = Array(TextMask.shared.phrases.enumerated())
        return (q.isEmpty ? all : all.filter { $0.element.lowercased().contains(q) }).map { ($0.offset, $0.element) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("Mask by word").font(.title3.weight(.semibold)); Spacer(); Button("Close") { dismiss() } }
            TextField("Search words (dog, car, wheel…)", text: $query).textFieldStyle(.roundedBorder)
            Text("Works best for things you can point at. Trees, mountains and water are not found reliably; use Sky or Background for those.")
                .font(.footnote).foregroundStyle(.secondary)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6)], spacing: 6) {
                    ForEach(matches, id: \.0) { m in
                        Button(m.1) { onPick(m.0, m.1); dismiss() }.buttonStyle(.bordered).lineLimit(1)
                    }
                }
                if matches.isEmpty { Text("No word like that yet.").foregroundStyle(.secondary).padding(.top, 16) }
            }
        }
        .padding(20).frame(width: 520, height: 420)
    }
}
