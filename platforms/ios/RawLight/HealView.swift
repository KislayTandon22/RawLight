import SwiftUI

struct SpotItem: Identifiable {
    var id: Int
    var mode: String
    var point: CGPoint
    var size: Double
    var feather: Double
    var opacity: Double
    var source: CGPoint
}

struct RedEyeItem: Identifiable {
    var id: Int
    var center: CGPoint
    var rx: Double
    var pupil: Double
    var darken: Double
    var pet: Bool
}

extension Engine {
    func healState() async -> (spots: [SpotItem], eyes: [RedEyeItem], active: Int?) {
        let d = await developState()
        func p(_ v: Any?) -> CGPoint { let m = v as? [String: Any]; return CGPoint(x: (m?["x"] as? NSNumber)?.doubleValue ?? 0, y: (m?["y"] as? NSNumber)?.doubleValue ?? 0) }
        func n(_ v: Any?, _ def: Double) -> Double { (v as? NSNumber)?.doubleValue ?? def }
        let spots = ((d["spots"] as? [[String: Any]]) ?? []).enumerated().map { i, s in
            SpotItem(id: i, mode: s["mode"] as? String ?? "heal", point: p((s["points"] as? [Any])?.first), size: n(s["size"], 0.04),
                     feather: n(s["feather"], 50), opacity: n(s["opacity"], 100), source: p(s["source_offset"]))
        }
        let eyes = ((d["red_eye"] as? [[String: Any]]) ?? []).enumerated().map { i, e in
            RedEyeItem(id: i, center: p(e["center"]), rx: n(e["rx"], 0.03), pupil: n(e["pupil_size"], 50), darken: n(e["darken"], 50), pet: e["pet"] as? Bool ?? false)
        }
        let st = try? await execute("library.state") as? [String: Any]
        return (spots, eyes, (st?["activeSpot"] as? NSNumber)?.intValue)
    }
}

enum HealTool: String, CaseIterable { case spot = "Spot", redEye = "Red-eye" }

/// Tap the photo to place a heal spot or a red-eye correction; drag the selected spot to move it.
struct HealOverlay: View {
    let engine: Engine
    let imageRect: CGRect
    let tool: HealTool
    let spotMode: String
    let spotSize: Double
    let pet: Bool
    let onChange: () -> Void
    @State private var spots: [SpotItem] = []
    @State private var eyes: [RedEyeItem] = []
    @State private var active: Int?
    @State private var dragging: Int?
    @State private var throttle = Throttle()
    @State private var sent: CGPoint?

    private func toScreen(_ p: CGPoint) -> CGPoint { CGPoint(x: imageRect.minX + p.x * imageRect.width, y: imageRect.minY + p.y * imageRect.height) }
    private func toNorm(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max((p.x - imageRect.minX) / imageRect.width, 0), 1), y: min(max((p.y - imageRect.minY) / imageRect.height, 0), 1))
    }
    private var long: Double { max(imageRect.width, imageRect.height) }

    var body: some View {
        ZStack {
            Canvas { ctx, _ in
                for s in spots {
                    let c = toScreen(s.point), r = max(s.size * long, 8)
                    let sel = s.id == active
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(sel ? Theme.accent : .white), lineWidth: sel ? 2.5 : 1.5)
                    if sel {
                        let sp = toScreen(CGPoint(x: s.point.x + s.source.x, y: s.point.y + s.source.y))
                        ctx.stroke(Path(ellipseIn: CGRect(x: sp.x - r, y: sp.y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        var l = Path(); l.move(to: c); l.addLine(to: sp)
                        ctx.stroke(l, with: .color(.white.opacity(0.5)), lineWidth: 1)
                    }
                }
                for e in eyes {
                    let c = toScreen(e.center), r = max(e.rx * long, 10)
                    ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(.red), lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard tool == .spot else { return }
                        if dragging == nil {
                            let hit = spots.first { hypot(toScreen($0.point).x - v.startLocation.x, toScreen($0.point).y - v.startLocation.y) < max($0.size * long, 22) }
                            dragging = hit?.id ?? -1
                            if let hit { active = hit.id; sent = hit.point; Task { _ = try? await engine.execute("spot.select", ["index": hit.id]); NotificationCenter.default.post(name: .healEdited, object: nil) } }
                        }
                        if let d = dragging, d >= 0 {
                            let p = toNorm(v.location)
                            if let i = spots.firstIndex(where: { $0.id == d }) { spots[i].point = p }
                            // `move` is a delta from where the spot is now: send the step since the last one sent
                            throttle.run {
                                guard let from = sent else { return }
                                sent = p
                                _ = try? await engine.execute("spot.update", ["index": d, "move": [p.x - from.x, p.y - from.y]])
                                onChange()
                            }
                        }
                    }
                    .onEnded { v in
                        defer { dragging = nil }
                        guard imageRect.contains(v.location) else { return }
                        let moved = hypot(v.location.x - v.startLocation.x, v.location.y - v.startLocation.y) > 6
                        let p = toNorm(v.startLocation)
                        if tool == .redEye {
                            Task {
                                _ = try? await engine.execute("redeye.add", ["center": [p.x, p.y], "rx": 0.03, "ry": 0.03, "pet": pet])
                                await refresh(); NotificationCenter.default.post(name: .healEdited, object: nil); onChange()
                            }
                        } else if dragging == -1, !moved {
                            Task {
                                _ = try? await engine.execute("spot.add", ["mode": spotMode, "points": [[p.x, p.y]], "size": spotSize])
                                await refresh(); NotificationCenter.default.post(name: .healEdited, object: nil); onChange()
                            }
                        } else { Task { await refresh(); onChange() } }
                    })
        }
        .task { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .healChanged)) { _ in Task { await refresh() } }
    }

    private func refresh() async { let s = await engine.healState(); spots = s.spots; eyes = s.eyes; active = s.active }
}

extension Notification.Name {
    static let healChanged = Notification.Name("rawlight.healChanged")   // the panel changed something: the overlay refreshes
    static let healEdited = Notification.Name("rawlight.healEdited")     // the overlay changed something: the panel refreshes
}

struct HealPanel: View {
    let engine: Engine
    let photoID: UInt64
    @Binding var tool: HealTool
    @Binding var spotMode: String
    @Binding var spotSize: Double
    @Binding var pet: Bool
    let onChange: () -> Void
    @State private var spots: [SpotItem] = []
    @State private var eyes: [RedEyeItem] = []
    @State private var active: Int?
    @State private var message: String?
    @State private var throttle = Throttle()

    private var current: SpotItem? { spots.first { $0.id == active } }

    var body: some View {
        VStack(spacing: 10) {
            Picker("Tool", selection: $tool) { ForEach(HealTool.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
            if tool == .spot {
                Text("Tap the photo to place a spot. Drag a spot to move where it is applied.").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([("heal", "Heal"), ("clone", "Clone"), ("remove", "Remove"), ("fill", "Fill")], id: \.0) { m in
                            Button { spotMode = m.0; if active != nil { update(["mode": m.0]) } } label: {
                                Text(m.1).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 38)
                                    .fieldBackground(spotMode == m.0, in: Capsule()).foregroundStyle(spotMode == m.0 ? .white : .primary)
                            }
                        }
                    }
                }
                slider("New spot size", spotSize, 0.01...0.2, "%.0f%%", 100) { spotSize = $0 }
                HStack(spacing: 8) {
                    pill("Find dust", "sparkles") { await auto("spot.findDust") }
                    pill("Blemishes", "face.smiling") { await auto("spot.findBlemishes") }
                }
                if let s = current {
                    VStack(spacing: 8) {
                        Text("Selected spot").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        slider("Size", s.size, 0.005...0.25, "%.0f%%", 100) { update(["size": $0]) }
                        slider("Feather", s.feather, 0...100, "%.0f", 1) { update(["feather": $0]) }
                        slider("Opacity", s.opacity, 0...100, "%.0f", 1) { update(["opacity": $0]) }
                        HStack(spacing: 8) {
                            pill("New source", "arrow.triangle.2.circlepath") { await run("spot.refreshSource") }
                            pill("Delete", "trash") { await run("spot.delete") }
                        }
                    }.padding(12).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                Text("\(spots.count) spot\(spots.count == 1 ? "" : "s")").font(.footnote).foregroundStyle(.secondary)
            } else {
                Text("Tap an eye to correct red-eye. Use Pet for glowing pet eyes.").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                Toggle("Pet eye", isOn: $pet).tint(Theme.accent)
                ForEach(eyes) { e in
                    VStack(spacing: 8) {
                        HStack { Text("Eye \(e.id + 1)").font(.subheadline.weight(.semibold)); Spacer()
                            Button { Task { await run("redeye.delete", ["index": e.id]) } } label: { Image(systemName: "trash").foregroundStyle(.secondary).frame(width: 44, height: 44) } }
                        eyeSlider("Pupil size", e.pupil, e.id) { v in setEye(e.id, pupil: v) }
                        eyeSlider("Darken", e.darken, e.id) { v in setEye(e.id, darken: v) }
                    }.padding(12).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.accentSoft).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .task(id: photoID) { await refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .healEdited)) { _ in Task { let s = await engine.healState(); spots = s.spots; eyes = s.eyes; active = s.active } }
    }

    private func slider(_ label: String, _ value: Double, _ range: ClosedRange<Double>, _ fmt: String, _ scale: Double, _ set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 2) {
            HStack { Text(label).font(.subheadline); Spacer(); Text(String(format: fmt, value * scale)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: Binding(get: { value }, set: { set($0) }), in: range).tint(Theme.accent)
        }
    }
    private func pill(_ title: String, _ symbol: String, _ f: @escaping () async -> Void) -> some View {
        Button { Task { await f() } } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).frame(height: 44).fieldBackground(in: Capsule())
        }.buttonStyle(.plain)
    }

    private func refresh() async {
        let s = await engine.healState(); spots = s.spots; eyes = s.eyes; active = s.active
        NotificationCenter.default.post(name: .healChanged, object: nil)
    }
    private func run(_ id: String, _ p: [String: Any] = [:]) async {
        do { _ = try await engine.execute(id, p); message = nil } catch { message = error.localizedDescription }
        await refresh(); onChange()
    }
    private func auto(_ id: String) async {
        do {
            let r = try await engine.execute(id, [:]) as? [String: Any]
            let n = (r?["added"] as? NSNumber)?.intValue ?? 0
            message = n == 0 ? "Nothing found" : "Added \(n) spot\(n == 1 ? "" : "s")"
        } catch { message = error.localizedDescription }
        await refresh(); onChange()
    }
    private func update(_ p: [String: Any]) {
        if let i = spots.firstIndex(where: { $0.id == active }) {
            if let v = p["size"] as? Double { spots[i].size = v }
            if let v = p["feather"] as? Double { spots[i].feather = v }
            if let v = p["opacity"] as? Double { spots[i].opacity = v }
        }
        // no index: the engine edits the selected spot
        throttle.run { _ = try? await engine.execute("spot.update", p); onChange() }
    }
    /// Red-eye has no update command, so an eye is rebuilt once when the slider is released (not on every tick).
    private func eyeSlider(_ label: String, _ value: Double, _ index: Int, _ set: @escaping (Double) -> Void) -> some View {
        VStack(spacing: 2) {
            HStack { Text(label).font(.subheadline); Spacer(); Text(String(format: "%.0f", value)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: Binding(get: { value }, set: { set($0) }), in: 0...100, onEditingChanged: { editing in if !editing { Task { await commitEye(index) } } }).tint(Theme.accent)
        }
    }
    private func setEye(_ index: Int, pupil: Double? = nil, darken: Double? = nil) {
        guard let i = eyes.firstIndex(where: { $0.id == index }) else { return }
        if let pupil { eyes[i].pupil = pupil }
        if let darken { eyes[i].darken = darken }
    }
    private func commitEye(_ index: Int) async {
        guard let e = eyes.first(where: { $0.id == index }) else { return }
        _ = try? await engine.execute("redeye.delete", ["index": index])
        _ = try? await engine.execute("redeye.add", ["center": [e.center.x, e.center.y], "rx": e.rx, "ry": e.rx, "pet": e.pet, "pupilSize": e.pupil, "darken": e.darken])
        await refresh(); onChange()
    }
}
