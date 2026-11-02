import SwiftUI

private let anchors: [[String]] = [["topLeft", "top", "topRight"], ["left", "center", "right"], ["bottomLeft", "bottom", "bottomRight"]]

@Observable @MainActor final class ExportModel {
    var format = "jpeg"
    var quality = 90.0
    var longEdge = 3000
    var colorSpace = "srgb"
    var useWatermark = true
    var text = "© RawLight"
    var anchor = "bottomRight"
    var size = 0.04
    var opacity = 0.8
    var inset = 0.03
    var white = true
    var shadow = true
    var folder: URL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first!.appending(path: "RawLight Exports", directoryHint: .isDirectory)
    var working = false
    var message: String?
    var preview: NSImage?

    func watermark() -> [String: Any] {
        ["text": text, "anchor": anchor, "size": size, "opacity": opacity, "insetX": inset, "insetY": inset,
         "color": white ? [255, 255, 255] : [0, 0, 0], "shadow": shadow]
    }

    func run(ids: [UInt64], engine: MacEngine) async {
        working = true; message = nil
        defer { working = false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var p: [String: Any] = ["ids": ids, "format": format, "quality": Int(quality), "longEdge": longEdge, "colorSpace": colorSpace]
        if useWatermark, !text.isEmpty { p["watermark"] = watermark() }
        let ext = ["jpeg": "jpg", "png": "png", "tiff": "tif", "webp": "webp"][format] ?? "jpg"
        if ids.count == 1 { p["path"] = folder.appending(path: "RawLight-\(ids[0]).\(ext)").path } else { p["dir"] = folder.path }
        do {
            let r = try await engine.execute("app.export", p)
            let files = ((r as? [String: Any])?["files"] as? [[String: Any]]) ?? []
            message = files.isEmpty ? "Nothing was exported" : "Exported \(files.count) file\(files.count == 1 ? "" : "s") to \(folder.path)"
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
            ex.preview = await lib.engine.render(id, maxEdge: 1800)?.image
        }
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
                    .overlay { if ex.useWatermark { WatermarkOverlay() } }
                    .aspectRatio(ar, contentMode: .fit)
                    .padding(24)
            } else { ProgressView() }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Approximates the engine's watermark placement so the preview moves as the settings do.
private struct WatermarkOverlay: View {
    @Environment(ExportModel.self) private var ex
    var body: some View {
        GeometryReader { g in
            let short = min(g.size.width, g.size.height)
            let a = ex.anchor
            let h: HorizontalAlignment = a.hasSuffix("Left") || a == "left" ? .leading : a.hasSuffix("Right") || a == "right" ? .trailing : .center
            let v: VerticalAlignment = a.hasPrefix("top") ? .top : a.hasPrefix("bottom") ? .bottom : .center
            Text(ex.text).font(.system(size: ex.size * short, weight: .semibold))
                .foregroundStyle((ex.white ? Color.white : Color.black).opacity(ex.opacity))
                .shadow(color: .black.opacity(ex.shadow ? 0.6 : 0), radius: 3)
                .padding(.horizontal, ex.inset * short).padding(.vertical, ex.inset * short)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: Alignment(horizontal: h, vertical: v))
        }
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
                    head("Watermark") { Toggle("", isOn: $e.useWatermark).labelsHidden().toggleStyle(.switch).tint(MacTheme.accent).controlSize(.small) }
                    if e.useWatermark {
                        row("Text") { TextField("", text: $e.text).textFieldStyle(.roundedBorder) }
                        row("Position") {
                            VStack(spacing: 3) {
                                ForEach(anchors, id: \.self) { r in
                                    HStack(spacing: 3) {
                                        ForEach(r, id: \.self) { a in
                                            RoundedRectangle(cornerRadius: 4).fill(e.anchor == a ? MacTheme.accent : Color.white.opacity(0.09))
                                                .frame(width: 34, height: 22).onTapGesture { e.anchor = a }
                                        }
                                    }
                                }
                            }
                            Spacer()
                        }
                        row("Size") { Slider(value: $e.size, in: 0.01...0.15).tint(MacTheme.accent); val(e.size) }
                        row("Opacity") { Slider(value: $e.opacity, in: 0.05...1).tint(MacTheme.accent); val(e.opacity) }
                        row("Margin") { Slider(value: $e.inset, in: 0...0.15).tint(MacTheme.accent); val(e.inset) }
                        row("Colour") { Picker("", selection: $e.white) { Text("White").tag(true); Text("Black").tag(false) }.labelsHidden().pickerStyle(.segmented) }
                        row("Shadow") { Toggle("", isOn: $e.shadow).labelsHidden().toggleStyle(.switch).tint(MacTheme.accent).controlSize(.small); Spacer() }
                    }
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
