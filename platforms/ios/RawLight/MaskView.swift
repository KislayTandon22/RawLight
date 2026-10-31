import SwiftUI

/// A mask as described by `develop.get`.
struct MaskItem: Identifiable, Equatable {
    var id: Int
    var name: String
    var visible: Bool
    var invert: Bool
    var kind: String
    var shape: [String: Any]
    var adjust: [String: Double]
    static func == (a: MaskItem, b: MaskItem) -> Bool { a.id == b.id && a.name == b.name && a.visible == b.visible && a.invert == b.invert && a.adjust == b.adjust }
}

extension Engine {
    func masks() async -> (items: [MaskItem], active: Int?) {
        let d = await developState()
        let arr = d["masks"] as? [[String: Any]] ?? []
        let items: [MaskItem] = arr.compactMap { m in
            guard let id = (m["id"] as? NSNumber)?.intValue else { return nil }
            let shape = ((m["components"] as? [[String: Any]])?.first?["shape"] as? [String: Any]) ?? [:]
            var adj: [String: Double] = [:]
            for (k, v) in (m["adjust"] as? [String: Any]) ?? [:] { if let n = v as? NSNumber { adj[k] = n.doubleValue } }
            return MaskItem(id: id, name: m["name"] as? String ?? "Mask", visible: m["visible"] as? Bool ?? true,
                            invert: m["invert"] as? Bool ?? false, kind: shape["kind"] as? String ?? "brush", shape: shape, adjust: adj)
        }
        let st = try? await execute("library.state") as? [String: Any]
        return (items, (st?["activeMask"] as? NSNumber)?.intValue)
    }
}

private func pt(_ d: Any?) -> CGPoint {
    let m = d as? [String: Any]
    return CGPoint(x: (m?["x"] as? NSNumber)?.doubleValue ?? 0.5, y: (m?["y"] as? NSNumber)?.doubleValue ?? 0.5)
}
private func num(_ d: Any?, _ def: Double) -> Double { (d as? NSNumber)?.doubleValue ?? def }

/// Guides and gestures for the selected mask: linear line, radial ellipse, brush strokes.
struct MaskOverlay: View {
    let engine: Engine
    let imageRect: CGRect
    let brushSize: Double
    let erase: Bool
    var pencilOnly = false
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onPencilTap: () -> Void = {}
    let onChange: () -> Void
    @State private var mask: MaskItem?
    @State private var samples: [StrokeSample] = []
    @State private var drag: String?
    @State private var throttle = Throttle()
    @State private var reload = 0

    init(engine: Engine, imageRect: CGRect, brushSize: Double, erase: Bool, pencilOnly: Bool = false, onUndo: @escaping () -> Void = {},
         onRedo: @escaping () -> Void = {}, onPencilTap: @escaping () -> Void = {}, onChange: @escaping () -> Void) {
        self.engine = engine; self.imageRect = imageRect; self.brushSize = brushSize; self.erase = erase; self.pencilOnly = pencilOnly
        self.onUndo = onUndo; self.onRedo = onRedo; self.onPencilTap = onPencilTap; self.onChange = onChange
    }

    private var long: Double { max(imageRect.width, imageRect.height) }
    private func toScreen(_ p: CGPoint) -> CGPoint { CGPoint(x: imageRect.minX + p.x * imageRect.width, y: imageRect.minY + p.y * imageRect.height) }
    private func toNorm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - imageRect.minX) / imageRect.width, 0), 1), y: min(max((p.y - imageRect.minY) / imageRect.height, 0), 1))
    }

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                guard let m = mask else { return }
                let accent = GraphicsContext.Shading.color(Theme.accent)
                switch m.kind {
                case "linear":
                    let a = toScreen(pt(m.shape["start"])), b = toScreen(pt(m.shape["end"]))
                    var l = Path(); l.move(to: a); l.addLine(to: b)
                    ctx.stroke(l, with: accent, lineWidth: 2)
                    for p in [a, b] { ctx.fill(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)), with: .color(.white)) }
                case "radial":
                    let c = toScreen(pt(m.shape["center"]))
                    let rx = num(m.shape["rx"], 0.3) * long, ry = num(m.shape["ry"], 0.25) * long
                    let ang = num(m.shape["angle"], 0) * .pi / 180
                    var e = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
                    e = e.applying(CGAffineTransform(rotationAngle: ang).concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
                    ctx.stroke(e, with: accent, lineWidth: 2)
                    for p in [c, radialHandle(c, rx, ry, ang, side: 0), radialHandle(c, rx, ry, ang, side: 1)] {
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22)), with: .color(.white))
                    }
                default:
                    break
                }
                if m.kind == "brush", samples.count > 1 {
                    let base = 2 * brushSize * max(imageRect.width, imageRect.height)   // size is a radius
                    for i in 1..<samples.count {
                        var seg = Path(); seg.move(to: samples[i - 1].point); seg.addLine(to: samples[i].point)
                        ctx.stroke(seg, with: .color(erase ? .black.opacity(0.5) : Theme.accent.opacity(0.55)),
                                   style: StrokeStyle(lineWidth: base * sizeFactor(samples[i].pressure), lineCap: .round, lineJoin: .round))
                    }
                }
            }
            .allowsHitTesting(false)
            if let m = mask, m.kind == "brush" {
                PencilCanvas(pencilOnly: pencilOnly,
                             onBegan: { samples = [$0] },
                             onMoved: { samples.append(contentsOf: $0) },
                             onEnded: { finishBrush(m) },
                             onCancelled: { samples = [] },
                             onUndo: onUndo, onRedo: onRedo, onPencilTap: onPencilTap)
            } else if let m = mask {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in handle(m, v) }
                        .onEnded { v in finish(m, v) })
            }
        }
        .task(id: reload) { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .masksChanged)) { _ in Task { await refresh() } }
    }

    private func radialHandle(_ c: CGPoint, _ rx: Double, _ ry: Double, _ ang: Double, side: Int) -> CGPoint {
        let (x, y) = side == 0 ? (rx, 0.0) : (0.0, ry)
        return CGPoint(x: c.x + x * cos(ang) - y * sin(ang), y: c.y + x * sin(ang) + y * cos(ang))
    }

    private func refresh() async {
        let r = await engine.masks()
        mask = r.items.first { $0.id == r.active }
    }

    private func handle(_ m: MaskItem, _ v: DragGesture.Value) {
        let p = toNorm(v.location)
        switch m.kind {
        case "linear":
            if drag == nil {
                let a = toScreen(pt(m.shape["start"])), b = toScreen(pt(m.shape["end"]))
                let da = hypot(a.x - v.startLocation.x, a.y - v.startLocation.y), db = hypot(b.x - v.startLocation.x, b.y - v.startLocation.y)
                drag = min(da, db) < 50 ? (da < db ? "start" : "end") : "move"
                dragOrigin = (pt(m.shape["start"]), pt(m.shape["end"]))
            }
            guard let d = drag, let o = dragOrigin else { return }
            let delta = CGPoint(x: (v.location.x - v.startLocation.x) / imageRect.width, y: (v.location.y - v.startLocation.y) / imageRect.height)
            var s = o.0, e = o.1
            if d == "start" { s = p } else if d == "end" { e = p } else { s.x += delta.x; s.y += delta.y; e.x += delta.x; e.y += delta.y }
            update(m, ["kind": "linear", "start": ["x": s.x, "y": s.y], "end": ["x": e.x, "y": e.y]])
        case "radial":
            if drag == nil {
                let c = toScreen(pt(m.shape["center"]))
                let rx = num(m.shape["rx"], 0.3) * long, ry = num(m.shape["ry"], 0.25) * long, ang = num(m.shape["angle"], 0) * .pi / 180
                let h0 = radialHandle(c, rx, ry, ang, side: 0), h1 = radialHandle(c, rx, ry, ang, side: 1)
                let d0 = hypot(h0.x - v.startLocation.x, h0.y - v.startLocation.y), d1 = hypot(h1.x - v.startLocation.x, h1.y - v.startLocation.y)
                drag = min(d0, d1) < 50 ? (d0 < d1 ? "rx" : "ry") : "move"
            }
            guard let d = drag else { return }
            var shape = m.shape
            let c = pt(m.shape["center"]), ang = num(m.shape["angle"], 0) * .pi / 180
            if d == "move" { shape["center"] = ["x": p.x, "y": p.y] }
            else {
                // distance from the centre along the ellipse axis the handle controls
                let dx = (p.x - c.x) * imageRect.width, dy = (p.y - c.y) * imageRect.height
                let along = d == "rx" ? abs(dx * cos(ang) + dy * sin(ang)) : abs(-dx * sin(ang) + dy * cos(ang))
                shape[d] = max(along / long, 0.02)
            }
            shape["center"] = shape["center"] ?? ["x": c.x, "y": c.y]
            update(m, shape)
        default:
            break
        }
    }

    @State private var dragOrigin: (CGPoint, CGPoint)?

    private func finish(_ m: MaskItem, _ v: DragGesture.Value) {
        drag = nil
        Task { await refresh(); onChange() }
    }

    /// Pressure maps to brush size: light pressure is a fine line, firm pressure a broad one.
    private func sizeFactor(_ pressure: CGFloat) -> Double { 0.35 + 1.3 * Double(pressure) }

    /// Sends the stroke in short pieces, each at the size its pressure asks for.
    private func finishBrush(_ m: MaskItem) {
        let s = samples
        samples = []
        guard s.count > 1 else { return }
        let id = m.id, base = brushSize, er = erase
        var pieces: [(pts: [[Double]], size: Double)] = []
        var i = 0
        while i < s.count - 1 {
            let chunk = Array(s[i..<min(i + 9, s.count)])   // 8 segments per piece, sharing an end point
            let avg = chunk.map { Double($0.pressure) }.reduce(0, +) / Double(chunk.count)
            pieces.append((chunk.map { p in let n = toNorm(p.point); return [Double(n.x), Double(n.y)] }, base * (0.35 + 1.3 * avg)))
            i += 8
        }
        Task {
            // one undo step for the whole stroke
            _ = try? await engine.execute("develop.beginInteraction", ["label": "Brush"])
            for piece in pieces { _ = try? await engine.execute("mask.brushStroke", ["id": id, "points": piece.pts, "size": piece.size, "erase": er]) }
            _ = try? await engine.execute("develop.endInteraction")
            onChange()
        }
    }

    private func update(_ m: MaskItem, _ shape: [String: Any]) {
        var local = m; local.shape = shape; mask = local
        let id = m.id
        throttle.run { _ = try? await engine.execute("mask.update", ["id": id, "component": 0, "shape": shape]); onChange() }
    }
}

extension Notification.Name { static let masksChanged = Notification.Name("rawlight.masksChanged") }

/// Inspector content for masks: list, add menu, per-mask adjustments, brush controls.
/// State of the "Object" tool: every tap, whether it is still working, and why the last one failed.
@Observable final class ObjectPicker {
    static let shared = ObjectPicker()
    struct Tap: Identifiable { let id = UUID(); let x: Double; let y: Double; let exclude: Bool; var group = 0; var cmds = 1; var lasso = false }
    var lasso = false
    var group = 0
    var taps: [Tap] = []
    var busy = false
    var status = "Finding edges…"
    var error: String?
    var undo: (() -> Void)?
    var clear: (() -> Void)?
    func reset() { taps = []; busy = false; error = nil; group = 0 }
}

struct MaskPanel: View {
    let engine: Engine
    let photoID: UInt64
    @Binding var brushSize: Double
    @Binding var erase: Bool
    @Binding var objectPick: Bool
    @Binding var objectExclude: Bool
    @Binding var showMask: Bool
    @AppStorage("pencilOnly") private var pencilOnly = false
    let onChange: () -> Void
    @State private var masks: [MaskItem] = []
    @State private var active: Int?
    @State private var message: String?
    @State private var throttle = Throttle()

    init(engine: Engine, photoID: UInt64, brushSize: Binding<Double>, erase: Binding<Bool>, objectPick: Binding<Bool>, objectExclude: Binding<Bool>, showMask: Binding<Bool>, onChange: @escaping () -> Void) {
        self.engine = engine; self.photoID = photoID; _brushSize = brushSize; _erase = erase; _objectPick = objectPick; _objectExclude = objectExclude; _showMask = showMask; self.onChange = onChange
    }

    private var current: MaskItem? { masks.first { $0.id == active } }

    private let adjustments: [(key: String, label: String, min: Double, max: Double, step: Double, dec: Int)] = [
        ("exposure", "Exposure", -5, 5, 0.01, 2), ("contrast", "Contrast", -100, 100, 1, 0), ("highlights", "Highlights", -100, 100, 1, 0),
        ("shadows", "Shadows", -100, 100, 1, 0), ("whites", "Whites", -100, 100, 1, 0), ("blacks", "Blacks", -100, 100, 1, 0),
        ("temp", "Temp", -100, 100, 1, 0), ("tint", "Tint", -100, 100, 1, 0), ("saturation", "Saturation", -100, 100, 1, 0),
        ("texture", "Texture", -100, 100, 1, 0), ("clarity", "Clarity", -100, 100, 1, 0), ("dehaze", "Dehaze", -100, 100, 1, 0),
        ("sharpness", "Sharpness", -100, 100, 1, 0), ("noise", "Noise", -100, 100, 1, 0),
    ]

    var body: some View {
        VStack(spacing: 10) {
            typeTabs
            HStack {
                Spacer()
                if current != nil {
                    Menu {
                        ForEach([("add", "Add"), ("subtract", "Subtract"), ("intersect", "Intersect")], id: \.0) { op in
                            Menu(op.1) {
                                Button("Linear gradient") { addComponent(op.0, ["kind": "linear", "start": [0.5, 0.3], "end": [0.5, 0.7]]) }
                                Button("Radial gradient") { addComponent(op.0, ["kind": "radial", "center": [0.5, 0.5], "rx": 0.2, "ry": 0.2, "angle": 0, "feather": 50]) }
                                Button("Brush") { addComponent(op.0, ["kind": "brush"]) }
                                Button("Luminance range") { addComponent(op.0, ["kind": "luminanceRange"]) }
                                Button("Colour range") { addComponent(op.0, ["kind": "colorRange"]) }
                            }
                        }
                    } label: { Text("Combine").font(.subheadline.weight(.medium)).lineLimit(1).fixedSize().padding(.horizontal, 14).frame(height: 44).fieldBackground(in: Capsule()) }
                }
                if current != nil {
                    Button { showMask.toggle(); onChange() } label: {
                        Image(systemName: showMask ? "eye.fill" : "eye.slash").frame(width: 44, height: 44)
                    }.fieldBackground(showMask, in: Circle()).buttonStyle(.plain).accessibilityLabel("Show mask overlay")
                }
                if !masks.isEmpty { Button("Delete all", role: .destructive) { run("mask.deleteAll") }.font(.footnote).lineLimit(1).fixedSize() }
            }
            if objectPick { objectCard }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.accentSoft).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(masks) { m in
                HStack {
                    Button { select(m.id) } label: {
                        HStack { Image(systemName: icon(m.kind)); Text(m.name).lineLimit(1); Spacer() }.frame(height: 44)
                    }.buttonStyle(.plain)
                    Button { run("mask.visible", ["id": m.id, "visible": !m.visible]) } label: { Image(systemName: m.visible ? "eye" : "eye.slash").frame(width: 44, height: 44) }
                }
                .padding(.horizontal, 12)
                .fieldBackground(m.id == active, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let m = current {
                HStack(spacing: 8) {
                    action("circle.lefthalf.filled", "Invert") { run("mask.invert", ["id": m.id]) }
                    action("plus.square.on.square", "Duplicate") { run("mask.duplicate", ["id": m.id]) }
                    action("arrow.up", "Up") { run("mask.move", ["id": m.id, "delta": -1]) }
                    action("arrow.down", "Down") { run("mask.move", ["id": m.id, "delta": 1]) }
                    action("trash", "Delete") { run("mask.delete", ["id": m.id]) }
                }
                if m.kind == "brush" {
                    VStack(spacing: 4) {
                        HStack { Text("Brush size").font(.subheadline); Spacer(); Text(String(format: "%.0f%%", brushSize * 100)).foregroundStyle(.secondary) }
                        Slider(value: $brushSize, in: 0.005...0.15).tint(Theme.accent)
                        Toggle("Erase", isOn: $erase).tint(Theme.accent)
                        Toggle("Pencil only", isOn: $pencilOnly).tint(Theme.accent)
                        Text("Press harder for a bigger brush. Double-tap the Pencil to switch erase. Two-finger tap undoes, three-finger tap redoes.")
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(12).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                ForEach(adjustments, id: \.key) { a in
                    let c = Control(id: a.key, label: a.label, section: "mask", min: a.min, max: a.max, def: 0, value: m.adjust[a.key] ?? 0,
                                    step: a.step, decimals: a.dec, track: a.key == "temp" ? .temp : a.key == "tint" ? .tint : .centered)
                    ColorSlider(control: c, onChange: { v in set(a.key, v) }, onEnd: { _ in }, reset: { set(a.key, 0) })
                }
            }
        }
        .task(id: photoID) { await reload() }
    }

    private var objectCard: some View {
        let picker = ObjectPicker.shared
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: picker.lasso ? "lasso" : "hand.tap").foregroundStyle(Theme.accent)
                Text(picker.lasso ? (picker.taps.isEmpty ? "Draw a loop around what you want to edit" : "Draw again to add or cut away parts")
                                  : (picker.taps.isEmpty ? "Tap the object you want to edit" : "Tap more to add or cut away parts")).font(.subheadline.weight(.semibold))
                Spacer()
                if picker.busy { ProgressView().controlSize(.small) }
            }
            HStack(spacing: 8) {
                ForEach([(false, "plus.circle.fill", "Include"), (true, "minus.circle.fill", "Exclude")], id: \.0) { o in
                    Button { objectExclude = o.0 } label: {
                        Label(o.2, systemImage: o.1).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).frame(height: 42)
                            .foregroundStyle(objectExclude == o.0 ? .white : .primary)
                            .background(objectExclude == o.0 ? (o.0 ? Color.red.opacity(0.75) : Theme.accent) : Color.clear, in: Capsule())
                            .fieldBackground(objectExclude != o.0, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 8) {
                Button { picker.undo?() } label: { Label(picker.lasso ? "Undo" : "Undo tap", systemImage: "arrow.uturn.backward").font(.footnote.weight(.medium)).frame(maxWidth: .infinity).frame(height: 38).fieldBackground(in: Capsule()) }
                    .buttonStyle(.plain).disabled(picker.taps.isEmpty).opacity(picker.taps.isEmpty ? 0.4 : 1)
                Button { picker.clear?() } label: { Label("Start over", systemImage: "xmark").font(.footnote.weight(.medium)).frame(maxWidth: .infinity).frame(height: 38).fieldBackground(in: Capsule()) }
                    .buttonStyle(.plain).disabled(picker.taps.isEmpty).opacity(picker.taps.isEmpty ? 0.4 : 1)
                Button { objectPick = false; message = nil; picker.reset() } label: {
                    Text("Done").font(.footnote.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 38).background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                }.buttonStyle(.plain)
            }
            if let e = picker.error { Text(e).font(.footnote).foregroundStyle(Theme.accentSoft) }
        }
        .padding(12).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// One-tap mask types, AI first. Replaces the "Add mask" menu so nothing is hidden.
    private var typeTabs: some View {
        let types: [(symbol: String, title: String, full: String, run: () -> Void)] = [
            ("person.crop.square", "Subject", "Subject", { add(["kind": "subject"]) }),
            ("cloud.sun", "Sky", "Sky", { add(["kind": "sky"]) }),
            ("rectangle.dashed", "Background", "Background", { add(["kind": "background"]) }),
            ("lasso", "Lasso", "Lasso", { ObjectPicker.shared.reset(); ObjectPicker.shared.lasso = true; objectPick = true; objectExclude = false; message = nil; showMask = true; onChange() }),
            ("hand.tap", "Object", "Object", { ObjectPicker.shared.reset(); ObjectPicker.shared.lasso = false; objectPick = true; objectExclude = false; message = nil; showMask = true; onChange() }),
            ("square.split.1x2", "Linear", "Linear gradient", { add(["kind": "linear", "start": [0.5, 0.3], "end": [0.5, 0.7]]) }),
            ("circle.dashed", "Radial", "Radial gradient", { add(["kind": "radial", "center": [0.5, 0.5], "rx": 0.3, "ry": 0.25, "angle": 0, "feather": 50]) }),
            ("paintbrush", "Brush", "Brush", { add(["kind": "brush"]) }),
            ("circle.lefthalf.filled", "Luminance", "Luminance range", { add(["kind": "luminanceRange"]) }),
            ("eyedropper", "Colour", "Colour range", { add(["kind": "colorRange"]) }),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                ForEach(types, id: \.full) { t in
                    Button(action: t.run) {
                        VStack(spacing: 5) {
                            Image(systemName: t.symbol).font(.system(size: 20, weight: .medium)).frame(height: 24)
                            Text(t.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .foregroundStyle(.white)
                        .fieldBackground(objectPick && t.title == (ObjectPicker.shared.lasso ? "Lasso" : "Object"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.full)
                }
        }
    }

    private func icon(_ kind: String) -> String {
        switch kind { case "linear": "square.split.1x2"; case "radial": "circle.dashed"; case "brush": "paintbrush"; default: "wand.and.stars" }
    }
    private func action(_ symbol: String, _ title: String, _ f: @escaping () -> Void) -> some View {
        Button(action: f) {
            VStack(spacing: 3) { Image(systemName: symbol); Text(title).font(.caption2) }.frame(maxWidth: .infinity).frame(height: 52)
                .fieldBackground(in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }.buttonStyle(.plain)
    }

    private func reload() async {
        let r = await engine.masks()
        masks = r.items; active = r.active
        NotificationCenter.default.post(name: .masksChanged, object: nil)
    }
    private func addComponent(_ op: String, _ shape: [String: Any]) {
        guard let id = active else { return }
        var p = shape; p["id"] = id; p["op"] = op
        Task {
            do { _ = try await engine.execute("mask.addComponent", p); message = nil } catch { message = error.localizedDescription }
            await reload(); onChange()
        }
    }
    private func select(_ id: Int) { showMask = true; Task { _ = try? await engine.execute("mask.select", ["id": id]); await reload() } }
    private func add(_ p: [String: Any]) {
        let picker = ObjectPicker.shared
        guard !picker.busy else { return }
        let kind = p["kind"] as? String ?? "mask"
        picker.status = ["subject", "sky", "background", "object"].contains(kind) ? "Finding the \(kind)…" : "Adding mask…"
        picker.busy = true; showMask = true; onChange()
        Task {
            defer { picker.busy = false }
            var failed = false
            do { _ = try await engine.execute("mask.add", p); message = nil; showMask = true } catch { message = error.localizedDescription; failed = true }
            await reload(); onChange()
            // AI masks are found in the background; refresh until the region shows up
            if !failed, ["subject", "sky", "background", "object"].contains(p["kind"] as? String ?? "") {
                message = "Finding the \(p["kind"] as? String ?? "") on this device…"
                for _ in 0..<28 { try? await Task.sleep(for: .milliseconds(250)); onChange() }
                message = nil
            }
        }
    }
    private func run(_ id: String, _ p: [String: Any] = [:]) { Task { _ = try? await engine.execute(id, p); await reload(); onChange() } }
    private func set(_ key: String, _ v: Double) {
        guard let id = active else { return }
        if showMask { showMask = false }   // judge the edit on the true colours, not under the red overlay
        if let i = masks.firstIndex(where: { $0.id == id }) { masks[i].adjust[key] = v }
        throttle.run { _ = try? await engine.execute("mask.adjust", ["id": id, "values": [key: v]]); onChange() }
    }
}
