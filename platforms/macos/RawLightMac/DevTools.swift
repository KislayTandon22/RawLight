import SwiftUI

/// Right-dock content for every Develop tab except Edit; the tabs match the iPad app (Edit, Crop, Mask, Heal, Looks, History, Info).
struct ToolPanel: View {
    @Environment(DevelopModel.self) private var dev
    @Environment(LibraryModel.self) private var lib
    @State private var angle = 0.0
    @State private var amount = 100.0
    @State private var maskValues: [String: Double] = [:]
    @State private var info: [(String, String)] = []

    private let aspects: [(String, String)] = [("original", "Original"), ("free", "Free"), ("1x1", "1:1"), ("4x5", "4:5"), ("5x7", "5:7"),
                                               ("2x3", "2:3"), ("4x3", "4:3"), ("16x9", "16:9"), ("16x10", "16:10")]
    private let maskSliders: [(String, String, ClosedRange<Double>)] = [
        ("exposure", "Exposure", -4...4), ("contrast", "Contrast", -100...100), ("highlights", "Highlights", -100...100),
        ("shadows", "Shadows", -100...100), ("saturation", "Saturation", -100...100),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch dev.tool {
                case "Crop": crop
                case "Mask": mask
                case "Heal": heal
                case "Looks": looks
                case "History": history
                default: infoPanel
                }
                if let m = dev.message { Text(m).font(.system(size: 11)).foregroundStyle(MacTheme.accent) }
            }.padding(12)
        }
        .task(id: dev.tool) { if dev.tool == "Info" { await loadInfo() } }
    }

    private var id: UInt64? { lib.activeID }
    private func go(_ cmd: String, _ p: [String: Any] = [:]) { if let id { Task { await dev.run(cmd, p, id: id, engine: lib.engine) } } }
    private func title(_ t: String) -> some View { Text(t.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(MacTheme.dim) }
    private func chip(_ t: String, _ icon: String? = nil, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 5) { if let icon { Image(systemName: icon).font(.system(size: 11)) }; Text(t).font(.system(size: 11, weight: .medium)).lineLimit(1) }
                .frame(maxWidth: .infinity).frame(height: 28).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
    private let two = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]
    private let three = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    // MARK: crop

    private var crop: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Aspect")
            LazyVGrid(columns: three, spacing: 6) { ForEach(aspects, id: \.0) { a in chip(a.1) { go("crop.aspect", ["aspect": a.0]) } } }
            title("Straighten")
            HStack {
                Slider(value: $angle, in: -45...45) { editing in if !editing { go("crop.straighten", ["angle": (angle * 100).rounded() / 100]) } }.tint(MacTheme.accent)
                Text(String(format: "%.1f°", angle)).font(.system(size: 11).monospacedDigit()).foregroundStyle(MacTheme.dim).frame(width: 44)
            }
            LazyVGrid(columns: two, spacing: 6) {
                chip("Swap shape", "aspectratio") { go("crop.rotateAspect") }
                chip("Auto level", "level") { go("crop.autoStraighten") }
                chip("Reset crop", "arrow.counterclockwise") { angle = 0; go("crop.reset") }
            }
        }
    }

    // MARK: mask

    private var mask: some View {
        VStack(alignment: .leading, spacing: 12) {
            title("Add a mask")
            LazyVGrid(columns: two, spacing: 6) {
                chip("Radial", "circle.dashed") { go("mask.add", ["kind": "radial", "center": [0.5, 0.5], "rx": 0.3, "ry": 0.25, "angle": 0, "feather": 50]) }
                chip("Linear", "rectangle.split.1x2") { go("mask.add", ["kind": "linear"]) }
                chip("Subject", "person.crop.square") { go("mask.add", ["kind": "subject"]) }
                chip("Sky", "cloud") { go("mask.add", ["kind": "sky"]) }
                chip("Background", "photo") { go("mask.add", ["kind": "background"]) }
                chip("Brush", "paintbrush") { go("mask.add", ["kind": "brush"]) }
            }
            title("Adjust the selected mask")
            ForEach(maskSliders, id: \.0) { s in
                HStack {
                    Text(s.1).font(.system(size: 12)).frame(width: 78, alignment: .leading)
                    Slider(value: Binding(get: { maskValues[s.0] ?? 0 }, set: { maskValues[s.0] = $0 }), in: s.2) { editing in
                        if !editing { go("mask.adjust", ["values": [s.0: maskValues[s.0] ?? 0]]) }
                    }.tint(MacTheme.accent)
                    Text(String(format: "%.1f", maskValues[s.0] ?? 0)).font(.system(size: 11).monospacedDigit()).foregroundStyle(MacTheme.dim).frame(width: 34)
                }
            }
            LazyVGrid(columns: two, spacing: 6) {
                chip("Invert", "circle.lefthalf.filled") { go("mask.invert") }
                chip("Duplicate", "plus.square.on.square") { go("mask.duplicate") }
                chip("Delete", "trash") { go("mask.delete") }
                chip("Delete all", "trash.slash") { go("mask.deleteAll") }
            }
        }
    }

    // MARK: heal

    private var heal: some View {
        @Bindable var d = dev
        return VStack(alignment: .leading, spacing: 12) {
            title("Mode")
            Picker("Mode", selection: $d.healMode) { Text("Heal").tag("heal"); Text("Clone").tag("clone") }.pickerStyle(.segmented).labelsHidden()
            title("Brush size")
            HStack {
                Slider(value: $d.healSize, in: 0.01...0.2).tint(MacTheme.accent)
                Text(String(format: "%.0f%%", d.healSize * 100)).font(.system(size: 11).monospacedDigit()).foregroundStyle(MacTheme.dim).frame(width: 36)
            }
            Text("Click a blemish on the photo to \(d.healMode == "heal" ? "heal" : "clone over") it.").font(.system(size: 12)).foregroundStyle(MacTheme.dim)
            LazyVGrid(columns: two, spacing: 6) {
                chip("Find dust", "sparkles") { go("spot.findDust") }
                chip("Find blemishes", "face.smiling") { go("spot.findBlemishes") }
                chip("Delete selected", "trash") { go("spot.delete") }
            }
        }
    }

    // MARK: looks

    private var looks: some View {
        VStack(alignment: .leading, spacing: 10) {
            title("Looks")
            HStack {
                Text("Amount").font(.system(size: 12))
                Slider(value: $amount, in: 0...100).tint(MacTheme.accent)
                Text("\(Int(amount))").font(.system(size: 11).monospacedDigit()).foregroundStyle(MacTheme.dim).frame(width: 28)
            }
            if dev.presets.isEmpty { Text("No looks available.").font(.system(size: 12)).foregroundStyle(MacTheme.dim) }
            LazyVGrid(columns: two, spacing: 6) {
                ForEach(dev.presets, id: \.id) { p in
                    Button { if let id { Task { await dev.applyPreset(p.id, amount: Int(amount), id: id, engine: lib.engine) } } } label: {
                        Text(p.name).font(.system(size: 11, weight: .medium)).lineLimit(1).frame(maxWidth: .infinity).frame(height: 30)
                            .background(dev.lastPreset == p.id ? MacTheme.accent : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: history

    private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                chip("Undo", "arrow.uturn.backward") { go("edit.undo") }
                chip("Redo", "arrow.uturn.forward") { go("edit.redo") }
            }
            title("Steps")
            if dev.history.isEmpty { Text("No edits yet.").font(.system(size: 12)).foregroundStyle(MacTheme.dim) }
            ForEach(Array(dev.history.enumerated()), id: \.offset) { i, step in
                Button { go("history.restore", ["index": i]) } label: {
                    HStack(spacing: 8) {
                        Circle().fill(i + 1 == dev.historyCursor ? MacTheme.accent : Color.white.opacity(0.25)).frame(width: 6, height: 6)
                        Text(step).font(.system(size: 12)).lineLimit(1)
                        Spacer()
                    }.frame(height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    // MARK: info

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            title("Photo")
            if info.isEmpty { Text("No details.").font(.system(size: 12)).foregroundStyle(MacTheme.dim) }
            ForEach(Array(info.enumerated()), id: \.offset) { _, kv in
                HStack(alignment: .top) {
                    Text(kv.0).font(.system(size: 11)).foregroundStyle(MacTheme.dim).frame(width: 96, alignment: .leading)
                    Text(kv.1).font(.system(size: 11)).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func loadInfo() async {
        guard let r = try? await lib.engine.execute("photo.inspect") as? [String: Any] else { info = []; return }
        info = r.keys.sorted().compactMap { k in
            guard k != "develop", k != "history" else { return nil }
            let v = r[k]
            if v is NSNull || v == nil { return nil }
            return (k.capitalized, "\(v!)")
        }
    }
}
