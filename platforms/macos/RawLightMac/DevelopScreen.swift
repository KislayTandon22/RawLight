import SwiftUI

@Observable @MainActor final class DevelopModel {
    var controls: [MacControl] = []
    var image: NSImage?
    var histogram: [UInt32] = []
    var collapsed: Set<String> = []
    var hdrOn = false
    var tool = "Edit"
    var presets: [(id: String, name: String)] = []
    var history: [String] = []
    var historyCursor = 0
    var message: String?
    var lastPreset: String?
    var healMode = "heal"
    var healSize = 0.06
    private var pending: (() async -> Void)?
    private var pendingCommit = false
    private var busy = false
    var onCommit: ((UInt64) -> Void)?

    func sections() -> [String] {
        var seen: [String] = []
        for c in controls where !seen.contains(c.section) { seen.append(c.section) }
        return seen
    }

    func open(_ id: UInt64, engine: MacEngine) async {
        lastPreset = nil; hdrOn = false; message = nil
        _ = try? await engine.execute("library.select", ["ids": [id], "active": id])
        async let ctl = engine.controls()
        await render(id, engine, draft: true)   // quick first picture
        controls = await ctl
        await render(id, engine, draft: false)
        await reloadLists(engine)
    }

    func reloadLists(_ engine: MacEngine) async {
        if let arr = try? await engine.execute("presets.list") as? [[String: Any]] {
            presets = arr.compactMap { d in (d["id"] as? String).flatMap { i in (d["name"] as? String).map { (i, $0) } } }
        }
        if let r = try? await engine.execute("history.list") as? [String: Any] {
            history = (r["history"] as? [String]) ?? []
            historyCursor = (r["cursor"] as? NSNumber)?.intValue ?? 0
        }
    }

    func applyPreset(_ pid: String, amount: Int, id: UInt64, engine: MacEngine) async {
        if lastPreset != nil { _ = try? await engine.execute("edit.undo") }
        do { _ = try await engine.execute("preset.apply", ["id": pid, "amount": amount]); lastPreset = pid; message = nil } catch { message = error.localizedDescription }
        controls = await engine.controls(); await render(id, engine, draft: false); await reloadLists(engine); onCommit?(id)
    }

    func addSpot(x: Double, y: Double, id: UInt64, engine: MacEngine) async {
        do { _ = try await engine.execute("spot.add", ["mode": healMode, "points": [[x, y]], "size": healSize]); message = nil } catch { message = error.localizedDescription }
        await render(id, engine, draft: false); await reloadLists(engine); onCommit?(id)
    }

    func run(_ command: String, _ params: [String: Any] = [:], id: UInt64, engine: MacEngine) async {
        do { _ = try await engine.execute(command, params); message = nil } catch { message = error.localizedDescription }
        controls = await engine.controls(); await render(id, engine, draft: false); await reloadLists(engine); onCommit?(id)
    }

    func render(_ id: UInt64, _ engine: MacEngine, draft: Bool) async {
        if let r = await engine.render(id, maxEdge: draft ? 900 : 1600, kind: draft ? 2 : 0) { image = r.image; histogram = r.histogram }
    }

    /// Latest value wins while a render is in flight.
    func set(_ c: MacControl, _ value: Double, commit: Bool, id: UInt64, engine: MacEngine) {
        if let i = controls.firstIndex(where: { $0.id == c.id }) { controls[i].value = value }
        let commit = commit || pendingCommit   // a queued final value must not be downgraded to a draft
        pendingCommit = commit
        pending = { [weak self] in
            _ = try? await engine.execute("develop.set", ["control": c.id, "value": value])
            await self?.render(id, engine, draft: !commit)
            if commit { self?.onCommit?(id) }
        }
        guard !busy else { return }
        busy = true
        Task {
            while let w = pending { pending = nil; pendingCommit = false; await w() }
            busy = false
        }
    }

    /// Runs a one-shot command (Auto, B&W, HDR), then reloads sliders and the render.
    func quick(_ command: String, _ params: [String: Any] = [:], id: UInt64, engine: MacEngine) async {
        do { _ = try await engine.execute(command, params); message = nil } catch { message = error.localizedDescription }
        controls = await engine.controls()
        await render(id, engine, draft: false)
        await reloadLists(engine)
        onCommit?(id)
    }

    func resetAll(id: UInt64, engine: MacEngine) async {
        _ = try? await engine.execute("develop.reset")
        controls = await engine.controls()
        await render(id, engine, draft: false)
    }
}

struct DevelopScreen: View {
    @Environment(LibraryModel.self) private var lib
    @State private var dev = DevelopModel()
    var body: some View {
        VStack(spacing: 0) {
            DevTopBar()
            HStack(spacing: 6) {
                LeftDock().frame(width: 262)
                VStack(spacing: 6) {
                    ToolBar().frame(height: 40)
                    Stage()
                    Filmstrip()
                }
                RightDock().frame(width: 322)
            }
            .padding(6)
            .background(Color(red: 0.04, green: 0.04, blue: 0.05))
            DevStatus()
        }
        .background(MacTheme.bg)
        .environment(dev)
        .onAppear {
            dev.onCommit = { lib.thumbVersion[$0, default: 0] += 1 }
            lib.devAction = { a in
                guard let id = lib.activeID else { return }
                let e = lib.engine
                Task { @MainActor in
                    switch a {
                    case "auto": await dev.quick("develop.auto", id: id, engine: e)
                    case "bw": await dev.quick("develop.treatment", id: id, engine: e)
                    case "reset": await dev.resetAll(id: id, engine: e)
                    case "undo", "redo": await dev.quick("edit.\(a)", id: id, engine: e)
                    default: break
                    }
                }
            }
        }
        .onDisappear { lib.devAction = nil }
        .onChange(of: lib.toolRequest) { _, t in if let t { dev.tool = t; lib.toolRequest = nil } }
        .task(id: lib.activeID) {
            guard let id = lib.activeID else { return }
            await dev.open(id, engine: lib.engine)
            // Debug aid: RAWLIGHT_EDIT="label=value" drives the same path a slider drag does (draft then commit).
            if let e = ProcessInfo.processInfo.environment["RAWLIGHT_EDIT"]?.split(separator: "="), e.count == 2, let v = Double(e[1]),
               let c = dev.controls.first(where: { $0.label == e[0] }) {
                dev.set(c, v, commit: false, id: id, engine: lib.engine)
                try? await Task.sleep(for: .seconds(1))
                dev.set(c, v, commit: true, id: id, engine: lib.engine)
            }
        }
    }
}

private extension View {
    func glass(_ r: CGFloat = 12) -> some View {
        background(Color(white: 0.157).opacity(0.86), in: RoundedRectangle(cornerRadius: r))
            .overlay(RoundedRectangle(cornerRadius: r).stroke(Color.white.opacity(0.07)))
    }
}

private struct DevTopBar: View {
    @Environment(LibraryModel.self) private var lib
    var body: some View {
        HStack(spacing: 14) {
            Spacer().frame(width: 64)
            ModuleSwitch()
            HStack(spacing: 6) {
                Text("All Photographs").foregroundStyle(MacTheme.dim)
                Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(MacTheme.dim)
                Text("Photo \(((lib.ids.firstIndex(of: lib.activeID ?? 0)) ?? 0) + 1)")
                Text("of \(lib.ids.count)").font(.system(size: 11)).padding(.horizontal, 8).frame(height: 18)
                    .background(Color.white.opacity(0.08), in: Capsule()).foregroundStyle(MacTheme.dim)
            }.font(.system(size: 13))
            Spacer()
            HStack(spacing: 2) {
                ForEach(["★", "★", "★", "★", "★"].indices, id: \.self) { i in
                    Image(systemName: i < 3 ? "star.fill" : "star").font(.system(size: 11)).foregroundStyle(Color(red: 0.95, green: 0.76, blue: 0.31))
                }
            }
            Group {
                icon("flag"); icon("xmark.circle")
            }
            Divider().frame(height: 18)
            HStack(spacing: 2) { icon("rectangle"); icon("rectangle.split.2x1"); icon("rectangle.split.1x2") }
            Divider().frame(height: 18)
            HStack(spacing: 4) {
                ForEach(["Fit", "Fill", "100%", "200%"], id: \.self) { z in
                    Text(z).font(.system(size: 11, weight: .medium)).padding(.horizontal, 8).frame(height: 22)
                        .background(z == "Fit" ? MacTheme.accent.opacity(0.22) : Color.white.opacity(0.07), in: Capsule())
                        .foregroundStyle(z == "Fit" ? Color(red: 1, green: 0.47, blue: 0.59) : .white.opacity(0.8))
                }
            }
            Divider().frame(height: 18)
            icon("arrow.uturn.backward"); icon("arrow.uturn.forward")
        }
        .padding(.horizontal, 14).frame(height: 48).background(MacTheme.bar)
    }
    private func icon(_ n: String) -> some View {
        Image(systemName: n).font(.system(size: 13)).foregroundStyle(MacTheme.dim).frame(width: 26, height: 26)
    }
}

private struct LeftDock: View {
    @Environment(LibraryModel.self) private var lib
    @Environment(DevelopModel.self) private var dev
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                card("Navigator") {
                    NavThumb().frame(height: 130).clipShape(RoundedRectangle(cornerRadius: 6)).padding(10)
                }
                card("Presets") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(dev.presets.prefix(8), id: \.id) { p in
                            Button { if let id = lib.activeID { Task { await dev.applyPreset(p.id, amount: 100, id: id, engine: lib.engine) } } } label: {
                                Text(p.name).font(.system(size: 12)).foregroundStyle(.white.opacity(0.85)).padding(.horizontal, 12).frame(maxWidth: .infinity, alignment: .leading).frame(height: 24).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
                card("History") {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(dev.history.suffix(8).enumerated()), id: \.offset) { _, p in
                            HStack(spacing: 8) { Circle().fill(Color.white.opacity(0.25)).frame(width: 5, height: 5); Text(p).font(.system(size: 12)).lineLimit(1) }
                                .padding(.horizontal, 12).frame(height: 24)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
                }
            }
        }
    }
    private func card<C: View>(_ t: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(spacing: 0) {
            Text(t.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(MacTheme.dim)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12).frame(height: 28)
            c()
        }.glass()
    }
}

private struct ToolBar: View {
    @Environment(DevelopModel.self) private var dev
    private let names = ["Edit", "Crop", "Mask", "Heal", "Looks", "History", "Info"]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(["slider.horizontal.3", "crop", "circle.lefthalf.filled.inverse", "bandage", "sparkles", "clock.arrow.circlepath", "info.circle"].enumerated()), id: \.offset) { i, n in
                let sel = names.firstIndex(of: dev.tool) ?? 0
                HStack(spacing: 6) {
                    Image(systemName: n).font(.system(size: 13))
                    Text(names[i]).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12).frame(height: 30)
                .background(sel == i ? MacTheme.accent : .clear, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(sel == i ? .white : MacTheme.dim)
                .onTapGesture { dev.tool = names[i] }.help("\(names[i])  (\(["E","C","M","H","L","Y","I"][i]))")
            }
            Spacer()
        }.padding(.horizontal, 5).frame(maxWidth: .infinity).glass()
    }
}

private struct DevImage: View {
    @Environment(DevelopModel.self) private var dev
    @Environment(LibraryModel.self) private var lib
    var body: some View {
        if let img = dev.image {
            Image(nsImage: img).resizable().scaledToFit()
                .overlay {
                    if dev.tool == "Heal" {
                        GeometryReader { g in
                            Color.clear.contentShape(Rectangle())
                                .onTapGesture { p in
                                    guard let id = lib.activeID, g.size.width > 0, g.size.height > 0 else { return }
                                    Task { await dev.addSpot(x: p.x / g.size.width, y: p.y / g.size.height, id: id, engine: lib.engine) }
                                }
                        }
                    }
                }
        } else { ProgressView().controlSize(.small) }
    }
}

/// The Navigator picture: a small cached thumbnail, so each slider render redraws one large image, not two.
private struct NavThumb: View {
    @Environment(LibraryModel.self) private var lib
    @State private var image: NSImage?
    var body: some View {
        Group { if let image { Image(nsImage: image).resizable().scaledToFit() } else { Color.clear } }
            .task(id: "\(lib.activeID ?? 0)-\(lib.activeID.flatMap { lib.thumbVersion[$0] } ?? 0)") {
                guard let id = lib.activeID else { return }
                image = await lib.engine.thumbnail(id, edge: 360, version: lib.thumbVersion[id] ?? 0)
            }
    }
}

private struct Stage: View {
    @State private var scale = 0.0
    var body: some View {
        DevImage().padding(10).frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    Image(systemName: "minus.magnifyingglass").font(.system(size: 11))
                    Slider(value: $scale).frame(width: 120).tint(MacTheme.accent).controlSize(.small)
                    Image(systemName: "plus.magnifyingglass").font(.system(size: 11))
                    Text(scale < 0.01 ? "Fit" : "\(Int(100 + scale * 300))%").font(.system(size: 11).monospacedDigit()).frame(width: 36, alignment: .leading)
                }
                .foregroundStyle(MacTheme.dim).padding(.horizontal, 12).frame(height: 28)
                .background(Color.black.opacity(0.45), in: Capsule()).padding(12)
            }
            .background(LinearGradient(colors: [Color(red: 0.09, green: 0.09, blue: 0.11), Color(red: 0.043, green: 0.043, blue: 0.055)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct Filmstrip: View {
    @Environment(LibraryModel.self) private var lib
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 6) { ForEach(lib.ids, id: \.self) { FilmThumb(id: $0) } }.padding(.horizontal, 10)
        }.frame(height: 84).glass()
    }
}

private struct FilmThumb: View {
    @Environment(LibraryModel.self) private var lib
    let id: UInt64
    @State private var image: NSImage?
    var body: some View {
        Color(white: 0.14).frame(width: 62, height: 62)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(lib.activeID == id ? MacTheme.accent : .clear, lineWidth: 2))
            .onTapGesture { lib.activeID = id; lib.selection = [id] }
            .task(id: lib.thumbVersion[id]) { image = await lib.engine.thumbnail(id, edge: 160, version: lib.thumbVersion[id] ?? 0) }
    }
}

private struct RightDock: View {
    @Environment(DevelopModel.self) private var dev
    @Environment(LibraryModel.self) private var lib
    var body: some View {
        VStack(spacing: 0) {
            Histogram().frame(height: 96).padding(10)
            HStack(spacing: 6) {
                quick("Auto", "wand.and.stars") { await dev.quick("develop.auto", id: $0, engine: lib.engine) }
                quick("B&W", "circle.lefthalf.filled") { await dev.quick("develop.treatment", id: $0, engine: lib.engine) }
                quick("HDR", "sun.max") { await dev.quick("develop.hdr", ["enabled": !dev.hdrOn], id: $0, engine: lib.engine); dev.hdrOn.toggle() }
            }.padding(.horizontal, 10).padding(.bottom, 10)
            Divider().overlay(MacTheme.line)
            if dev.tool == "Edit" {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(dev.sections(), id: \.self) { s in Group_(section: s) }
                    }
                }
            } else {
                ToolPanel()
            }
            Divider().overlay(MacTheme.line)
            HStack(spacing: 6) {
                bar("Copy"); bar("Paste")
                Button { if let id = lib.activeID { Task { await dev.resetAll(id: id, engine: lib.engine) } } } label: {
                    Text("Reset all").font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(height: 24)
                        .background(MacTheme.accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 8)).foregroundStyle(Color(red: 1, green: 0.47, blue: 0.59))
                }.buttonStyle(.plain)
            }.padding(10)
        }.glass()
    }
    private func quick(_ t: String, _ icon: String, _ run: @escaping (UInt64) async -> Void) -> some View {
        Button { if let id = lib.activeID { Task { await run(id) } } } label: {
            Label(t, systemImage: icon).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(height: 26)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    private func bar(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .medium)).frame(maxWidth: .infinity).frame(height: 24)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct Histogram: View {
    @Environment(DevelopModel.self) private var dev
    var body: some View {
        Canvas { ctx, size in
            let h = dev.histogram
            guard h.count == 1024 else { return }
            let peak = Double(h.max() ?? 1)
            let layers: [(Int, Color)] = [(0, .red), (1, .green), (2, .blue)]
            for (ch, col) in layers {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height))
                for x in 0..<256 {
                    let v = sqrt(Double(h[ch * 256 + x]) / peak)
                    p.addLine(to: CGPoint(x: Double(x) / 255 * size.width, y: size.height - v * size.height))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height)); p.closeSubpath()
                ctx.fill(p, with: .color(col.opacity(0.45)))
            }
        }
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct Group_: View {
    @Environment(DevelopModel.self) private var dev
    let section: String
    var body: some View {
        let open = !dev.collapsed.contains(section)
        VStack(spacing: 0) {
            Button { if open { dev.collapsed.insert(section) } else { dev.collapsed.remove(section) } } label: {
                HStack {
                    Image(systemName: open ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .bold)).frame(width: 12)
                    Text(section.capitalized).font(.system(size: 12, weight: .bold))
                    Spacer()
                    Image(systemName: "eye").font(.system(size: 11)).foregroundStyle(MacTheme.dim)
                }.padding(.horizontal, 12).frame(height: 30).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if open {
                VStack(spacing: 0) {
                    ForEach(dev.controls.filter { $0.section == section }) { c in SliderRow(control: c) }
                }.padding(.horizontal, 12).padding(.bottom, 8)
            }
            Divider().overlay(MacTheme.line)
        }
    }
}

private struct SliderRow: View {
    @Environment(DevelopModel.self) private var dev
    @Environment(LibraryModel.self) private var lib
    let control: MacControl
    @State private var hover = false
    var body: some View {
        let edited = abs(control.value - control.def) > 1e-9
        HStack(spacing: 8) {
            Text(control.label).font(.system(size: 11.5, weight: edited ? .medium : .regular))
                .foregroundStyle(edited ? .white : Color(white: 0.71)).frame(width: 96, alignment: .leading).lineLimit(1)
                .onTapGesture(count: 2) { push(control.def, true) }
            Track(control: control, edited: edited) { v, commit in push(v, commit) }.frame(height: 24)
            Text(String(format: "%.\(control.decimals)f", control.value).replacingOccurrences(of: "-", with: "\u{2212}"))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(edited ? Color(red: 1, green: 0.47, blue: 0.59) : .white.opacity(0.8))
                .frame(width: 46, height: 20, alignment: .trailing).padding(.trailing, 6)
                .background(Color.white.opacity(hover ? 0.12 : 0.07), in: RoundedRectangle(cornerRadius: 6))
        }
        .frame(height: 24)
        .background(hover ? Color.white.opacity(0.04) : .clear)
        .onHover { hover = $0 }
    }
    private func push(_ v: Double, _ commit: Bool) {
        guard let id = lib.activeID else { return }
        dev.set(control, v, commit: commit, id: id, engine: lib.engine)
    }
}

private struct Track: View {
    let control: MacControl
    let edited: Bool
    let onChange: (Double, Bool) -> Void
    var body: some View {
        GeometryReader { g in
            let thumb = xPos(control.value, g.size.width), origin = control.centered ? xPos(control.def, g.size.width) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.16)).frame(height: 3)
                if edited {
                    Capsule().fill(MacTheme.accent).frame(width: abs(thumb - origin), height: 3).offset(x: min(thumb, origin))
                }
                if control.centered { Rectangle().fill(Color.white.opacity(0.35)).frame(width: 1, height: 9).offset(x: origin) }
                Circle().fill(Color(white: 0.91)).frame(width: 11, height: 11)
                    .overlay(Circle().stroke(edited ? MacTheme.accent : Color.black.opacity(0.35), lineWidth: edited ? 2 : 1))
                    .offset(x: thumb - 5.5)
            }
            .frame(maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { d in onChange(value(d.location.x, g.size.width), false) }
                .onEnded { d in onChange(value(d.location.x, g.size.width), true) })
            .onTapGesture(count: 2) { onChange(control.def, true) }
        }
    }
    private func xPos(_ v: Double, _ w: CGFloat) -> CGFloat { CGFloat((v - control.min) / (control.max - control.min)) * w }
    private func value(_ px: CGFloat, _ w: CGFloat) -> Double {
        let f = min(max(Double(px / max(w, 1)), 0), 1)
        let v = control.min + f * (control.max - control.min)
        let p = pow(10, Double(control.decimals))
        return (v * p).rounded() / p
    }
}

private struct DevStatus: View {
    @Environment(LibraryModel.self) private var lib
    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(Color.green).frame(width: 6, height: 6)
            Text("Autosaved").font(.system(size: 11)).foregroundStyle(MacTheme.dim)
            Spacer()
            Text("sRGB · Rust engine").font(.system(size: 11)).foregroundStyle(MacTheme.dim)
        }.padding(.horizontal, 14).frame(height: 26).background(MacTheme.bar)
    }
}
