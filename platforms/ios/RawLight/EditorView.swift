import SwiftUI

private let groups: [(name: String, sections: [String])] = [
    ("Light", ["light"]), ("Colour", ["color", "mixer", "grading", "bwMix", "calibration"]),
    ("Effects", ["effects", "vignette", "grain"]), ("Detail", ["detail"]), ("Optics", ["optics"]),
]

enum EditMode: String, CaseIterable {
    case edit = "Edit", crop = "Crop", mask = "Mask"
    var symbol: String { switch self { case .edit: "slider.horizontal.3"; case .crop: "crop.rotate"; case .mask: "circle.lefthalf.filled.inverse" } }
}

struct EditorView: View {
    @Environment(AppModel.self) private var model
    @State private var photoID: UInt64
    @State private var image: UIImage?
    @State private var histogram: [UInt32] = []
    @State private var controls: [Control] = []
    @State private var info = PhotoInfo(name: "", rating: 0, flag: "none", edited: false)
    @State private var group = "Light"
    @State private var renderTask: Task<Void, Never>?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var showExport = false
    @State private var curveChannel = "master"
    @State private var curvePoints: [CGPoint] = []
    @State private var mode: EditMode = .edit
    @State private var brushSize = 0.03
    @State private var erase = false
    @State private var live = Throttle()

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
                    filmstrip
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                inspector.frame(width: wide ? 360 : nil, height: wide ? nil : min(geo.size.height * 0.45, 420))
            }
        }
        .sheet(isPresented: $showExport) { ExportSheet(photoID: photoID) }
        .task(id: photoID) { await open() }
    }

    // MARK: top bar, canvas, filmstrip

    private var topBar: some View {
        HStack(spacing: 6) {
            glass("chevron.left") { model.openPhoto = nil }
            glass("arrow.uturn.backward") { Task { await command("edit.undo") } }
            glass("arrow.uturn.forward") { Task { await command("edit.redo") } }
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
            glass("square.and.arrow.up", tint: Theme.accent) { showExport = true }
        }
        .padding(.horizontal, 10).frame(height: 60)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                    Image(uiImage: image).resizable().scaledToFit()
                        .scaleEffect(scale).offset(offset)
                        .gesture(MagnifyGesture().onChanged { if mode == .edit { scale = min(max($0.magnification * baseScale, 1), 8) } }
                            .onEnded { _ in baseScale = scale; if scale == 1 { offset = .zero } })
                        .simultaneousGesture(DragGesture().onChanged { if mode == .edit, scale > 1 { offset = CGSize(width: baseOffset.width + $0.translation.width, height: baseOffset.height + $0.translation.height) } }
                            .onEnded { _ in baseOffset = offset })
                        .onTapGesture(count: 2) { if mode == .edit { withAnimation(.snappy) { scale = scale > 1 ? 1 : 3; baseScale = scale; offset = .zero; baseOffset = .zero } } }
                    if mode == .crop { CropOverlay(engine: model.engine, imageRect: rect) { live.run { await render(draft: true) } } }
                    if mode == .mask { MaskOverlay(engine: model.engine, imageRect: rect, brushSize: brushSize, erase: erase) { live.run { await render(draft: true) } } }
                } else {
                    ProgressView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
    }

    private func fitRect(_ s: CGSize, in box: CGSize) -> CGRect {
        guard s.width > 0, s.height > 0 else { return .zero }
        let k = min(box.width / s.width, box.height / s.height)
        let w = s.width * k, h = s.height * k
        return CGRect(x: (box.width - w) / 2, y: (box.height - h) / 2, width: w, height: h)
    }

    private var modeBar: some View {
        HStack(spacing: 4) {
            ForEach(EditMode.allCases, id: \.self) { m in
                Button { setMode(m) } label: {
                    Label(m.rawValue, systemImage: m.symbol).font(.subheadline.weight(.medium)).padding(.horizontal, 16).frame(height: 44)
                        .background(mode == m ? Color.white.opacity(0.16) : .clear, in: Capsule())
                        .foregroundStyle(mode == m ? Theme.accentSoft : .primary)
                }
            }
        }
        .padding(4).background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 6)
    }

    private func setMode(_ m: EditMode) {
        mode = m
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
        return controls.filter { secs.contains($0.section) }
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
                    CropPanel(engine: model.engine, photoID: photoID) { live.run { await render(draft: true) } }.padding(.horizontal, 16)
                } else if mode == .mask {
                    MaskPanel(engine: model.engine, photoID: photoID, brushSize: $brushSize, erase: $erase) { live.run { await render(draft: true) } }.padding(.horizontal, 16)
                } else {
                VStack(spacing: 8) {
                    if !histogram.isEmpty { HistogramView(bins: histogram) }
                    if group == "Light" {
                        CurveEditor(channel: $curveChannel, points: $curvePoints, histogram: histogram,
                                    onChange: { pts in setCurve(pts, commit: false) }, onEnd: { setCurve(curvePoints, commit: true) })
                            .padding(.vertical, 4)
                            .onChange(of: curveChannel) { _, c in Task { curvePoints = await model.engine.curve(c) } }
                    }
                    ForEach(visible) { c in
                        ColorSlider(control: c, onChange: { v in set(c.id, v, commit: false) }, onEnd: { set(c.id, c.value, commit: true) },
                                    reset: { set(c.id, c.def, commit: true) })
                    }
                }.padding(.horizontal, 16)
                }
            }
            if mode == .edit { Picker("Group", selection: $group) { ForEach(groups, id: \.name) { Text($0.name).tag($0.name) } }
                  .pickerStyle(.segmented).padding(.horizontal, 16).padding(.bottom, 12) }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(8)
    }

    // MARK: engine glue

    private func open() async {
        scale = 1; baseScale = 1; offset = .zero; baseOffset = .zero
        try? await model.engine.execute("library.select", ["ids": [photoID], "active": photoID])
        async let c = model.engine.controls()
        async let i = model.engine.info()
        async let p = model.engine.curve(curveChannel)
        controls = await c
        info = await i ?? info
        curvePoints = await p
        // Debug aids for screenshots: RAWLIGHT_MODE=crop|mask, RAWLIGHT_MASK=1 adds a radial mask.
        let env = ProcessInfo.processInfo.environment
        if let m = env["RAWLIGHT_MODE"], let em = EditMode(rawValue: m.capitalized) { mode = em }
        if env["RAWLIGHT_MASK"] != nil { _ = try? await model.engine.execute("mask.add", ["kind": "radial", "center": [0.5, 0.5], "rx": 0.3, "ry": 0.25, "angle": 0, "feather": 0.5]) }
        await render()
    }

    private func reloadControls() async { controls = await model.engine.controls(); curvePoints = await model.engine.curve(curveChannel); await refreshInfo() }
    private func refreshInfo() async { if let i = await model.engine.info() { info = i } }
    private func command(_ id: String, _ p: [String: Any] = [:]) async {
        _ = try? await model.engine.execute(id, p)
        if id.hasPrefix("edit.") { await reloadControls(); await render() }
    }

    private func set(_ id: String, _ value: Double, commit: Bool) {
        if let i = controls.firstIndex(where: { $0.id == id }) { controls[i].value = value }
        renderTask?.cancel()
        renderTask = Task {
            _ = try? await model.engine.execute("develop.set", ["control": id, "value": value])
            if !Task.isCancelled { await render(draft: !commit) }
        }
    }

    private func setCurve(_ pts: [CGPoint], commit: Bool) {
        let ch = curveChannel
        renderTask?.cancel()
        renderTask = Task {
            _ = try? await model.engine.execute("develop.curve", ["channel": ch, "points": pts.map { [$0.x, $0.y] }])
            if !Task.isCancelled { await render(draft: !commit) }
        }
    }

    /// Fast draft while dragging; full quality when the finger lifts.
    private func render(draft: Bool = false) async {
        let id = photoID
        if let r = await model.engine.render(id, maxEdge: draft ? 900 : 1600, kind: mode == .crop ? .uncropped : (draft ? .draft : .full)), id == photoID {
            image = r.image; histogram = r.histogram
            if !draft { info.edited = true }
        }
    }
}
