import SwiftUI

/// Merge the selected photos: HDR, panorama or HDR panorama, with a preview before the result is added.
struct MergeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let ids: [UInt64]
    @State private var kind = "merge.hdr"
    @State private var deghost = "none"
    @State private var projection = "auto"
    @State private var autoCrop = true
    @State private var align = true
    @State private var busy = false
    @State private var preview: UIImage?
    @State private var message: String?

    private var hasPanorama: Bool { kind != "merge.hdr" }
    private var hasHDR: Bool { kind != "merge.panorama" }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind) {
                        Text("HDR").tag("merge.hdr"); Text("Panorama").tag("merge.panorama"); Text("HDR panorama").tag("merge.hdrPanorama")
                    }.pickerStyle(.segmented)
                    Text("\(ids.count) photos selected").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Options") {
                    if hasHDR {
                        Toggle("Align images", isOn: $align).tint(Theme.accent)
                        Picker("Deghost", selection: $deghost) { ForEach(["none", "low", "medium", "high"], id: \.self) { Text($0.capitalized).tag($0) } }
                    }
                    if hasPanorama {
                        Picker("Projection", selection: $projection) { ForEach(["auto", "spherical", "cylindrical", "perspective"], id: \.self) { Text($0.capitalized).tag($0) } }
                        Toggle("Auto crop", isOn: $autoCrop).tint(Theme.accent)
                    }
                }
                if let preview { Section("Preview") { Image(uiImage: preview).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)) } }
                if let message { Section { Text(message).font(.footnote) } }
                Section {
                    Button { Task { await run(preview: true) } } label: { HStack { if busy { ProgressView() }; Text("Preview") } }.disabled(busy || ids.count < 2)
                        .accessibilityIdentifier("merge.preview")
                    Button { Task { await run(preview: false) } } label: { Text("Merge and add to library").fontWeight(.semibold) }.disabled(busy || ids.count < 2)
                        .accessibilityIdentifier("merge.run")
                }
            }
            .navigationTitle("Merge").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationBackground(.ultraThinMaterial).presentationCornerRadius(28)
    }

    private func run(preview wantPreview: Bool) async {
        busy = true; message = nil
        defer { busy = false }
        var p: [String: Any] = ["ids": ids]
        if hasHDR { p["align"] = align; p["deghost"] = deghost }
        if hasPanorama { p["projection"] = projection; p["autoCrop"] = autoCrop }
        let url = FileManager.default.temporaryDirectory.appending(path: "merge-preview.png")
        if wantPreview { p["preview"] = true; p["previewPath"] = url.path }
        do {
            _ = try await model.engine.execute(kind, p)
            if wantPreview { preview = UIImage(contentsOfFile: url.path) }
            else { await model.load(); model.importMessage = "Merged photo added"; dismiss() }
        } catch { message = error.localizedDescription }
    }
}
