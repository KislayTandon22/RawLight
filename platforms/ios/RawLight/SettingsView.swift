import SwiftUI

/// Library and app settings: cache size, XMP sidecars, import copyright, Pencil, credits.
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage("pencilOnly") private var pencilOnly = false
    @AppStorage("swipeGestures") private var swipeGestures = true
    @AppStorage("haptics") private var haptics = true
    @AppStorage("maskColor") private var maskColor = "auto"
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
                    Text("Everything runs on this device and nothing is uploaded. AI Denoise (RawNIND, GPL-3.0) and the Object and Lasso masks (MobileSAM, Apache-2.0) are included in the app. Subject, Sky and Background use Apple Vision.").font(.footnote).foregroundStyle(.secondary)
                } header: { Text("On-device AI") }
                Section("About") {
                    LabeledContent("RawLight", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                    Text("The raw engine is LightCraft by storytold, used under the MIT and Apache-2.0 licences. The interface is original. Interface font: Inter (SIL OFL). Subject selection by Apple Vision.").font(.footnote).foregroundStyle(.secondary)
                    Link("LightCraft on GitHub", destination: URL(string: "https://github.com/storytold/lightcraft")!)
                }
                if let message { Section { Text(message).font(.footnote) } }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { Task { await saveImport() }; dismiss() } } }
            .task { await load() }
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

    private func saveImport() async {
        _ = try? await model.engine.execute("library.preferences", ["import": ["creator": creator, "copyright": copyright]])
    }

    private func optimise() async {
        do { _ = try await model.engine.execute("library.compact"); message = "Library optimised." } catch { message = error.localizedDescription }
        await load()
    }
}
