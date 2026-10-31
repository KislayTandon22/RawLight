import SwiftUI

/// Library and app settings: cache size, XMP sidecars, import copyright, Pencil, credits.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pencilOnly") private var pencilOnly = false
    @AppStorage("swipeGestures") private var swipeGestures = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("maskColor") private var maskColor = "auto"
    @AppStorage("segmenter") private var segmenter = "sam"
    @State private var denoiseModels: [[String: Any]] = []
    @State private var terms: (title: String, terms: String, sizeBytes: Int)?
    @State private var photos = 0
    @State private var albums = 0
    @State private var cacheBytes = 0
    @State private var cacheMb = 0
    @State private var autoWrite = false
    @State private var creator = ""
    @State private var copyright = ""
    @State private var message: String?

    private let cacheChoices = [(0, "Default"), (256, "256 MB"), (512, "512 MB"), (1024, "1 GB"), (2048, "2 GB")]

    var body: some View {
        NavigationStack {
            Form {
                Section("Library") {
                    LabeledContent("Name", value: model.currentLibrary?.name ?? "Library")
                    LabeledContent("Photos", value: "\(photos)")
                    LabeledContent("Albums", value: "\(albums)")
                    LabeledContent("Preview cache", value: ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))
                    Picker("Cache budget", selection: $cacheMb) { ForEach(cacheChoices, id: \.0) { Text($0.1).tag($0.0) } }
                        .onChange(of: cacheMb) { _, v in Task { _ = try? await model.engine.execute("library.preferences", ["cacheMb": v]) } }
                    Button("Optimise library") { Task { await optimise() } }
                }
                Section {
                    Toggle("Write edits to XMP sidecars", isOn: $autoWrite).tint(Theme.accent)
                        .onChange(of: autoWrite) { _, v in Task { _ = try? await model.engine.execute("library.xmpPreferences", ["autoWrite": v]) } }
                } header: { Text("Metadata") } footer: { Text("Saves a small .xmp file next to each original so other apps can read your edits.") }
                Section("Copyright on import") {
                    TextField("Creator", text: $creator).onSubmit { Task { await saveImport() } }
                    TextField("Copyright notice", text: $copyright).onSubmit { Task { await saveImport() } }
                }
                Section {
                    Picker("Appearance", selection: Binding(get: { ThemeStore.shared.appearance }, set: { ThemeStore.shared.appearance = $0 })) {
                        Text("Dark").tag("dark"); Text("Light").tag("light"); Text("System").tag("system")
                    }.pickerStyle(.segmented)
                    HStack(spacing: 14) {
                        Text("Accent")
                        Spacer()
                        ForEach(ThemeStore.accents, id: \.name) { a in
                            Button { ThemeStore.shared.accentName = a.name } label: {
                                Circle().fill(a.base).frame(width: 30, height: 30)
                                    .overlay(Circle().stroke(.white, lineWidth: ThemeStore.shared.accentName == a.name ? 3 : 0))
                                    .overlay(Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white).opacity(ThemeStore.shared.accentName == a.name ? 1 : 0))
                            }.buttonStyle(.plain).accessibilityLabel(a.label)
                        }
                    }
                } header: { Text("Theme") } footer: { Text("Dark suits editing best. The photo area stays dark in every theme.") }
                Section {
                    Picker("Overlay colour", selection: $maskColor) {
                        Text("Automatic (one per mask)").tag("auto")
                        ForEach(MaskPalette.colors, id: \.name) { c in
                            Label { Text(c.name) } icon: { Circle().fill(MaskPalette.color(for: MaskPalette.colors.firstIndex { $0.name == c.name }.map { $0 + 1 } ?? 1)) }.tag(c.name)
                        }
                    }
                } header: { Text("Masks") } footer: { Text("The tint shown over the area a mask affects. The default palette keeps masks apart for people with colour blindness; each mask also shows its colour in the list.") }
                Section {
                    Toggle("Swipe to rate, flag and move", isOn: $swipeGestures).tint(Theme.accent)
                    Toggle("Haptic feedback", isOn: $haptics).tint(Theme.accent)
                } header: { Text("Gestures") } footer: {
                    Text("In the editor: swipe left or right for the next or previous photo. Swipe up or down on the left half to change the rating, on the right half to pick or reject. A keyboard works too: 0–5, P, X, U and the arrow keys.")
                }
                Section("Apple Pencil") {
                    Toggle("Draw with Pencil only", isOn: $pencilOnly).tint(Theme.accent)
                    Text("Brush and Lasso: double-tap or squeeze switches erase, or include and exclude. Two-finger tap undoes, three-finger tap redoes. A resting palm is ignored.").font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Picker("Object and Lasso", selection: $segmenter) {
                        Text("MobileSAM (recommended)").tag("sam")
                        Text("Apple Vision only").tag("vision")
                    }
                    LabeledContent("Subject, Sky, Background", value: "Apple Vision")
                } header: { Text("Selection model") } footer: {
                    Text(MobileSAM.shared.available ? "MobileSAM (Apache-2.0, about 23 MB) is included in the app and follows edges best. Apple Vision is faster to start but picks whole people and groups." : "MobileSAM is not in this build, so Apple Vision is used.")
                }
                Section {
                    if denoiseModels.isEmpty { Text("No denoise model yet.").foregroundStyle(.secondary) }
                    ForEach(denoiseModels.indices, id: \.self) { i in
                        let m = denoiseModels[i]
                        let installed = m["installed"] as? Bool ?? false, selected = m["selected"] as? Bool ?? false
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m["name"] as? String ?? "Model").font(.body)
                                Text(modelSubtitle(m)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if installed {
                                if selected { Label("In use", systemImage: "checkmark.circle.fill").font(.footnote.weight(.semibold)).foregroundStyle(Theme.accent) }
                                else { Button("Use") { Task { await selectModel(m["id"] as? String) } }.buttonStyle(.bordered).tint(Theme.accent) }
                            } else if (m["known"] as? Bool) == true {
                                if let dl = model.denoiseDownload { ProgressView(value: dl.total > 0 ? Double(dl.bytes) / Double(dl.total) : nil).frame(width: 90).tint(Theme.accent) }
                                else { Button("Download") { Task { await askModelDownload() } }.buttonStyle(.borderedProminent).tint(Theme.accent) }
                            }
                        }
                        .swipeActions { if installed { Button("Remove", role: .destructive) { Task { await removeModel(m["id"] as? String) } } } }
                    }
                    if denoiseModels.contains(where: { ($0["selected"] as? Bool) == true }) {
                        Button("Switch AI denoise off") { Task { await selectModel(nil) } }
                    }
                } header: { Text("AI denoise model") } footer: {
                    Text("RawNIND (GPL-3.0) is not part of the app: it is downloaded only when you ask, after you see its licence. Swipe a model to remove it. To add another .onnx model, use Edit › Detail › Add a denoise model. Everything runs on this device and nothing is uploaded.")
                }
                Section("About") {
                    LabeledContent("RawLight", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("The raw engine is LightCraft by storytold, used under the MIT and Apache-2.0 licences. The interface is original. Interface font: Inter (SIL OFL). Subject selection by Apple Vision.").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Acknowledgements") { AcknowledgementsView() }
                    Link("Privacy policy", destination: URL(string: "https://github.com/KislayTandon22/RawLight/blob/main-rawlight/docs/appstore/privacy-policy.md")!)
                    Link("LightCraft on GitHub", destination: URL(string: "https://github.com/storytold/lightcraft")!)
                }
                if let message { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Task { await saveImport() }; dismiss() } } }
            .task { await load(); await loadModels() }
            .onChange(of: model.denoiseDownload == nil) { _, _ in Task { await loadModels() } }
            .alert(terms?.title ?? "", isPresented: Binding(get: { terms != nil }, set: { if !$0 { terms = nil } })) {
                Button("Cancel", role: .cancel) {}
                Button("Accept and download") { Task { await model.downloadDenoiseModel() } }
            } message: { Text(terms?.terms ?? "") }
        }
        .presentationBackground(.ultraThinMaterial).presentationCornerRadius(28)
    }

    private func load() async {
        if let i = try? await model.engine.execute("library.info") as? [String: Any] {
            photos = i["photos"] as? Int ?? 0; albums = i["albums"] as? Int ?? 0
            cacheBytes = (((i["cache"] as? [String: Any])?["disk"] as? [String: Any])?["bytes"] as? Int) ?? 0
        }
        if let p = try? await model.engine.execute("library.preferences") as? [String: Any] {
            cacheMb = p["cacheMb"] as? Int ?? 0
            let imp = p["import"] as? [String: Any]
            creator = imp?["creator"] as? String ?? ""; copyright = imp?["copyright"] as? String ?? ""
        }
        if let x = try? await model.engine.execute("library.xmpPreferences") as? [String: Any] { autoWrite = x["autoWrite"] as? Bool ?? false }
    }

    private func askModelDownload() async { terms = await model.denoiseTerms() }

    private func loadModels() async {
        let r = try? await model.engine.execute("denoise.models.list", [:]) as? [String: Any]
        denoiseModels = (r?["models"] as? [[String: Any]] ?? []).filter { ($0["installed"] as? Bool) == true || ($0["known"] as? Bool) == true }
    }
    private func selectModel(_ id: String?) async {
        _ = try? await model.engine.execute("denoise.models.select", ["id": id as Any? ?? NSNull()])
        await loadModels()
    }
    private func removeModel(_ id: String?) async {
        guard let id else { return }
        _ = try? await model.engine.execute("denoise.models.remove", ["id": id])
        await loadModels()
    }
    private func modelSubtitle(_ m: [String: Any]) -> String {
        var parts: [String] = []
        if let b = m["sizeBytes"] as? Int, b > 0 { parts.append(ByteCountFormatter.string(fromByteCount: Int64(b), countStyle: .file)) }
        if let l = (m["licence"] as? [String: Any])?["name"] as? String { parts.append(l) }
        parts.append((m["installed"] as? Bool) == true ? "Installed" : "Not installed")
        return parts.joined(separator: " · ")
    }

    private func saveImport() async {
        _ = try? await model.engine.execute("library.preferences", ["import": ["creator": creator, "copyright": copyright]])
    }

    private func optimise() async {
        do { _ = try await model.engine.execute("library.compact"); message = "Library optimised." } catch { message = error.localizedDescription }
        await load()
    }
}


/// Licences and credits for everything RawLight is built on.
struct AcknowledgementsView: View {
    private let items: [(String, String, String)] = [
        ("LightCraft", "MIT or Apache-2.0", "The raw engine and editing pipeline, by storytold. github.com/storytold/lightcraft"),
        ("MobileSAM", "Apache-2.0", "Tap and Lasso selection. Chaoning Zhang et al.; Core ML conversion by mlboydaisuke; prompt encoding after SamKit (Apache-2.0)."),
        ("Inter", "SIL Open Font License 1.1", "The interface font, by Rasmus Andersson."),
        ("Apple Vision and Core Image", "Part of iOS", "Subject, Sky and Background selection and Apple noise reduction."),
        ("RawNIND denoise model", "GPL-3.0", "Optional download, not part of the app. By Brummer and De Vleeschouwer; packaged by darktable-ai (github.com/darktable-org/darktable-ai). The model file stays under the GPL if you pass it on."),
    ]
    var body: some View {
        List(items, id: \.0) { it in
            VStack(alignment: .leading, spacing: 4) {
                Text(it.0).font(.headline)
                Text(it.1).font(.subheadline).foregroundStyle(Theme.accentSoft)
                Text(it.2).font(.footnote).foregroundStyle(.secondary)
            }.padding(.vertical, 4)
        }
        .navigationTitle("Acknowledgements").navigationBarTitleDisplayMode(.inline)
    }
}
