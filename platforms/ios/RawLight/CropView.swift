import SwiftUI

private enum Handle: String, CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    func point(in r: CGRect) -> CGPoint {
        switch self {
        case .topLeft: CGPoint(x: r.minX, y: r.minY)
        case .top: CGPoint(x: r.midX, y: r.minY)
        case .topRight: CGPoint(x: r.maxX, y: r.minY)
        case .right: CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
        case .left: CGPoint(x: r.minX, y: r.midY)
        }
    }
}

/// Crop rectangle over the uncropped image: dimmed outside, thirds grid, 8 handles, drag inside to move.
/// "Level" tool: draw a line along something that should be horizontal or vertical and the photo turns to match.
@Observable final class LevelTool {
    static let shared = LevelTool()
    var active = false
}
extension Notification.Name { static let cropAngleChanged = Notification.Name("rawlight.cropAngleChanged") }

struct CropOverlay: View {
    let engine: Engine
    let imageRect: CGRect
    let onChange: () -> Void
    @State private var rect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var active: String?
    @State private var dragStart: CGRect?
    @State private var throttle = Throttle()
    @State private var line: (CGPoint, CGPoint)?
    private let level = LevelTool.shared

    init(engine: Engine, imageRect: CGRect, onChange: @escaping () -> Void) {
        self.engine = engine; self.imageRect = imageRect; self.onChange = onChange
    }

    private var screen: CGRect {
        CGRect(x: imageRect.minX + rect.minX * imageRect.width, y: imageRect.minY + rect.minY * imageRect.height,
               width: rect.width * imageRect.width, height: rect.height * imageRect.height)
    }
    private func norm(_ p: CGPoint) -> [Double] {
        [min(max((p.x - imageRect.minX) / imageRect.width, 0), 1), min(max((p.y - imageRect.minY) / imageRect.height, 0), 1)]
    }

    var body: some View {
        ZStack {
            Path { p in p.addRect(CGRect(x: 0, y: 0, width: 4000, height: 4000)); p.addRect(screen) }
                .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            Canvas { ctx, _ in
                let r = screen
                ctx.stroke(Path(r), with: .color(.white), lineWidth: 1.5)
                for i in 1...2 {
                    let f = CGFloat(i) / 3
                    var g = Path()
                    g.move(to: CGPoint(x: r.minX + r.width * f, y: r.minY)); g.addLine(to: CGPoint(x: r.minX + r.width * f, y: r.maxY))
                    g.move(to: CGPoint(x: r.minX, y: r.minY + r.height * f)); g.addLine(to: CGPoint(x: r.maxX, y: r.minY + r.height * f))
                    ctx.stroke(g, with: .color(.white.opacity(0.35)), lineWidth: 0.8)
                }
                for h in Handle.allCases {
                    let c = h.point(in: r)
                    let corner = [.topLeft, .topRight, .bottomLeft, .bottomRight].contains(h)
                    let size = CGSize(width: corner ? 16 : 22, height: corner ? 16 : 22)
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - size.width / 2, y: c.y - size.height / 2, width: size.width, height: size.height)),
                             with: .color(active == h.rawValue ? Theme.accent : .white))
                }
            }
            .allowsHitTesting(false)
            if level.active { levelLayer } else { dragLayer }
        }
        .task { rect = Engine.cropRect(await engine.developState()) }
    }

    /// Drag a line; on release the photo is turned so that line becomes level (or plumb, whichever is nearer).
    private var levelLayer: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            Canvas { ctx, _ in
                guard let l = line else { return }
                var p = Path(); p.move(to: l.0); p.addLine(to: l.1)
                ctx.stroke(p, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                ctx.stroke(p, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                for pt in [l.0, l.1] { ctx.fill(Path(ellipseIn: CGRect(x: pt.x - 7, y: pt.y - 7, width: 14, height: 14)), with: .color(.white)) }
            }.allowsHitTesting(false)
        }
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { v in line = (v.startLocation, v.location) }
            .onEnded { v in
                let l = (v.startLocation, v.location)
                line = nil
                let dx = l.1.x - l.0.x, dy = l.1.y - l.0.y
                guard hypot(dx, dy) > 40 else { return }
                var turn = -atan2(dy, dx) * 180 / .pi          // a line descending to the right needs a negative angle
                turn = turn.truncatingRemainder(dividingBy: 90)  // level or plumb, whichever is nearer
                if turn > 45 { turn -= 90 } else if turn < -45 { turn += 90 }
                level.active = false
                Task {
                    let now = Engine.cropAngle(await engine.developState())
                    let target = min(45, max(-45, now + turn))
                    _ = try? await engine.execute("crop.straighten", ["angle": (target * 100).rounded() / 100])
                    rect = Engine.cropRect(await engine.developState())
                    NotificationCenter.default.post(name: .cropAngleChanged, object: nil)
                    onChange()
                }
            })
    }

    private var dragLayer: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if dragStart == nil {
                            dragStart = rect
                            let r = screen
                            let near = Handle.allCases.map { ($0, hypot($0.point(in: r).x - v.startLocation.x, $0.point(in: r).y - v.startLocation.y)) }
                                .min { $0.1 < $1.1 }
                            if let near, near.1 < 44 { active = near.0.rawValue } else if r.contains(v.startLocation) { active = "move" } else { active = nil }
                        }
                        guard let active, let start = dragStart else { return }
                        let from = norm(v.startLocation), to = norm(v.location)
                        let s = [start.minX, start.minY, start.maxX, start.maxY]
                        throttle.run {
                            _ = try? await engine.execute("crop.drag", ["handle": active, "from": from, "to": to, "start": s])
                            rect = Engine.cropRect(await engine.developState())
                            onChange()
                        }
                    }
                    .onEnded { _ in active = nil; dragStart = nil })
        }
    }
}

/// Inspector content for the crop tool.
struct CropPanel: View {
    let engine: Engine
    let photoID: UInt64
    let onChange: () -> Void
    @State private var angle = 0.0
    @State private var aspect = "original"
    @State private var throttle = Throttle()

    init(engine: Engine, photoID: UInt64, onChange: @escaping () -> Void) {
        self.engine = engine; self.photoID = photoID; self.onChange = onChange
    }

    private let aspects: [(String, String)] = [("original", "Original"), ("free", "Free"), ("1x1", "1:1"), ("4x5", "4:5"), ("5x7", "5:7"),
                                               ("2x3", "2:3"), ("4x3", "4:3"), ("16x9", "16:9"), ("16x10", "16:10")]

    var body: some View {
        VStack(spacing: 14) {
            do {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                    ForEach(aspects, id: \.0) { a in
                        Button { aspect = a.0; run("crop.aspect", ["aspect": a.0]) } label: {
                            Text(a.1).font(.subheadline.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity).frame(height: 40)
                                .fieldBackground(aspect == a.0, in: Capsule())
                                .foregroundStyle(aspect == a.0 ? .white : .primary)
                        }
                    }
                }
            }
            VStack(spacing: 4) {
                HStack {
                    Text("Straighten").font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f°", angle)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Button { angle = 0; run("crop.straighten", ["angle": 0]) } label: {
                        Image(systemName: "arrow.counterclockwise").font(.caption.weight(.semibold)).frame(width: 28, height: 28).fieldBackground(in: Circle())
                    }.buttonStyle(.plain).opacity(angle == 0 ? 0.3 : 1)
                }
                Slider(value: Binding(get: { angle }, set: { v in angle = v; throttle.run { _ = try? await engine.execute("crop.straighten", ["angle": v]); onChange() } }),
                       in: -45...45).tint(Theme.accent)
            }
            .padding(12).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            HStack(spacing: 10) {
                tool("rotate.left", "Left") { run("photo.rotateLeft") }
                tool("rotate.right", "Right") { run("photo.rotateRight") }
                tool("arrow.left.and.right.righttriangle.left.righttriangle.right", "Flip H") { run("photo.flipHorizontal") }
                tool("arrow.up.and.down.righttriangle.up.righttriangle.down", "Flip V") { run("photo.flipVertical") }
                tool("aspectratio", "Swap") { run("crop.rotateAspect") }
            }
            Button { LevelTool.shared.active.toggle() } label: {
                HStack(spacing: 8) { Image(systemName: "level"); Text(LevelTool.shared.active ? "Draw a line along the horizon…" : "Level: draw a line") }
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).frame(height: 44)
                    .fieldBackground(LevelTool.shared.active, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("crop.level")
            HStack(spacing: 10) {
                pill("Auto level") { run("crop.autoStraighten"); Task { try? await Task.sleep(for: .milliseconds(300)); await load() } }
                Menu {
                    ForEach([("auto", "Auto"), ("level", "Level"), ("vertical", "Vertical"), ("full", "Full"), ("off", "Off")], id: \.0) { m in
                        Button(m.1) { run("geometry.upright", ["mode": m.0]) }
                    }
                } label: { pillLabel("Upright") }
                pill("Reset crop") { run("crop.reset"); angle = 0; aspect = "original" }
            }
        }
        .task(id: photoID) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .cropAngleChanged)) { _ in Task { await load() } }
        .onDisappear { LevelTool.shared.active = false }
    }

    private func load() async {
        let d = await engine.developState()
        angle = Engine.cropAngle(d)
        if let a = (d["crop"] as? [String: Any])?["aspect"] as? String { aspect = a }
    }

    private func run(_ id: String, _ p: [String: Any] = [:]) {
        Task { _ = try? await engine.execute(id, p); onChange() }
    }
    private func tool(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) { Image(systemName: symbol).font(.title3); Text(title).font(.caption2) }
                .frame(maxWidth: .infinity).frame(height: 56).fieldBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }
    private func pill(_ title: String, _ action: @escaping () -> Void) -> some View { Button(action: action) { pillLabel(title) }.buttonStyle(.plain) }
    private func pillLabel(_ title: String) -> some View {
        Text(title).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).frame(height: 44).fieldBackground(in: Capsule())
    }
}
