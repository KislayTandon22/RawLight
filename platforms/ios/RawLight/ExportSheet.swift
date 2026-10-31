import SwiftUI

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
            if let error { Text(error).font(.footnote).foregroundStyle(Theme.accentSoft) }
            Spacer()
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
    }

    private func footer(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon).font(.headline).frame(maxWidth: .infinity).frame(height: 52)
            .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
    }

    private func run() async {
        working = true; error = nil
        defer { working = false }
        let ext = ["jpeg": "jpg", "png": "png", "tiff": "tif", "webp": "webp"][format] ?? "jpg"
        let dir = FileManager.default.temporaryDirectory.appending(path: "RawLight-Export-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var p: [String: Any] = ["ids": ids, "format": format, "quality": Int(quality), "longEdge": longEdge, "colorSpace": colorSpace]
        do {
            if ids.contains(where: { AppleDenoise.level($0) > 0 }) {
                // photos with Apple noise reduction are exported one by one so each file is filtered at its own strength
                var out: [URL] = []
                for id in ids {
                    var q = p; q["ids"] = [id]; q["path"] = dir.appending(path: "RawLight-\(id).\(ext)").path
                    let r = try await model.engine.execute("app.export", q)
                    for f in ((r as? [String: Any])?["files"] as? [[String: Any]]) ?? [] {
                        guard let path = f["path"] as? String else { continue }
                        let url = URL(fileURLWithPath: path)
                        AppleDenoise.apply(toFile: url, level: AppleDenoise.level(id), quality: quality)
                        out.append(url)
                    }
                }
                results = out
            } else {
                if ids.count == 1 { p["path"] = dir.appending(path: "RawLight-\(ids[0]).\(ext)").path } else { p["dir"] = dir.path }
                let r = try await model.engine.execute("app.export", p)
                let files = ((r as? [String: Any])?["files"] as? [[String: Any]]) ?? []
                results = files.compactMap { ($0["path"] as? String).map { URL(fileURLWithPath: $0) } }
            }
            if results.isEmpty { error = "Nothing was exported" }
        } catch { self.error = error.localizedDescription }
    }
}
