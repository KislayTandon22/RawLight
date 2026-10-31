import SwiftUI
import UniformTypeIdentifiers

/// The Detail group: Sharpening, Noise Reduction (luminance and colour) and AI Denoise.
struct DetailPanel: View {
    let engine: Engine
    let photoID: UInt64
    let controls: [Control]
    let set: (String, Double, Bool) -> Void
    let onChange: () -> Void
    @Binding var appleLevel: Double
    let onApple: () -> Void

    private func slider(_ id: String, _ label: String? = nil) -> some View {
        Group {
            if let c = controls.first(where: { $0.id == id }) {
                let shown = label.map { Control(id: c.id, label: $0, section: c.section, min: c.min, max: c.max, def: c.def, value: c.value, step: c.step, decimals: c.decimals, track: c.track) } ?? c
                ColorSlider(control: shown, onChange: { set(id, $0, false) }, onEnd: { v in set(id, v, true) }, reset: { set(id, c.def, true) }, compact: true)
            }
        }
    }

    private func section(_ title: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).padding(.horizontal, 6).padding(.top, 4)
            content()
        }
        .padding(8).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    var body: some View {
        VStack(spacing: 10) {
            section("Sharpening") {
                slider("detail.sharpenAmount", "Amount"); slider("detail.sharpenRadius", "Radius")
                slider("detail.sharpenDetail", "Detail"); slider("detail.sharpenMasking", "Masking")
            }
            section("Noise reduction") {
                slider("detail.nrLuminance", "Luminance"); slider("detail.nrDetail", "Detail"); slider("detail.nrContrast", "Contrast")
                Divider().opacity(0.3).padding(.vertical, 2)
                slider("detail.nrColor", "Colour"); slider("detail.nrColorDetail", "Colour detail"); slider("detail.nrColorSmoothness", "Smoothness")
            }
            section("Apple noise reduction") {
                HStack {
                    Text("Strength").font(.subheadline)
                    Slider(value: $appleLevel, in: 0...100, step: 1) { editing in if !editing { onApple() } }.tint(Theme.accent)
                    Text("\(Int(appleLevel))").font(.subheadline).monospacedDigit().frame(width: 34, alignment: .trailing)
                }
                .padding(.horizontal, 6)
                Text("Core Image filtering on the device, applied to the preview and to JPEG and PNG exports. It is not an AI model.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 6).padding(.bottom, 4)
            }
            AIDenoiseCard(engine: engine, photoID: photoID, amount: controls.first { $0.id == "enhance.denoise" }, set: set, onChange: onChange)
        }
    }
}

/// AI Denoise runs on this device with a model the user installs (none ships with the app).
struct AIDenoiseCard: View {
    let engine: Engine
    let photoID: UInt64
    let amount: Control?
    let set: (String, Double, Bool) -> Void
    let onChange: () -> Void
    @State private var status: [String: Any] = [:]
    @State private var enabled = false
    @State private var showImporter = false
    @State private var pending: PendingModel?
    @State private var message: String?
    @State private var generation = -1
    @Environment(AppModel.self) private var app

    struct PendingModel: Identifiable { let id = UUID(); let path: String; let title: String; let terms: String }

    private var model: String? {
        if let m = status["model"] as? [String: Any] { return (m["name"] as? String) ?? (m["id"] as? String) }
        return status["model"] as? String
    }
    private var photoState: String { ((status["photo"] as? [String: Any])?["state"] as? String) ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI Denoise", systemImage: "wand.and.sparkles").font(.subheadline.weight(.semibold))
                Spacer()
                if model != nil { Toggle("", isOn: Binding(get: { enabled }, set: { v in Task { await toggle(v) } })).labelsHidden().tint(Theme.accent) }
            }
            Text("Runs on this iPad with a denoise model. RAW photos only.").font(.footnote).foregroundStyle(.secondary)
            if model == nil {
                if let dl = app.denoiseDownload {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: dl.total > 0 ? Double(dl.bytes) / Double(dl.total) : nil).tint(Theme.accent)
                        Text(dl.total > 0 ? "Downloading… \(ByteCountFormatter.string(fromByteCount: Int64(dl.bytes), countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: Int64(dl.total), countStyle: .file))" : "Starting download…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Button { Task { await askDownload() } } label: {
                        Text("Download AI denoise model").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 44)
                            .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                    }.buttonStyle(.plain)
                    Text("RawNIND, about 58 MB. You see its licence first.").font(.caption).foregroundStyle(.secondary)
                }
                if let e = app.denoiseDownloadError { Text(e).font(.footnote).foregroundStyle(Theme.accentSoft) }
                Button { showImporter = true } label: {
                    Text("Add a denoise model…").font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).frame(height: 44).fieldBackground(in: Capsule())
                }.buttonStyle(.plain)
                Text("Or choose another .onnx file and its denoise-model.json from Files.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Model: \(model ?? "")").font(.footnote).foregroundStyle(.secondary)
                if enabled, let amount {
                    ColorSlider(control: amount, onChange: { set(amount.id, $0, false) }, onEnd: { v in set(amount.id, v, true) }, reset: { set(amount.id, amount.def, true) }, compact: true)
                }
                Text(stateText).font(.footnote).foregroundStyle(photoState == "failed" ? Theme.accentSoft : .secondary)
                Button("Remove model", role: .destructive) { Task { await removeModel() } }.font(.footnote)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.accentSoft) }
        }
        .padding(12).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { Task { await inspect(urls) } }
        }
        .sheet(item: $pending) { p in
            VStack(spacing: 14) {
                Text(p.title).font(.title3.weight(.semibold))
                ScrollView { Text(p.terms).font(.footnote).frame(maxWidth: .infinity, alignment: .leading) }
                Text("Install only if you accept this model's terms.").font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Cancel") { pending = nil }.buttonStyle(.bordered).tint(.gray)
                    Button { let path = p.path; pending = nil; Task { if path.isEmpty { await app.downloadDenoiseModel() } else { await install(path) } } } label: {
                        Text(p.path.isEmpty ? "Accept and download" : "Accept and install").font(.headline).frame(maxWidth: .infinity).frame(height: 48).background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                    }
                }
            }
            .padding(20).presentationDetents([.medium]).presentationBackground(.ultraThinMaterial)
        }
        .task(id: photoID) { await poll() }
    }

    private var stateText: String {
        switch photoState {
        case "notApplicable": return "AI Denoise works on RAW photos; this one isn't."
        case "ready": return "Denoised version is ready."
        case "queued": return "Waiting to denoise…"
        case "running":
            if let r = status["running"] as? [String: Any], let d = (r["done"] as? NSNumber)?.intValue, let t = (r["total"] as? NSNumber)?.intValue, t > 0 { return "Denoising… \(d * 100 / t)%" }
            return "Denoising…"
        case "failed": return "Denoise failed for this photo."
        case "noModel": return "No model selected."
        default: return enabled ? "Turn the amount up to see the effect." : "Off."
        }
    }

    /// Keeps the engine's denoise work moving while this card is visible and refreshes the photo when a result arrives.
    private func poll() async {
        while !Task.isCancelled {
            status = ((try? await engine.execute("denoise.status", ["id": photoID])) as? [String: Any]) ?? [:]
            enabled = (status["enabled"] as? Bool) ?? false
            let busy = photoState == "queued" || photoState == "running"
            if enabled || busy { _ = try? await engine.execute("denoise.pump", ["pace": "normal"]) }
            if let g = (status["generation"] as? NSNumber)?.intValue, g != generation { if generation >= 0 { onChange() }; generation = g }
            try? await Task.sleep(for: .milliseconds(busy ? 700 : 1800))
        }
    }

    private func toggle(_ on: Bool) async {
        do { _ = try await engine.execute("denoise.toggle", ["id": photoID, "enabled": on]); message = nil } catch { message = error.localizedDescription }
        status = ((try? await engine.execute("denoise.status", ["id": photoID])) as? [String: Any]) ?? status
        enabled = (status["enabled"] as? Bool) ?? on
        onChange()
    }

    /// Copies the chosen files together (the manifest must sit beside the .onnx) and shows the model's terms.
    private func inspect(_ urls: [URL]) async {
        let dir = FileManager.default.temporaryDirectory.appending(path: "DenoiseModel-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var onnx: URL?
        for u in urls {
            guard u.startAccessingSecurityScopedResource() else { continue }
            defer { u.stopAccessingSecurityScopedResource() }
            let dst = dir.appending(path: u.lastPathComponent)
            try? FileManager.default.copyItem(at: u, to: dst)
            if dst.pathExtension.lowercased() == "onnx" || dst.pathExtension.lowercased() == "dtmodel" { onnx = dst }
        }
        guard let onnx else { message = "Choose the model's .onnx file (and its denoise-model.json)."; return }
        do {
            let r = try await engine.execute("denoise.models.inspect", ["path": onnx.path]) as? [String: Any] ?? [:]
            let lic = r["licence"] as? [String: Any]
            let terms = [r["name"].map { "Model: \($0)" }, lic?["name"].map { "Licence: \($0)" }, lic?["notice"].map { "\($0)" },
                         r["provenance"].map { "Source: \($0)" }].compactMap { $0 }.joined(separator: "\n\n")
            pending = PendingModel(path: onnx.path, title: (r["name"] as? String) ?? "Denoise model", terms: terms.isEmpty ? "\(r)" : terms)
        } catch { message = error.localizedDescription }
    }

    private func askDownload() async {
        guard let t = await app.denoiseTerms() else { message = "No downloadable denoise model in this build."; return }
        pending = PendingModel(path: "", title: t.title, terms: t.terms)
    }

    private func install(_ path: String) async {
        do {
            _ = try await engine.execute("denoise.models.install", ["path": path, "acknowledged": true, "activate": true])
            message = "Model installed."
        } catch { message = error.localizedDescription }
        status = ((try? await engine.execute("denoise.status", ["id": photoID])) as? [String: Any]) ?? status
    }

    private func removeModel() async {
        guard let m = model else { return }
        _ = try? await engine.execute("denoise.models.remove", ["id": m])
        enabled = false
        status = ((try? await engine.execute("denoise.status", ["id": photoID])) as? [String: Any]) ?? [:]
        onChange()
    }
}
