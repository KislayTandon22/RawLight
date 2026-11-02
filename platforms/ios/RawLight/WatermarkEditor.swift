import SwiftUI
import UniformTypeIdentifiers

/// The watermark editor opened from Export: a live preview on the first photo, text or graphic, a 3 x 3 position grid,
/// size, opacity, colour, a frame and a box behind it, and saved watermarks with Import and Export of a shareable file.
struct WatermarkEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var watermark: Watermark
    let photoID: UInt64?
    /// The short edge the export will have, so the preview scales the watermark as the file will.
    let exportShortEdge: Int

    @State private var store = WatermarkStore.shared
    @State private var preview: UIImage?
    @State private var saveName = ""
    @State private var message: String?
    @State private var pickingLogo = false
    @State private var importing = false
    @State private var shareURL: URL?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                previewCard
                card("Style") { styleControls }
                card("Position") { positionControls }
                card("Look") { lookControls }
                card("Frame and box") { frameControls }
                card("Saved watermarks") { savedControls }
                if let message { Text(message).font(.footnote).foregroundStyle(Theme.accentSoft).frame(maxWidth: .infinity, alignment: .leading) }
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
        .task(id: watermark.params.description) { await refreshPreview() }
        .fileImporter(isPresented: $pickingLogo, allowedContentTypes: [.png, .jpeg]) { result in
            if case .success(let url) = result { useLogo(url) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { Task { await importFile(url) } }
        }
    }

    // MARK: pieces

    private var header: some View {
        HStack {
            Text("Watermark").font(.title2.weight(.semibold))
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).panelBackground(in: Circle()) }
        }
    }

    private var previewCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.35))
            if let preview {
                Image(uiImage: preview).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)).padding(6)
            } else {
                Text(photoID == nil ? "Select a photo to preview" : (watermark.hasContent ? "Rendering…" : "Add text or a graphic"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .frame(height: 260)
    }

    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased()).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(in: RoundedRectangle(cornerRadius: 18))
    }

    private var styleControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Style", selection: Binding(get: { watermark.isGraphic }, set: { graphic in
                if graphic { pickingLogo = true } else { watermark.imagePath = "" }
            })) { Text("Text").tag(false); Text("Graphic").tag(true) }.pickerStyle(.segmented)
            if watermark.isGraphic {
                HStack {
                    Text(URL(fileURLWithPath: watermark.imagePath).lastPathComponent).lineLimit(1).foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…") { pickingLogo = true }.tint(Theme.accent)
                }
                slider("Width", $watermark.imageWidth, 0.02...1, percent: true)
            } else {
                TextField("© Your name", text: $watermark.text, axis: .vertical).lineLimit(1...3)
                    .padding(10).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Toggle("Vertical lettering", isOn: $watermark.vertical).tint(Theme.accent)
                slider("Size", $watermark.size, 0.01...0.15, percent: true)
            }
        }
    }

    private var positionControls: some View {
        HStack(alignment: .top, spacing: 18) {
            let columns = Array(repeating: GridItem(.fixed(52), spacing: 6), count: 3)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Watermark.Anchor.allCases) { a in
                    Button { watermark.anchor = a } label: {
                        Image(systemName: a.symbol).font(.system(size: a == .center ? 8 : 16, weight: .semibold))
                            .frame(width: 52, height: 44)
                            .background(watermark.anchor == a ? Theme.accent : Color.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(watermark.anchor == a ? Color.white : Color.primary)
                    }
                    .accessibilityLabel(a.label)
                    .accessibilityAddTraits(watermark.anchor == a ? .isSelected : [])
                }
            }
            .fixedSize()
            VStack(spacing: 10) {
                slider("Across", $watermark.insetX, 0...0.4, percent: true, enabled: ![.top, .center, .bottom].contains(watermark.anchor))
                slider("Down", $watermark.insetY, 0...0.4, percent: true, enabled: ![.left, .center, .right].contains(watermark.anchor))
                Picker("Rotate", selection: $watermark.rotation) {
                    ForEach([0, 90, 180, 270], id: \.self) { Text("\($0)°").tag($0) }
                }.pickerStyle(.segmented)
            }
        }
    }

    private var lookControls: some View {
        VStack(spacing: 10) {
            slider("Opacity", $watermark.opacity, 0.05...1, percent: true)
            if !watermark.isGraphic {
                ColorPicker("Colour", selection: $watermark.color, supportsOpacity: false)
                Toggle("Shadow", isOn: $watermark.shadow).tint(Theme.accent)
            }
        }
    }

    private var frameControls: some View {
        VStack(spacing: 10) {
            slider("Border", $watermark.borderWidth, 0...0.05, percent: true)
            if watermark.borderWidth > 0 { ColorPicker("Border colour", selection: $watermark.borderColor, supportsOpacity: false) }
            slider("Box", $watermark.backgroundOpacity, 0...1, percent: true)
            if watermark.backgroundOpacity > 0 { ColorPicker("Box colour", selection: $watermark.backgroundColor, supportsOpacity: false) }
            if watermark.borderWidth > 0 || watermark.backgroundOpacity > 0 {
                slider("Padding", $watermark.padding, 0...0.1, percent: true)
                slider("Corners", $watermark.radius, 0...0.05, percent: true)
            }
        }
    }

    private var savedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            if store.names.isEmpty {
                Text("Nothing saved yet.").font(.footnote).foregroundStyle(.secondary)
            } else {
                FlowChips(items: store.names) { name in
                    HStack(spacing: 6) {
                        Button(name) { Task { await load(name) } }
                        Button { store.delete(name) } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .accessibilityLabel("Delete \(name)")
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8).background(Color.white.opacity(0.1), in: Capsule())
                }
            }
            HStack {
                TextField("Name", text: $saveName).padding(10).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                Button("Save current") { Task { await save() } }.buttonStyle(.borderedProminent).tint(Theme.accent).disabled(!watermark.hasContent)
            }
            HStack {
                Button { importing = true } label: { Label("Import…", systemImage: "square.and.arrow.down") }
                Spacer()
                if let shareURL {
                    ShareLink(item: shareURL) { Label("Share file", systemImage: "square.and.arrow.up") }
                } else {
                    Button { Task { await prepareShare() } } label: { Label("Export file…", systemImage: "square.and.arrow.up") }
                        .disabled(!watermark.hasContent)
                }
            }
            .tint(Theme.accent)
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, percent: Bool, enabled: Bool = true) -> some View {
        HStack {
            Text(title).frame(width: 64, alignment: .leading).foregroundStyle(enabled ? .primary : .secondary)
            Slider(value: value, in: range).tint(Theme.accent).disabled(!enabled)
            Text(String(format: "%.1f%%", value.wrappedValue * 100)).monospacedDigit().font(.footnote).frame(width: 52, alignment: .trailing)
        }
    }

    // MARK: actions

    private func refreshPreview() async {
        shareURL = nil
        guard let photoID, watermark.hasContent else { preview = nil; return }
        try? await Task.sleep(for: .milliseconds(150))
        if Task.isCancelled { return }
        let img = await model.engine.renderWatermarked(photoID, maxEdge: 900, watermark: watermark.params, exportShortEdge: exportShortEdge)
        if !Task.isCancelled { preview = img }
    }

    private func useLogo(_ url: URL) {
        do {
            watermark.imagePath = try WatermarkStore.copyLogo(from: url)
            message = nil
        } catch { message = "Couldn't open that picture: \(error.localizedDescription)" }
    }

    private func save() async {
        do {
            try await store.save(watermark, as: saveName.isEmpty ? "Watermark" : saveName, engine: model.engine)
            message = "Saved “\(saveName.isEmpty ? "Watermark" : saveName)”"
            saveName = ""
        } catch { message = error.localizedDescription }
    }

    private func load(_ name: String) async {
        do { watermark = try await store.load(name, engine: model.engine); message = nil } catch { message = error.localizedDescription }
    }

    private func importFile(_ url: URL) async {
        do {
            let r = try await store.importFile(url, engine: model.engine)
            watermark = r.watermark
            message = "Imported “\(r.name)”"
        } catch { message = error.localizedDescription }
    }

    private func prepareShare() async {
        do {
            let name = saveName.isEmpty ? "Watermark" : saveName
            let json = try await model.engine.watermarkFile(watermark.params, name: name)
            let url = FileManager.default.temporaryDirectory.appending(path: "\(name).json")
            try json.write(to: url, atomically: true, encoding: .utf8)
            shareURL = url
        } catch { message = error.localizedDescription }
    }
}
