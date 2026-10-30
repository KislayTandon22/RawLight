import SwiftUI

struct ExportSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let photoID: UInt64
    @State private var format = "jpeg"
    @State private var quality = 90.0
    @State private var longEdge = 3000
    @State private var colorSpace = "srgb"
    @State private var working = false
    @State private var result: URL?
    @State private var error: String?

    private let sizes: [(String, Int)] = [("1600", 1600), ("3000", 3000), ("Full", 0)]

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Export").font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).background(.ultraThinMaterial, in: Circle()) }
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
            if let result {
                ShareLink(item: result) { footer("Share or Save", "square.and.arrow.up") }
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
        let url = FileManager.default.temporaryDirectory.appending(path: "RawLight-\(photoID).\(ext)")
        try? FileManager.default.removeItem(at: url)
        do {
            try await model.engine.execute("app.export", ["path": url.path, "ids": [photoID], "format": format, "quality": Int(quality),
                                                          "longEdge": longEdge, "colorSpace": colorSpace])
            result = url
        } catch { self.error = error.localizedDescription }
    }
}
