import SwiftUI

private let groups: [(name: String, sections: [String])] = [
    ("Light", ["light"]), ("Colour", ["color", "mixer", "grading", "bwMix", "calibration"]),
    ("Effects", ["effects", "vignette", "grain"]), ("Detail", ["detail"]), ("Optics", ["optics", "geometry"]),
]

enum EditMode: String, CaseIterable {
    case edit = "Edit", crop = "Crop", mask = "Mask", heal = "Heal", looks = "Looks", history = "History", info = "Info"
    var symbol: String {
        switch self {
        case .edit: "slider.horizontal.3"; case .crop: "crop.rotate"; case .mask: "circle.lefthalf.filled.inverse"
        case .heal: "bandage"; case .looks: "sparkles"; case .history: "clock.arrow.circlepath"; case .info: "info.circle"
        }
    }
}

struct EditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.horizontalSizeClass) private var hsize
    @State private var photoID: UInt64
    @State private var image: UIImage?
    @State private var histogram: [UInt32] = []
    @State private var controls: [Control] = []
    @State private var info = PhotoInfo(name: "", rating: 0, flag: "none", edited: false)
    @State private var group = "Light"
    @State private var edits = OrderedQueue()
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var showExport = false
    @State private var curveChannel = "master"
    @State private var curvePoints: [CGPoint] = []
    @State private var mode: EditMode = .edit
    @State private var healTool: HealTool = .spot
    @State private var spotMode = "heal"
    @State private var spotSize = 0.04
    @State private var pet = false
    @State private var objectPick = false
    @State private var objectExclude = false
    @State private var lassoStroke: [CGPoint] = []
    @State private var objectMask: Int?
    @State private var showMask = true
    @State private var activeMask: Int?
    @State private var copied = false
    @State private var wbMode = "asShot"
    @State private var showCurve = false
    @State private var colourTab = "Basic"
    @State private var colourBand = "red"
    @State private var picking = false
    @State private var pickMessage: String?
    @State private var brushSize = 0.03
    @State private var erase = false
    @State private var live = Throttle()
    @State private var compare = "off"
    @State private var hdrOn = false
    @State private var appleLevel = 0.0
    @State private var rendition = "HDR"
    @State private var beforeImage: UIImage?
    @State private var peek = false
    @State private var split: CGFloat = 0.5

    init(photoID: UInt64) { _photoID = State(initialValue: photoID) }

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height
            let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
            layout {
                VStack(spacing: 0) {
                    topBar
                    canvas
                    modeBar
                    if hsize != .compact { filmstrip }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(width: wide ? 360 : nil, height: wide ? nil : min(geo.size.height * (hsize == .compact ? 0.5 : 0.45), 420))
            }
        }
        .sheet(isPresented: $showExport) { ExportSheet(ids: [photoID]) }
        .onReceive(NotificationCenter.default.publisher(for: .masksChanged)) { n in activeMask = n.object as? Int }
        .onReceive(NotificationCenter.default.publisher(for: .curvePreset)) { n in
            guard let name = n.object as? String else { return }
            Task { _ = try? await model.engine.execute("curve.applyPreset", ["name": name]); curvePoints = await model.engine.curve(curveChannel); await render() }
        }
        .onChange(of: objectPick) { _, on in
            if on { objectMask = nil; ObjectPicker.shared.reset(); ObjectPicker.shared.undo = { undoObjectTap() }; ObjectPicker.shared.clear = { clearObjectTaps() } }
        }
        .task(id: photoID) { await open() }
    }

    // MARK: top bar, canvas, filmstrip

    private var topBar: some View {
        Group { if hsize == .compact { compactTopBar } else { regularTopBar } }
    }

    private var compactTopBar: some View {
        HStack(spacing: 2) {
            glass("chevron.left") { model.openPhoto = nil }
            glass("arrow.uturn.backward") { Task { await command("edit.undo") } }
            glass("arrow.uturn.forward") { Task { await command("edit.redo") } }
            VStack(spacing: 0) {
                Text(info.name).font(.footnote.weight(.semibold)).lineLimit(1)
                Text(info.edited ? "Edited" : "Original").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            Menu {
                Button { setCompare("off") } label: { Label("Compare off", systemImage: compare == "off" ? "checkmark" : "eye.slash") }
                Button { setCompare("before") } label: { Label("Before only", systemImage: compare == "before" ? "checkmark" : "photo") }
                Button { setCompare("split") } label: { Label("Split", systemImage: compare == "split" ? "checkmark" : "rectangle.split.2x1") }
            } label: {
                Image(systemName: "rectangle.split.2x1").font(.body.weight(.medium)).foregroundStyle(compare == "off" ? Color.primary : Theme.accentSoft)
                    .frame(width: 40, height: 44).contentShape(Circle())
            } primaryAction: { setCompare(compare == "off" ? "split" : "off") }
            .accessibilityIdentifier("compare.menu")
            Menu {
                Button { Task { await command("develop.copy"); copied = true } } label: { Label("Copy settings", systemImage: "doc.on.doc") }
                Button { Task { await command("develop.paste"); await reloadControls(); await render() } } label: { Label("Paste settings", systemImage: "doc.on.clipboard") }
                Divider()
                Button { Task { await command(info.flag == "pick" ? "photo.unflag" : "photo.pick"); await refreshInfo() } } label: { Label(info.flag == "pick" ? "Remove pick" : "Pick", systemImage: "flag") }
                Button { Task { await command(info.flag == "reject" ? "photo.unflag" : "photo.reject"); await refreshInfo() } } label: { Label(info.flag == "reject" ? "Remove reject" : "Reject", systemImage: "xmark.circle") }
                Menu("Rating") {
                    ForEach(0...5, id: \.self) { n in
                        Button(n == 0 ? "No rating" : String(repeating: "★", count: n)) { Task { await command("photo.rate", ["rating": n]); await refreshInfo() } }
                    }
                }
            } label: { Image(systemName: "ellipsis.circle").font(.body.weight(.medium)).frame(width: 40, height: 44).contentShape(Circle()) }
            glass("square.and.arrow.up", tint: Theme.accent) { showExport = true }
        }
        .padding(.horizontal, 6).frame(height: 56)
        .panelBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 8).padding(.top, 4)
    }

    private var regularTopBar: some View {
        HStack(spacing: 6) {
            glass("chevron.left") { model.openPhoto = nil }
            glass("arrow.uturn.backward") { Task { await command("edit.undo") } }
            glass("arrow.uturn.forward") { Task { await command("edit.redo") } }
            glass("doc.on.doc") { Task { await command("develop.copy"); copied = true } }
            glass("doc.on.clipboard", tint: copied ? Theme.accentSoft : nil) { Task { await command("develop.paste"); await reloadControls(); await render() } }
            VStack(spacing: 0) {
                Text(info.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(info.edited ? "Edited" : "Original").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            glass(info.flag == "pick" ? "flag.fill" : "flag", tint: info.flag == "pick" ? Theme.accent : nil) {
                Task { await command(info.flag == "pick" ? "photo.unflag" : "photo.pick"); await refreshInfo() }
            }
            glass(info.flag == "reject" ? "xmark.circle.fill" : "xmark.circle") {
                Task { await command(info.flag == "reject" ? "photo.unflag" : "photo.reject"); await refreshInfo() }
            }
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { n in
                    Button {
                        Task { await command("photo.rate", ["rating": info.rating == n ? 0 : n]); await refreshInfo() }
                    } label: {
                        Image(systemName: n <= info.rating ? "star.fill" : "star").font(.footnote)
                            .foregroundStyle(n <= info.rating ? Theme.accentSoft : .secondary).frame(width: 26, height: 44)
                    }
                }
            }
            Menu {
                Button { setCompare("off") } label: { Label("Off", systemImage: compare == "off" ? "checkmark" : "eye.slash") }
                Button { setCompare("before") } label: { Label("Before only", systemImage: compare == "before" ? "checkmark" : "photo") }
                Button { setCompare("split") } label: { Label("Split", systemImage: compare == "split" ? "checkmark" : "rectangle.split.2x1") }
                Text("Tap toggles the split slider. Touch and hold the photo to peek at the original.")
            } label: {
                Image(systemName: "rectangle.split.2x1").font(.body.weight(.medium)).foregroundStyle(compare == "off" ? Color.primary : Theme.accentSoft)
                    .frame(width: 44, height: 44).contentShape(Circle())
            } primaryAction: { setCompare(compare == "off" ? "split" : "off") }
            .accessibilityIdentifier("compare.menu")
            glass("square.and.arrow.up", tint: Theme.accent) { showExport = true }
        }
        .padding(.horizontal, 10).frame(height: 60)
        .panelBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(8)
    }

    private func glass(_ symbol: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.medium)).foregroundStyle(tint ?? .primary)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
    }

    private var canvas: some View {
        GeometryReader { geo in
            let rect = fitRect(image?.size ?? .zero, in: geo.size)
            ZStack {
                if let image {
                    ZStack {
                        Image(uiImage: (compare == "before" || peek) ? (beforeImage ?? image) : image).resizable().scaledToFit()
                        if compare == "split", !peek, let beforeImage, mode == .edit {
                            Image(uiImage: beforeImage).resizable().scaledToFit()
                                .mask(alignment: .leading) { Rectangle().frame(width: rect.minX + rect.width * split) }
                            Rectangle().fill(.white).frame(width: 2, height: rect.height).position(x: rect.minX + rect.width * split, y: geo.size.height / 2)
                            Circle().fill(.ultraThinMaterial).overlay(Image(systemName: "arrow.left.and.right").font(.caption.weight(.bold)))
                                .frame(width: 40, height: 40).position(x: rect.minX + rect.width * split, y: geo.size.height / 2)
                                .gesture(DragGesture().onChanged { split = min(max(($0.location.x - rect.minX) / max(rect.width, 1), 0.02), 0.98) })
                        }
                    }
                    .scaleEffect(scale).offset(offset)
                    .onLongPressGesture(minimumDuration: 0.3, maximumDistance: 20, perform: { if mode == .edit { Task { await loadBefore(); peek = true } } },
                                        onPressingChanged: { if !$0 { peek = false } })
                        .gesture(MagnifyGesture().onChanged { if mode == .edit { scale = min(max($0.magnification * baseScale, 1), 8) } }
                            .onEnded { _ in baseScale = scale; if scale == 1 { offset = .zero } })
                        .simultaneousGesture(DragGesture().onChanged { if mode == .edit, scale > 1 { offset = CGSize(width: baseOffset.width + $0.translation.width, height: baseOffset.height + $0.translation.height) } }
                            .onEnded { _ in baseOffset = offset })
                        .onTapGesture(count: 2) { if mode == .edit { withAnimation(.snappy) { scale = scale > 1 ? 1 : 3; baseScale = scale; offset = .zero; baseOffset = .zero } } }
                    if objectPick && mode == .mask {
                        Color.clear.contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { tapObject(at: $0.location, in: rect) })
                        objectMarkers(in: rect)
                    }
                    if objectPick && mode == .mask && ObjectPicker.shared.lasso {
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 4).onChanged { lassoStroke.append($0.location) }
                                .onEnded { _ in let s = lassoStroke; lassoStroke = []; finishLasso(s, in: rect) })
                        Canvas { ctx, _ in
                            guard let f = lassoStroke.first else { return }
                            var p = Path(); p.move(to: f); for q in lassoStroke.dropFirst() { p.addLine(to: q) }; p.closeSubpath()
                            ctx.stroke(p, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                            ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: [8, 6]))
                        }.allowsHitTesting(false)
                    }
                    if picking {
                        Color.clear.contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { pickColour(at: $0.location, in: rect) })
                            .overlay(alignment: .top) { Text(pickMessage ?? "Tap the colour you want to edit").font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 38).panelBackground(in: Capsule()).padding(.top, 10) }
                    }
                    if mode == .crop { CropOverlay(engine: model.engine, imageRect: rect) { live.run { await render(draft: true) } }.transition(.opacity) }
                    if mode == .heal { HealOverlay(engine: model.engine, imageRect: rect, tool: healTool, spotMode: spotMode, spotSize: spotSize, pet: pet) { live.run { await render(draft: true) } }.transition(.opacity) }
                    if mode == .mask { MaskOverlay(engine: model.engine, imageRect: rect, brushSize: brushSize, erase: erase, pencilOnly: UserDefaults.standard.bool(forKey: "pencilOnly"),
                        onUndo: { Task { await command("edit.undo") } }, onRedo: { Task { await command("edit.redo") } }, onPencilTap: { erase.toggle() }) { live.run { await render(draft: true) } }.transition(.opacity) }
                } else {
                    ProgressView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    /// Reads the colour under a tap from the rendered image and selects the nearest Mixer colour.
    private func pickColour(at p: CGPoint, in rect: CGRect) {
        guard let cg = image?.cgImage, rect.width > 0 else { return }
        let u = (p.x - rect.minX) / rect.width, v = (p.y - rect.minY) / rect.height
        guard (0...1).contains(u), (0...1).contains(v) else { return }
        let cx = Int(u * Double(cg.width - 1)), cy = Int(v * Double(cg.height - 1))
        var r = 0.0, g = 0.0, b = 0.0, n = 0.0
        if let data = cg.dataProvider?.data, let ptr = CFDataGetBytePtr(data) {
            let bpp = cg.bitsPerPixel / 8
            for dy in -3...3 { for dx in -3...3 {
                let x = min(max(cx + dx, 0), cg.width - 1), y = min(max(cy + dy, 0), cg.height - 1)
                let o = y * cg.bytesPerRow + x * bpp
                r += Double(ptr[o]); g += Double(ptr[o + 1]); b += Double(ptr[o + 2]); n += 1
            } }
        }
        guard n > 0 else { return }
        let ui = UIColor(red: r / n / 255, green: g / n / 255, blue: b / n / 255, alpha: 1)
        var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0, a: CGFloat = 0
        ui.getHue(&h, saturation: &s, brightness: &br, alpha: &a)
        if s < 0.08 { pickMessage = "That area is neutral, try a coloured spot"; return }
        let deg = Double(h) * 360
        let centres: [(String, Double)] = [("red", 0), ("orange", 30), ("yellow", 60), ("green", 120), ("aqua", 180), ("blue", 230), ("purple", 275), ("magenta", 320)]
        func dist(_ a: Double, _ b: Double) -> Double { let d = abs(a - b).truncatingRemainder(dividingBy: 360); return min(d, 360 - d) }
        colourBand = centres.min { dist($0.1, deg) < dist($1.1, deg) }?.0 ?? "red"
        colourTab = "Mixer"; picking = false; pickMessage = nil
    }

    /// Object mask: the first tap makes an on-device Object mask, further taps add to it or cut parts out.
    private func tapObject(at p: CGPoint, in rect: CGRect) {
        guard rect.width > 0 else { return }
        let x = (p.x - rect.minX) / rect.width, y = (p.y - rect.minY) / rect.height
        guard (0...1).contains(x), (0...1).contains(y) else { return }
        applyObject(points: [(x, y)], lasso: false)
    }

    /// Lasso: the user draws around something; a few points spread through the loop go to the segmenter, which follows the
    /// nearest real edges instead of the hand-drawn line.
    private func finishLasso(_ stroke: [CGPoint], in rect: CGRect) {
        guard rect.width > 0, stroke.count > 8 else { return }
        let poly = stroke.map { CGPoint(x: min(max(($0.x - rect.minX) / rect.width, 0), 1), y: min(max(($0.y - rect.minY) / rect.height, 0), 1)) }
        let xs = poly.map(\.x), ys = poly.map(\.y)
        guard let x0 = xs.min(), let x1 = xs.max(), let y0 = ys.min(), let y1 = ys.max(), x1 - x0 > 0.02, y1 - y0 > 0.02 else { return }
        func inside(_ p: CGPoint) -> Bool {
            var c = false, j = poly.count - 1
            for i in 0..<poly.count {
                if (poly[i].y > p.y) != (poly[j].y > p.y), p.x < (poly[j].x - poly[i].x) * (p.y - poly[i].y) / (poly[j].y - poly[i].y) + poly[i].x { c.toggle() }
                j = i
            }
            return c
        }
        var cand: [CGPoint] = []
        let n = 28
        for i in 0..<n { for k in 0..<n {
            let q = CGPoint(x: x0 + (x1 - x0) * (Double(i) + 0.5) / Double(n), y: y0 + (y1 - y0) * (Double(k) + 0.5) / Double(n))
            if inside(q) { cand.append(q) }
        } }
        guard !cand.isEmpty else { return }
        // Farthest-point sampling from the middle, so the points cover the whole shape (head, body, tail…).
        let mid = CGPoint(x: cand.map(\.x).reduce(0, +) / Double(cand.count), y: cand.map(\.y).reduce(0, +) / Double(cand.count))
        var chosen = [cand.min { hypot($0.x - mid.x, $0.y - mid.y) < hypot($1.x - mid.x, $1.y - mid.y) }!]
        while chosen.count < 6 {
            guard let next = cand.max(by: { a, b in
                chosen.map { hypot(a.x - $0.x, a.y - $0.y) }.min()! < chosen.map { hypot(b.x - $0.x, b.y - $0.y) }.min()!
            }), chosen.map({ hypot(next.x - $0.x, next.y - $0.y) }).min()! > 0.06 else { break }
            chosen.append(next)
        }
        applyObject(points: chosen.map { ($0.x, $0.y) }, lasso: true)
    }

    private func applyObject(points: [(Double, Double)], lasso: Bool) {
        let picker = ObjectPicker.shared
        guard !picker.busy else { return }
        picker.busy = true; picker.error = nil
        showMask = true
        picker.group += 1
        let group = picker.group
        Task {
            defer { picker.busy = false }
            do {
                var cmds = 0
                var rest = points[...]
                if objectMask == nil, !objectExclude, let r = try await model.engine.execute("mask.add", ["kind": "object", "points": points.map { [$0.0, $0.1] }]) as? [String: Any] {
                    objectMask = (r["activeMask"] as? NSNumber)?.intValue
                    rest = []; cmds = 1
                }
                if let id = objectMask {
                    for p in rest { _ = try await model.engine.execute("mask.objectPoint", ["x": p.0, "y": p.1, "exclude": objectExclude, "id": id]); cmds += 1 }
                }
                for (i, p) in points.enumerated() { picker.taps.append(.init(x: p.0, y: p.1, exclude: objectExclude, group: group, cmds: i == 0 ? cmds : 0, lasso: lasso)) }
            } catch {
                picker.error = lasso ? "Couldn't find an object in that loop. Draw closer around it." : "Couldn't pick an object there. Try the middle of it, or tap again."
            }
            NotificationCenter.default.post(name: .masksChanged, object: nil)
            await render(draft: true)
        }
    }

    private func undoObjectTap() {
        let picker = ObjectPicker.shared
        guard let g = picker.taps.last?.group else { return }
        let n = picker.taps.filter { $0.group == g }.reduce(0) { $0 + $1.cmds }
        Task {
            for _ in 0..<max(1, n) { await command("edit.undo") }
            picker.taps.removeAll { $0.group == g }
            if picker.taps.isEmpty { objectMask = nil }
            NotificationCenter.default.post(name: .masksChanged, object: nil)
            await render(draft: true)
        }
    }

    private func clearObjectTaps() {
        let picker = ObjectPicker.shared
        guard let id = objectMask else { picker.reset(); return }
        Task {
            _ = try? await model.engine.execute("mask.delete", ["id": id])
            objectMask = nil; picker.reset()
            NotificationCenter.default.post(name: .masksChanged, object: nil)
            await render(draft: true)
        }
    }

    /// Green + / red − where the user tapped, so it is clear what was added and what was cut away.
    private func objectMarkers(in rect: CGRect) -> some View {
        ZStack {
            ForEach(ObjectPicker.shared.taps.filter { !$0.lasso }) { t in
                Image(systemName: t.exclude ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 26)).symbolRenderingMode(.palette)
                    .foregroundStyle(.white, t.exclude ? Color.red : Color.green)
                    .shadow(radius: 2)
                    .position(x: rect.minX + t.x * rect.width, y: rect.minY + t.y * rect.height)
            }
        }.allowsHitTesting(false)
    }

    private func fitRect(_ s: CGSize, in box: CGSize) -> CGRect {
        guard s.width > 0, s.height > 0 else { return .zero }
        let k = min(box.width / s.width, box.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    private var modeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) { modeItems }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: hsize == .compact ? .infinity : 560)
            .panelBackground(in: Capsule())
            .padding(.bottom, 6).padding(.horizontal, hsize == .compact ? 8 : 12)
    }

    private var modeItems: some View {
        HStack(spacing: 0) {
            ForEach(EditMode.allCases, id: \.self) { m in
                Button { setMode(m) } label: {
                    VStack(spacing: 4) {
                        Image(systemName: m.symbol).font(.system(size: 19, weight: .medium)).frame(height: 24)
                        Text(m.rawValue).font(.system(size: 11, weight: .semibold)).tracking(0.2)
                    }
                    .frame(minWidth: 52, maxWidth: .infinity).frame(height: 54)
                    .foregroundStyle(mode == m ? Color.white : Color.white.opacity(0.55))
                    .overlay(alignment: .bottom) { Capsule().fill(Theme.accent).frame(width: mode == m ? 16 : 0, height: 3).offset(y: -2) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6).frame(minWidth: hsize == .compact ? 0 : 560)
    }

    private func setMode(_ m: EditMode) {
        withAnimation(.snappy(duration: 0.3)) { mode = m }
        if m != .mask { objectPick = false; objectMask = nil }
        scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero
        Task { await render() }
    }
    @State private var baseScale: CGFloat = 1
    @State private var baseOffset: CGSize = .zero

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(model.photoIDs, id: \.self) { id in
                        Button { photoID = id } label: {
                            Color(white: 0.12).frame(width: 64, height: 64)
                                .overlay { if let t = model.thumbs[id] { Image(uiImage: t).resizable().scaledToFill() } }
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(id == photoID ? Theme.accent : .clear, lineWidth: 2))
                        }
                        .id(id).task { await model.thumbnail(id) }
                    }
                }
                .padding(.horizontal, 10)
            }
            .frame(height: 72)
            .onAppear { proxy.scrollTo(photoID, anchor: .center) }
        }
    }

    // MARK: inspector

    private var visible: [Control] {
        let secs = groups.first { $0.name == group }?.sections ?? []
        let list = controls.filter { secs.contains($0.section) }
        guard group == "Light" else { return list }
        // HDR editing keeps two renditions: the main sliders shape the HDR picture, the SDR ones what SDR displays show
        if hdrOn && rendition == "SDR" { return list.filter { $0.id.hasPrefix("hdr.sdr") } }
        // white balance lives at the top of the Light tab
        return controls.filter { $0.id == "wb.temp" || $0.id == "wb.tint" } + list.filter { !$0.id.hasPrefix("hdr.sdr") && ($0.id != "hdr.maxEv" || hdrOn) }
    }

    private var inspector: some View {
        VStack(spacing: 8) {
            HStack {
                Text(mode.rawValue).font(.title3.weight(.semibold))
                Spacer()
                if mode == .edit { Button("Reset") { Task { await command("develop.reset"); await reloadControls(); await render() } }
                    .buttonStyle(.bordered).tint(Theme.accent) }
            }
            .padding(.horizontal, 20).padding(.top, 12)
            ScrollView {
                if mode == .crop {
                    CropPanel(engine: model.engine, photoID: photoID) { live.run { await render(draft: true) } }.padding(.horizontal, 16).transition(.opacity.combined(with: .move(edge: .trailing)))
                } else if mode == .heal {
                    HealPanel(engine: model.engine, photoID: photoID, tool: $healTool, spotMode: $spotMode, spotSize: $spotSize, pet: $pet) { live.run { await render(draft: true) } }
                        .padding(.horizontal, 16).transition(.opacity.combined(with: .move(edge: .trailing)))
                } else if mode == .looks {
                    LooksPanel(engine: model.engine, photoID: photoID) { Task { await reloadControls(); await render() } }
                        .padding(.horizontal, 16).transition(.opacity.combined(with: .move(edge: .trailing)))
                } else if mode == .info {
                    InfoPanel(engine: model.engine, photoID: photoID).padding(.horizontal, 16).transition(.opacity.combined(with: .move(edge: .trailing)))
                } else if mode == .history {
                    HistoryPanel(engine: model.engine, photoID: photoID) { Task { await reloadControls(); await render() } }
                        .padding(.horizontal, 16).transition(.opacity.combined(with: .move(edge: .trailing)))
                } else if mode == .mask {
                    MaskPanel(engine: model.engine, photoID: photoID, brushSize: $brushSize, erase: $erase, objectPick: $objectPick, objectExclude: $objectExclude, showMask: $showMask) { live.run { await render(draft: true) } }.padding(.horizontal, 16).transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                VStack(spacing: 8) {
                    if !histogram.isEmpty { HistogramView(height: hsize == .compact ? 44 : 70, bins: histogram) }
                    QuickEditBar(engine: model.engine) { Task { await reloadControls(); await render() } }.id(photoID)
                    if group == "Light" && hdrOn {
                        Picker("Rendition", selection: $rendition) { Text("HDR").tag("HDR"); Text("SDR").tag("SDR") }.pickerStyle(.segmented)
                            .accessibilityIdentifier("rendition.picker")
                        Text(rendition == "HDR" ? "Shapes the picture on HDR displays and in HDR exports." : "Shapes what ordinary SDR displays show.")
                            .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if group == "Light" && !(hdrOn && rendition == "SDR") {
                        Button { withAnimation(.snappy) { showCurve.toggle() } } label: {
                            HStack { Text("Tone curve").font(.subheadline.weight(.medium)); Spacer()
                                Text(curvePoints.count <= 2 && curvePoints.allSatisfy { abs($0.x - $0.y) < 0.001 } ? "Linear" : "Custom").accessibilityIdentifier("curve.state").font(.subheadline).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).rotationEffect(.degrees(showCurve ? 90 : 0)) }
                                .padding(.horizontal, 14).frame(height: 48).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                    if group == "Light" && !(hdrOn && rendition == "SDR") {
                        HStack {
                            Text("White balance").font(.subheadline.weight(.semibold))
                            Spacer()
                            Menu {
                                ForEach([("asShot", "As shot"), ("auto", "Auto"), ("daylight", "Daylight"), ("cloudy", "Cloudy"), ("shade", "Shade"),
                                         ("tungsten", "Tungsten"), ("fluorescent", "Fluorescent"), ("flash", "Flash")], id: \.0) { m in
                                    Button { Task { await command("develop.wb", ["mode": m.0]); await reloadControls(); await render() } } label: {
                                        if wbMode == m.0 { Label(m.1, systemImage: "checkmark") } else { Text(m.1) }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) { Text(wbMode == "asShot" ? "As shot" : wbMode.capitalized); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                                    .font(.subheadline.weight(.medium)).padding(.horizontal, 12).frame(height: 36).fieldBackground(in: Capsule())
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    if group == "Light" && showCurve && !(hdrOn && rendition == "SDR") {
                        CurveEditor(channel: $curveChannel, points: $curvePoints, histogram: histogram, controls: controls,
                                    setControl: { id, v, commit in set(id, v, commit: commit) },
                                    onChange: { pts in curvePoints = pts; setCurve(pts, commit: false) },
                                    onEnd: { setCurve(curvePoints, commit: true); edits.add(.step) { _ = try? await model.engine.execute("develop.endInteraction") } },
                                    onBegin: { edits.add(.step) { _ = try? await model.engine.execute("develop.beginInteraction", ["label": "Tone Curve"]) } })
                            .padding(.vertical, 4)
                            .onChange(of: curveChannel) { _, c in Task { curvePoints = await model.engine.curve(c) } }
                    }
                    if group == "Detail" {
                        DetailPanel(engine: model.engine, photoID: photoID, controls: controls, set: { id, v, c in set(id, v, commit: c) }, onChange: { Task { await reloadControls(); await render() } }, appleLevel: $appleLevel, onApple: { AppleDenoise.setLevel(appleLevel, for: photoID); Task { await render() } })
                    } else if group == "Colour" {
                        ColourPanel(controls: controls, set: { id, v, commit in set(id, v, commit: commit) }, tab: $colourTab, band: $colourBand, picking: $picking)
                    } else { ForEach(visible) { c in
                        ColorSlider(control: c, onChange: { v in set(c.id, v, commit: false) }, onEnd: { v in set(c.id, v, commit: true) },
                                    reset: { set(c.id, c.def, commit: true) })
                    } }
                }.padding(.horizontal, 16)
                }
            }
            .accessibilityIdentifier("inspector")
            .contentMargins(.top, 8, for: .scrollContent)
            .contentMargins(.bottom, 36, for: .scrollContent)
            .scrollIndicators(.hidden)
            if mode == .edit { Picker("Group", selection: $group) { ForEach(groups, id: \.name) { Text($0.name).tag($0.name) } }
                  .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12) }
        }
        .panelBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .animation(.snappy(duration: 0.3), value: mode)
        .padding(8)
    }

    // MARK: engine glue

    private func open() async {
        scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero; beforeImage = nil; peek = false
        appleLevel = AppleDenoise.level(photoID)
        if compare != "off" { await loadBefore() }
        try? await model.engine.execute("library.select", ["ids": [photoID], "active": photoID])
        async let c = model.engine.controls()
        async let i = model.engine.info()
        async let p = model.engine.curve(curveChannel)
        controls = await c
        let dev = await model.engine.developState()
        wbMode = ((dev["wb"] as? [String: Any])?["mode"] as? String) ?? "asShot"
        hdrOn = ((dev["hdr"] as? [String: Any])?["enabled"] as? Bool) ?? false
        info = await i ?? info
        curvePoints = await p
        // Debug aids for screenshots: RAWLIGHT_MODE=crop|mask, RAWLIGHT_MASK=1 adds a radial mask.
        let env = ProcessInfo.processInfo.environment
        if let m = env["RAWLIGHT_MODE"], let em = EditMode(rawValue: m.capitalized) { mode = em }
        if env["RAWLIGHT_MASK"] != nil { _ = try? await model.engine.execute("mask.add", ["kind": "radial", "center": [0.5, 0.5], "rx": 0.3, "ry": 0.25, "angle": 0, "feather": 50]) }
        if env["RAWLIGHT_EXPORT"] != nil {
            let url = FileManager.default.temporaryDirectory.appending(path: "dbg-export.jpg")
            let t0 = Date()
            do { let r = try await model.engine.execute("app.export", ["path": url.path, "ids": [photoID], "format": "jpeg", "quality": 90, "longEdge": 3000, "colorSpace": "srgb"]); NSLog("[RawLight] EXPORT ok %.1fs %@", Date().timeIntervalSince(t0), "\(r)") }
            catch { NSLog("[RawLight] EXPORT error %@", error.localizedDescription) }
        }
        if let g = env["RAWLIGHT_GROUP"] { group = g }
        if env["RAWLIGHT_HDR"] != nil { _ = try? await model.engine.execute("develop.hdr", ["enabled": true]); hdrOn = true; await reloadControls(); if env["RAWLIGHT_HDR"] == "sdr" { rendition = "SDR" } }
        if let c = env["RAWLIGHT_COMPARE"] { setCompare(c) }
        if let t = env["RAWLIGHT_COLOURTAB"] { colourTab = t }
        if env["RAWLIGHT_CURVE"] != nil { showCurve = true; _ = try? await model.engine.execute("develop.curve", ["channel": "master", "points": [[0, 0], [0.3, 0.2], [1, 1]]]); curvePoints = await model.engine.curve("master") }
        if let pt = env["RAWLIGHT_OBJECT"] {
            let v = pt.split(separator: ",").compactMap { Double($0) }
            if v.count == 2 {
                do { let r = try await model.engine.execute("mask.add", ["kind": "object", "points": [[v[0], v[1]]]]); NSLog("[RawLight] OBJECT ok %@", "\(r)"); _ = try? await model.engine.execute("mask.adjust", ["values": ["exposure": -3.0]]); try? await Task.sleep(for: .seconds(4)) }
                catch { NSLog("[RawLight] OBJECT error %@", error.localizedDescription) }
            }
        }
        if let k = env["RAWLIGHT_AIMASK"] {
            do { let r = try await model.engine.execute("mask.add", ["kind": k]); NSLog("[RawLight] AIMASK %@ ok %@", k, "\(r)"); _ = try? await model.engine.execute("mask.adjust", ["values": ["exposure": -3.0]]); try? await Task.sleep(for: .seconds(4)) }
            catch { NSLog("[RawLight] AIMASK %@ error %@", k, error.localizedDescription) }
        }
        if env["RAWLIGHT_SPOT"] != nil { _ = try? await model.engine.execute("spot.add", ["mode": "heal", "points": [[0.5, 0.45]], "size": 0.06]) }
        await render()
    }

    private func reloadControls() async { controls = await model.engine.controls(); let d = await model.engine.developState(); wbMode = ((d["wb"] as? [String: Any])?["mode"] as? String) ?? "asShot"; hdrOn = ((d["hdr"] as? [String: Any])?["enabled"] as? Bool) ?? false; if !hdrOn { rendition = "HDR" }; curvePoints = await model.engine.curve(curveChannel); await refreshInfo() }
    private func refreshInfo() async { if let i = await model.engine.info() { info = i } }
    private func command(_ id: String, _ p: [String: Any] = [:]) async {
        _ = try? await model.engine.execute(id, p)
        if id.hasPrefix("edit.") { await reloadControls(); await render() }
    }

    private func set(_ id: String, _ value: Double, commit: Bool) {
        if let i = controls.firstIndex(where: { $0.id == id }) { controls[i].value = value }
        edits.add(commit ? .step : .live) {
            _ = try? await model.engine.execute("develop.set", ["control": id, "value": value])
            await render(draft: !commit)
        }
    }

    private func setCurve(_ pts: [CGPoint], commit: Bool) {
        let ch = curveChannel
        edits.add(commit ? .step : .live) {
            if pts.isEmpty { _ = try? await model.engine.execute("curve.reset", ["channel": ch]) }
            else { _ = try? await model.engine.execute("develop.curve", ["channel": ch, "points": pts.map { [$0.x, $0.y] }]) }
            await render(draft: !commit)
        }
    }

    /// Fast draft while dragging; full quality when the finger lifts.
    private func setCompare(_ c: String) {
        compare = c
        if c != "off" { Task { await loadBefore() } }
    }

    private func loadBefore() async {
        if beforeImage == nil, let r = await model.engine.render(photoID, maxEdge: 1600, kind: .before) { beforeImage = r.image }
    }

    private func render(draft: Bool = false) async {
        let id = photoID
        if let r = await model.engine.render(id, maxEdge: draft ? 900 : 1600, kind: (mode == .crop || mode == .mask || mode == .heal) ? .uncropped : (draft ? .draft : .full),
                                            maskOverlay: mode == .mask && showMask ? (activeMask ?? 0) : nil), id == photoID {
            image = AppleDenoise.apply(r.image, level: appleLevel); histogram = r.histogram
            if !draft { info.edited = true }
        }
    }
}
