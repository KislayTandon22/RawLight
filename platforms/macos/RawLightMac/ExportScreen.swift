import SwiftUI

@Observable @MainActor final class ExportModel {
    var format = "jpeg"
    var quality = UserDefaults.standard.object(forKey: "exportQuality") as? Double ?? 90.0
    var longEdge = UserDefaults.standard.object(forKey: "exportEdge") as? Int ?? 3000
    var colorSpace = UserDefaults.standard.string(forKey: "exportSpace") ?? "srgb"
    var useWatermark = true
    var wm = Watermark()
    var savedName: String?
    var saveName = ""
    var usePixels = false
    var folder: URL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!.appending(path: "RawLight Exports", directoryHint: .isDirectory)
    /// How files are named: tokens such as {name} {seq} {date} {camera} {rating}; {seq:4} pads to four digits.
    var naming = UserDefaults.standard.string(forKey: "exportNaming") ?? "{name}"
    var startNumber = 1
    /// A folder made inside the chosen one for this export; {date} becomes today's date.
    var subfolder = ""
    var conflict = "unique"
    var working = false
    var message: String?
    var preview: NSImage?
    var base: NSImage?
    let store = WatermarkStore.shared

    /// Short edge the exported file will have; margins in pixels are measured against it (2000 when exporting full size).
    var aspect: Double { guard let b = base, b.size.width > 0, b.size.height > 0 else { return 2.0 / 3.0 }; return Double(min(b.size.width, b.size.height) / max(b.size.width, b.size.height)) }
    var shortEdge: Int { longEdge == 0 ? 0 : Int(Double(longEdge) * aspect) }
    var referenceShort: Double { shortEdge > 0 ? Double(shortEdge) : 2000 }

    func chooseGraphic() {
        let p = NSOpenPanel(); p.allowedContentTypes = [.png, .jpeg]; p.allowsMultipleSelection = false
        p.message = "Choose a logo or signature (PNG with transparency works best)"
        if p.runModal() == .OK, let u = p.url {
            do { wm.imagePath = try WatermarkStore.copyLogo(from: u); message = nil } catch { message = error.localizedDescription }
        }
    }

    func refreshPreview(id: UInt64?, engine: MacEngine) async {
        guard useWatermark, wm.hasContent, let id else { preview = base; return }
        try? await Task.sleep(for: .milliseconds(120))
        if Task.isCancelled { return }
        let img = await engine.renderWatermarked(id, maxEdge: 1400, watermark: wm.params, exportShortEdge: shortEdge)
        if !Task.isCancelled { preview = img ?? base }
    }

    func saveCurrent(engine: MacEngine) async {
        do { try await store.save(wm, as: saveName, engine: engine); savedName = saveName; message = "Saved watermark “\(saveName)”"; saveName = "" }
        catch { message = error.localizedDescription }
    }
    func useSaved(_ name: String, engine: MacEngine) async {
        do { wm = try await store.load(name, engine: engine); savedName = name; useWatermark = true; message = nil } catch { message = error.localizedDescription }
    }
    func importFile(engine: MacEngine) async {
        let p = NSOpenPanel(); p.allowedContentTypes = [.json]; p.message = "Choose a RawLight watermark file"
        guard p.runModal() == .OK, let u = p.url else { return }
        do { let r = try await store.importFile(u, engine: engine); wm = r.watermark; savedName = r.name; useWatermark = true; message = "Imported “\(r.name)”" }
        catch { message = error.localizedDescription }
    }
    func exportFile(engine: MacEngine) async {
        let p = NSSavePanel(); p.allowedContentTypes = [.json]; p.nameFieldStringValue = "\(savedName ?? "watermark").json"
        guard p.runModal() == .OK, let u = p.url else { return }
        do { try await engine.watermarkFile(wm.params, name: savedName ?? "Watermark").write(to: u, atomically: true, encoding: .utf8); message = "Exported \(u.lastPathComponent)" }
        catch { message = error.localizedDescription }
    }

    func chooseFolder() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Choose"; p.message = "Choose or create the folder the exported files are saved in"; p.directoryURL = folder
        if p.runModal() == .OK, let u = p.url { folder = u }
    }

    /// The subfolder name with {date} filled in, and anything that could leave the chosen folder removed.
    var resolvedSubfolder: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return subfolder.replacingOccurrences(of: "{date}", with: f.string(from: Date()))
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
    }
    /// What the naming rule gives for a photo called IMG_0042.CR2 at position `n`, so the rule can be checked before exporting.
    func example(_ n: Int) -> String {
        var out = naming.isEmpty ? "{name}" : naming
        let d = DateFormatter(); d.dateFormat = "yyyyMMdd"
        let num = n + startNumber - 1
        func seq(_ digits: Int) -> String { String(format: "%0\(digits)d", num) }
        for (tok, val) in [("{name}", "IMG_0042"), ("{num}", "0042"), ("{date}", d.string(from: Date())), ("{ext}", "CR2"), ("{rating}", "0")] { out = out.replacingOccurrences(of: tok, with: val) }
        if let r = out.range(of: "\\{seq:(\\d+)\\}", options: .regularExpression) {
            out.replaceSubrange(r, with: seq(Int(out[r].dropFirst(5).dropLast()) ?? 3))
        }
        out = out.replacingOccurrences(of: "{seq}", with: seq(3)).replacingOccurrences(of: "{n}", with: seq(3))
        return out + "." + ["jpeg": "jpg", "png": "png", "tiff": "tif", "webp": "webp"][format, default: "jpg"]
    }

    func run(ids: [UInt64], engine: MacEngine) async {
        working = true; message = nil
        defer { working = false }
        UserDefaults.standard.set(naming, forKey: "exportNaming")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var p: [String: Any] = ["ids": ids, "format": format, "quality": Int(quality), "longEdge": longEdge, "colorSpace": colorSpace,
                                "naming": naming, "startNumber": max(startNumber, 1), "conflict": conflict, "dir": folder.path]
        if !resolvedSubfolder.isEmpty { p["subfolder"] = resolvedSubfolder }
        if useWatermark, wm.hasContent { p["watermark"] = wm.params }
        do {
            let r = try await engine.execute("app.export", p)
            let files = ((r as? [String: Any])?["files"] as? [[String: Any]]) ?? []
            let into = resolvedSubfolder.isEmpty ? folder.path : folder.appending(path: resolvedSubfolder).path
            message = files.isEmpty ? "Nothing was exported" : "Exported \(files.count) file\(files.count == 1 ? "" : "s") to \(into)"
        } catch { message = error.localizedDescription }
    }
}

struct ExportScreen: View {
    @Environment(LibraryModel.self) private var lib
    @State private var ex = ExportModel()
    private var ids: [UInt64] { lib.selection.isEmpty ? (lib.activeID.map { [$0] } ?? []) : lib.ids.filter { lib.selection.contains($0) } }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Spacer().frame(width: 64)
                ModuleSwitch()
                Text("Export \(ids.count) photo\(ids.count == 1 ? "" : "s")").font(.system(size: 13)).foregroundStyle(MacTheme.dim)
                Spacer()
            }.padding(.horizontal, 14).frame(height: 48).background(MacTheme.bar)
            HStack(spacing: 6) {
                PreviewPane().environment(ex)
                SettingsPane(ids: ids).environment(ex).frame(width: 360)
            }
            .padding(6).background(Color(red: 0.04, green: 0.04, blue: 0.05))
            HStack {
                Text(ex.message ?? "Files go to \(ex.folder.path)").font(.system(size: 11)).foregroundStyle(MacTheme.dim).lineLimit(1)
                Spacer()
            }.padding(.horizontal, 14).frame(height: 26).background(MacTheme.bar)
        }
        .background(MacTheme.bg)
        .environment(ex)
        .task(id: ids.first) {
            guard let id = ids.first else { return }
            let img = await lib.engine.render(id, maxEdge: 1400)?.image
            guard !Task.isCancelled, ids.first == id else { return }
            ex.base = img
            ex.preview = ex.base
            await ex.refreshPreview(id: id, engine: lib.engine)
        }
        .task(id: "\(ex.wm.params.description)\(ex.useWatermark)\(ex.longEdge)") { await ex.refreshPreview(id: ids.first, engine: lib.engine) }
    }
}

private struct PreviewPane: View {
    @Environment(ExportModel.self) private var ex
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.09, blue: 0.11), Color(red: 0.043, green: 0.043, blue: 0.055)], startPoint: .top, endPoint: .bottom)
            if let img = ex.preview {
                let ar = img.size.width / max(img.size.height, 1)
                Image(nsImage: img).resizable().scaledToFit()
                    .aspectRatio(ar, contentMode: .fit)
                    .padding(24)
            } else { ProgressView() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsPane: View {
    @Environment(ExportModel.self) private var ex
    @Environment(LibraryModel.self) private var lib
    let ids: [UInt64]
    var body: some View {
        @Bindable var e = ex
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    head("File")
                    row("Format") { Picker("", selection: $e.format) { Text("JPEG").tag("jpeg"); Text("PNG").tag("png"); Text("TIFF").tag("tiff"); Text("WebP").tag("webp") }.labelsHidden().pickerStyle(.segmented) }
                    if e.format == "jpeg" || e.format == "webp" {
                        row("Quality") { Slider(value: $e.quality, in: 40...100, step: 1).tint(MacTheme.accent); Text("\(Int(e.quality))").monospacedDigit().frame(width: 30) }
                    }
                    row("Long edge") { Picker("", selection: $e.longEdge) { Text("1600").tag(1600); Text("3000").tag(3000); Text("Full").tag(0) }.labelsHidden().pickerStyle(.segmented) }
                    row("Colour") { Picker("", selection: $e.colorSpace) { Text("sRGB").tag("srgb"); Text("P3").tag("displayP3"); Text("Adobe").tag("adobeRgb") }.labelsHidden().pickerStyle(.segmented) }
                    head("Files")
                    row("Folder") {
                        Text(ex.folder.lastPathComponent).lineLimit(1).truncationMode(.middle).font(.system(size: 11.5))
                        Spacer(); Button("Choose…") { ex.chooseFolder() }.controlSize(.small)
                    }
                    row("Subfolder") { TextField("optional, e.g. Kyoto {date}", text: $e.subfolder).textFieldStyle(.roundedBorder).controlSize(.small) }
                    row("Name") { TextField("{name}", text: $e.naming).textFieldStyle(.roundedBorder).controlSize(.small) }
                    HStack(spacing: 4) {
                        ForEach(["{name}", "{seq}", "{date}", "{camera}", "{rating}"], id: \.self) { t in
                            Button(t) { e.naming += t }.buttonStyle(.plain).font(.system(size: 10.5)).padding(.horizontal, 6).padding(.vertical, 3)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }
                    }.padding(.horizontal, 14).padding(.leading, 72)
                    row("Start at") {
                        Stepper(value: $e.startNumber, in: 1...99999) { Text("\(e.startNumber)").monospacedDigit() }.controlSize(.small)
                        Spacer()
                        Picker("", selection: $e.conflict) { Text("Keep both").tag("unique"); Text("Replace").tag("overwrite"); Text("Skip").tag("skip") }.labelsHidden().controlSize(.small).frame(width: 96)
                    }
                    Text("e.g. \(ex.example(1)), \(ex.example(2))").font(.system(size: 10.5)).foregroundStyle(MacTheme.dim).padding(.horizontal, 14).padding(.leading, 72)
                    head("Watermark") { Toggle("", isOn: $e.useWatermark).labelsHidden().toggleStyle(.switch).tint(MacTheme.accent).controlSize(.small) }
                    if e.useWatermark { watermarkSection($e) }
                }.padding(.bottom, 8)
            }
            Divider().overlay(MacTheme.line)
            Button { Task { await ex.run(ids: ids, engine: lib.engine) } } label: {
                Text(ex.working ? "Exporting…" : "Export").font(.system(size: 13, weight: .semibold)).frame(maxWidth: .infinity).frame(height: 34)
                    .background(MacTheme.accent, in: Capsule()).foregroundStyle(.white)
            }.buttonStyle(.plain).disabled(ex.working || ids.isEmpty).padding(12)
        }
        .background(Color(white: 0.157).opacity(0.86), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.07)))
    }
    @ViewBuilder private func watermarkSection(_ e: Bindable<ExportModel>) -> some View {
        let m = e.wrappedValue
        row("Saved") {
            Menu {
                if m.store.names.isEmpty { Text("No saved watermarks yet") }
                ForEach(m.store.names, id: \.self) { n in
                    Button(n) { Task { await m.useSaved(n, engine: lib.engine) } }
                }
                if !m.store.names.isEmpty {
                    Divider()
                    Menu("Delete") { ForEach(m.store.names, id: \.self) { n in Button(n, role: .destructive) { m.store.delete(n); if m.savedName == n { m.savedName = nil } } } }
                }
            } label: { Text(m.savedName ?? "Choose…").lineLimit(1) }.controlSize(.small)
            Spacer()
        }
        row("Style") {
            Picker("", selection: Binding(get: { m.wm.isGraphic }, set: { g in if g { m.chooseGraphic() } else { m.wm.imagePath = "" } })) {
                Text("Text").tag(false); Text("Graphic").tag(true)
            }.labelsHidden().pickerStyle(.segmented)
        }
        if m.wm.isGraphic {
            row("Picture") {
                Text(URL(fileURLWithPath: m.wm.imagePath).lastPathComponent).lineLimit(1).font(.system(size: 11)).foregroundStyle(MacTheme.dim)
                Spacer(); Button("Choose…") { m.chooseGraphic() }.controlSize(.small)
            }
            row("Logo size") { Slider(value: e.wm.imageWidth, in: 0.05...0.6).tint(MacTheme.accent); val(m.wm.imageWidth) }
        } else {
            row("Text") { TextField("© Your name", text: e.wm.text).textFieldStyle(.roundedBorder) }
            row("Size") { Slider(value: e.wm.size, in: 0.01...0.15).tint(MacTheme.accent); val(m.wm.size) }
            row("Colour") { ColorPicker("", selection: e.wm.color, supportsOpacity: false).labelsHidden(); Toggle("Shadow", isOn: e.wm.shadow).toggleStyle(.switch).controlSize(.small).tint(MacTheme.accent); Spacer() }
            row("Vertical") { Toggle("", isOn: e.wm.vertical).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(MacTheme.accent); Spacer() }
        }
        row("Position") {
            let cols = Array(repeating: GridItem(.fixed(34), spacing: 3), count: 3)
            LazyVGrid(columns: cols, spacing: 3) {
                ForEach(Watermark.Anchor.allCases) { a in
                    Button { m.wm.anchor = a } label: {
                        Image(systemName: a.symbol).font(.system(size: a == .center ? 6 : 10, weight: .semibold)).frame(width: 34, height: 22)
                            .background(m.wm.anchor == a ? MacTheme.accent : Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 4))
                    }.buttonStyle(.plain).help(a.label)
                }
            }.fixedSize()
            Spacer()
        }
        row("Margins") { Picker("", selection: e.usePixels) { Text("%").tag(false); Text("px").tag(true) }.labelsHidden().pickerStyle(.segmented).frame(width: 90); Spacer() }
        margin("Across", e.wm.insetX, enabled: ![.top, .center, .bottom].contains(m.wm.anchor), m)
        margin("Down", e.wm.insetY, enabled: ![.left, .center, .right].contains(m.wm.anchor), m)
        row("Rotate") { Picker("", selection: e.wm.rotation) { ForEach([0, 90, 180, 270], id: \.self) { Text("\($0)°").tag($0) } }.labelsHidden().pickerStyle(.segmented) }
        row("Opacity") { Slider(value: e.wm.opacity, in: 0.05...1).tint(MacTheme.accent); val(m.wm.opacity) }
        head("Frame")
        row("Border") { Slider(value: e.wm.borderWidth, in: 0...0.05).tint(MacTheme.accent); val(m.wm.borderWidth) }
        if m.wm.borderWidth > 0 { row("Border col.") { ColorPicker("", selection: e.wm.borderColor, supportsOpacity: false).labelsHidden(); Spacer() } }
        row("Box") { Slider(value: e.wm.backgroundOpacity, in: 0...1).tint(MacTheme.accent); val(m.wm.backgroundOpacity) }
        if m.wm.backgroundOpacity > 0 { row("Box colour") { ColorPicker("", selection: e.wm.backgroundColor, supportsOpacity: false).labelsHidden(); Spacer() } }
        if m.wm.borderWidth > 0 || m.wm.backgroundOpacity > 0 {
            row("Padding") { Slider(value: e.wm.padding, in: 0...0.1).tint(MacTheme.accent); val(m.wm.padding) }
            row("Corners") { Slider(value: e.wm.radius, in: 0...0.05).tint(MacTheme.accent); val(m.wm.radius) }
        }
        head("Save and share")
        row("Name") {
            TextField("Name", text: e.saveName).textFieldStyle(.roundedBorder)
            Button("Save") { Task { await m.saveCurrent(engine: lib.engine) } }.controlSize(.small).disabled(!m.wm.hasContent || m.saveName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        row("File") {
            Button("Import…") { Task { await m.importFile(engine: lib.engine) } }.controlSize(.small)
            Button("Export…") { Task { await m.exportFile(engine: lib.engine) } }.controlSize(.small).disabled(!m.wm.hasContent)
            Spacer()
        }
    }
    @ViewBuilder private func margin(_ t: String, _ v: Binding<Double>, enabled: Bool, _ m: ExportModel) -> some View {
        let ref = m.referenceShort
        row(t) {
            if m.usePixels {
                Slider(value: Binding(get: { v.wrappedValue * ref }, set: { v.wrappedValue = min(0.4, max(0, $0 / ref)) }), in: 0...(0.4 * ref)).tint(MacTheme.accent)
                TextField("", value: Binding(get: { (v.wrappedValue * ref).rounded() }, set: { v.wrappedValue = min(0.4, max(0, $0 / ref)) }), format: .number)
                    .textFieldStyle(.roundedBorder).frame(width: 54)
                Text("px").font(.system(size: 11)).foregroundStyle(MacTheme.dim)
            } else {
                Slider(value: v, in: 0...0.4).tint(MacTheme.accent)
                Text(String(format: "%.1f%%", v.wrappedValue * 100)).font(.system(size: 11).monospacedDigit()).frame(width: 46, alignment: .trailing)
            }
        }.disabled(!enabled).opacity(enabled ? 1 : 0.45)
    }
    private func head<T: View>(_ t: String, @ViewBuilder trailing: () -> T = { EmptyView() }) -> some View {
        HStack { Text(t.uppercased()).font(.system(size: 11, weight: .bold)).tracking(0.6).foregroundStyle(MacTheme.dim); Spacer(); trailing() }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 4)
    }
    private func row<C: View>(_ l: String, @ViewBuilder _ c: () -> C) -> some View {
        HStack(spacing: 8) {
            Text(l).font(.system(size: 11.5)).foregroundStyle(Color(white: 0.71)).frame(width: 64, alignment: .leading)
            c()
        }.padding(.horizontal, 14).frame(minHeight: 30)
    }
    private func val(_ v: Double) -> some View {
        Text(String(format: "%.2f", v)).font(.system(size: 11).monospacedDigit()).frame(width: 38, alignment: .trailing)
    }
}
