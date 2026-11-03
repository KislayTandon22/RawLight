import SwiftUI
import UniformTypeIdentifiers

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ids: [UInt64]
    @State private var format = "jpeg"
    @State private var quality = 90.0
    @State private var longEdge = 3000
    @State private var colorSpace = "srgb"
    @State private var working = false
    @State private var results: [URL] = []
    @State private var progress: Int = 0
    @State private var error: String?
    @State private var watermarkOn = false
    @State private var watermark = Watermark()
    @State private var editingWatermark = false
    @State private var savedWatermarks = WatermarkStore.shared
    @State private var watermarkName: String?
    @State private var pickingLogo = false
    @AppStorage("exportNaming") private var naming = "{name}"
    @State private var startNumber = 1
    @State private var subfolder = ""
    @State private var destination: URL?
    @State private var pickingFolder = false
    @State private var savedMessage: String?

    private let sizes: [(String, Int)] = [("1600", 1600), ("3000", 3000), ("Full", 0)]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(ids.count > 1 ? "Export \(ids.count) photos" : "Export").font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).panelBackground(in: Circle()) }
            }
            Picker("Format", selection: $format) {
                Text("JPEG").tag("jpeg"); Text("PNG").tag("png"); Text("TIFF").tag("tiff"); Text("WebP").tag("webp")
            }.pickerStyle(.segmented)
            if format == "jpeg" || format == "webp" {
                HStack { Text("Quality"); Slider(value: $quality, in: 40...100, step: 1).tint(Theme.accent); Text("\(Int(quality))").monospacedDigit() }
            }
            HStack {
                Text("Long edge")
                Picker("Size", selection: $longEdge) { ForEach(sizes, id: \.1) { Text($0.0).tag($0.1) } }.pickerStyle(.segmented)
            }
            HStack {
                Text("Colour space")
                Picker("Space", selection: $colorSpace) { Text("sRGB").tag("srgb"); Text("Display P3").tag("displayP3"); Text("Adobe RGB").tag("adobeRgb") }
                    .pickerStyle(.segmented)
            }
            DisclosureGroup("File names and folder") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Name").frame(width: 76, alignment: .leading)
                        TextField("{name}", text: $naming).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(8).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack { ForEach(["{name}", "{seq}", "{date}", "{camera}", "{rating}"], id: \.self) { t in
                            Button(t) { naming += t }.buttonStyle(.bordered).tint(Theme.accent).controlSize(.small)
                        } }
                    }
                    Stepper("Number from \(startNumber)", value: $startNumber, in: 1...99999)
                    HStack {
                        Text("Folder").frame(width: 76, alignment: .leading)
                        TextField("optional, e.g. Kyoto {date}", text: $subfolder).autocorrectionDisabled()
                            .padding(8).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    HStack {
                        Text("Save in").frame(width: 76, alignment: .leading)
                        Text(destination?.lastPathComponent ?? "Choose when sharing").foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button(destination == nil ? "Choose…" : "Change") { pickingFolder = true }.buttonStyle(.bordered).tint(Theme.accent).controlSize(.small)
                        if destination != nil { Button("Clear") { destination = nil }.buttonStyle(.bordered).controlSize(.small) }
                    }
                    Text("e.g. \(example(1)), \(example(2))").font(.footnote).foregroundStyle(.secondary)
                }.padding(.top, 6)
            }.tint(Theme.accent)
            HStack {
                Toggle("Watermark", isOn: $watermarkOn).tint(Theme.accent).layoutPriority(1)
                Menu {
                    if savedWatermarks.names.isEmpty {
                        Text("No saved watermarks yet")
                    } else {
                        ForEach(savedWatermarks.names, id: \.self) { name in
                            Button { Task { await useSaved(name) } } label: {
                                if name == watermarkName { Label(name, systemImage: "checkmark") } else { Text(name) }
                            }
                        }
                    }
                } label: {
                    Label(watermarkName ?? "Saved", systemImage: "tray.full")
                        .lineLimit(1).truncationMode(.tail).frame(width: 128)
                }
                    .buttonStyle(.bordered).tint(Theme.accent).fixedSize()
                Button { editingWatermark = true } label: { Label(watermark.hasContent ? "Edit" : "Set up", systemImage: "slider.horizontal.3") }
                    .buttonStyle(.bordered).tint(Theme.accent).disabled(!watermarkOn).fixedSize()
            }
            .transaction { $0.animation = nil }
            if watermarkOn {
                Picker("Style", selection: Binding(get: { watermark.isGraphic }, set: { graphic in
                    if graphic { pickingLogo = true } else { watermark.imagePath = "" }
                })) { Text("Text").tag(false); Text("Graphic").tag(true) }.pickerStyle(.segmented)
                if watermark.isGraphic {
                    HStack {
                        Text(URL(fileURLWithPath: watermark.imagePath).lastPathComponent).lineLimit(1).foregroundStyle(.secondary)
                        Spacer()
                        Button("Choose picture…") { pickingLogo = true }.tint(Theme.accent)
                    }
                } else {
                    TextField("© Your name", text: $watermark.text)
                        .padding(10).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            if watermarkOn && !watermark.hasContent {
                Text("Add text or a graphic, or the watermark is left off.").font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.accentSoft) }
            Spacer()
            if let savedMessage { Text(savedMessage).font(.footnote).foregroundStyle(.secondary) }
            if !results.isEmpty {
                ShareLink(items: results) { footer(results.count > 1 ? "Share \(results.count) files" : "Share or Save", "square.and.arrow.up") }
            } else {
                Button { Task { await run() } } label: { footer(working ? "Exporting…" : "Export", "arrow.down.circle") }.disabled(working)
            }
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .fileImporter(isPresented: $pickingFolder, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { destination = url }
        }
        .fileImporter(isPresented: $pickingLogo, allowedContentTypes: [.png, .jpeg]) { result in
            if case .success(let url) = result {
                do { watermark.imagePath = try WatermarkStore.copyLogo(from: url); error = nil } catch { self.error = error.localizedDescription }
            }
        }
        .sheet(isPresented: $editingWatermark) {
            WatermarkEditor(watermark: $watermark, photoID: ids.first, exportShortEdge: longEdge == 0 ? 0 : longEdge * 2 / 3)
        }
    }

    /// Apply a saved watermark and switch the watermark on.
    private func useSaved(_ name: String) async {
        do {
            watermark = try await savedWatermarks.load(name, engine: model.engine)
            watermarkName = name
            watermarkOn = true
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    /// What the naming rule gives for a photo called IMG_0042.CR2 at position `n`.
    private func example(_ n: Int) -> String {
        var out = naming.isEmpty ? "{name}" : naming
        let d = DateFormatter(); d.dateFormat = "yyyyMMdd"
        let num = n + startNumber - 1
        for (tok, val) in [("{name}", "IMG_0042"), ("{num}", "0042"), ("{date}", d.string(from: Date())), ("{ext}", "CR2"), ("{rating}", "0")] { out = out.replacingOccurrences(of: tok, with: val) }
        if let r = out.range(of: "\\{seq:(\\d+)\\}", options: .regularExpression) { out.replaceSubrange(r, with: String(format: "%0\(Int(out[r].dropFirst(5).dropLast()) ?? 3)d", num)) }
        out = out.replacingOccurrences(of: "{seq}", with: String(format: "%03d", num)).replacingOccurrences(of: "{n}", with: String(format: "%03d", num))
        return out + "." + ["jpeg": "jpg", "png": "png", "tiff": "tif", "webp": "webp"][format, default: "jpg"]
    }
    private var resolvedSubfolder: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return subfolder.replacingOccurrences(of: "{date}", with: f.string(from: Date()))
            .components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-").trimmingCharacters(in: .whitespaces)
    }

    private func footer(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).frame(height: 52)
            .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
    }

    private func run() async {
        working = true; error = nil
        defer { working = false }
        // a chosen Files folder is written to directly (access held for the export); otherwise a temporary folder is shared
        let scoped = destination.map { $0.startAccessingSecurityScopedResource() } ?? false
        defer { if scoped { destination?.stopAccessingSecurityScopedResource() } }
        let dir = destination ?? FileManager.default.temporaryDirectory.appending(path: "RawLight-Export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var p: [String: Any] = ["ids": ids, "format": format, "quality": Int(quality), "longEdge": longEdge, "colorSpace": colorSpace,
                                "naming": naming, "startNumber": startNumber, "conflict": "unique", "dir": dir.path]
        if !resolvedSubfolder.isEmpty { p["subfolder"] = resolvedSubfolder }
        if watermarkOn && watermark.hasContent { p["watermark"] = watermark.params }
        func paths(_ r: Any) -> [URL] {
            (((r as? [String: Any])?["files"] as? [[String: Any]]) ?? []).compactMap { ($0["path"] as? String).map { URL(fileURLWithPath: $0) } }
        }
        do {
            if ids.contains(where: { AppleDenoise.level($0) > 0 }) {
                // photos with Apple noise reduction are exported one by one so each file is filtered at its own strength
                var out: [URL] = []
                for (i, id) in ids.enumerated() {
                    var q = p; q["ids"] = [id]; q["startNumber"] = startNumber + i
                    for url in paths(try await model.engine.execute("app.export", q)) {
                        AppleDenoise.apply(toFile: url, level: AppleDenoise.level(id), quality: quality)
                        out.append(url)
                    }
                }
                results = out
            } else {
                results = paths(try await model.engine.execute("app.export", p))
            }
            if results.isEmpty { error = "Nothing was exported" }
            else if destination != nil { savedMessage = "Saved \(results.count) file\(results.count == 1 ? "" : "s") to \(destination?.lastPathComponent ?? "Files")" }
        } catch { self.error = error.localizedDescription }
    }
}
