import SwiftUI

/// Settings ▸ AI Denoise: RawNIND ships inside the app and is installed offline once its GPL-3.0 terms are accepted.
struct DenoiseSettings: View {
    @Environment(LibraryModel.self) private var lib
    @State private var installed = false
    @State private var inUse = false
    @State private var terms = ""
    @State private var asking = false
    @State private var message: String?

    static var bundled: URL? { Bundle.main.url(forResource: "rawnind", withExtension: "onnx") }

    var body: some View {
        Form {
            Text("AI noise reduction runs on this Mac and nothing is uploaded. The model comes with RawLight; accept its licence to turn it on.").font(.footnote).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RawNIND UtNet2 (Bayer)").font(.system(size: 13, weight: .semibold))
                    Text("Raw denoise · 30 MB · GPL-3.0").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if installed {
                    if inUse { Label("In use", systemImage: "checkmark.circle.fill").font(.caption) }
                    else { Button("Use") { Task { await select(true) } } }
                } else if Self.bundled != nil { Button("Install…") { Task { await ask() } } }
            }
            if inUse { Button("Switch AI denoise off") { Task { await select(false) } } }
            if let message { Text(message).font(.footnote).foregroundStyle(.red) }
        }
        .padding(20)
        .task { await refresh() }
        .alert("RawNIND UtNet2 (Bayer)", isPresented: $asking) {
            Button("Accept and install") { Task { await install() } }
            Button("Cancel", role: .cancel) {}
        } message: { Text(terms) }
    }

    private func row() async -> [String: Any]? {
        let r = try? await lib.engine.execute("denoise.models.list") as? [String: Any]
        return (r?["models"] as? [[String: Any]])?.first { ($0["id"] as? String) == "rawnind-bayer" }
    }
    private func refresh() async {
        let m = await row()
        installed = m?["installed"] as? Bool ?? false
        inUse = m?["selected"] as? Bool ?? false
    }
    private func ask() async {
        let m = await row()
        terms = ((m?["licence"] as? [String: Any])?["notice"] as? String) ?? "RawNIND's weights are published under the GNU General Public License v3."
        asking = true
    }
    private func install() async {
        guard let url = Self.bundled else { return }
        do { _ = try await lib.engine.execute("denoise.models.install", ["path": url.path, "acknowledged": true]); message = nil }
        catch { message = error.localizedDescription }
        await refresh()
    }
    private func select(_ on: Bool) async {
        _ = try? await lib.engine.execute("denoise.models.select", ["id": on ? "rawnind-bayer" : NSNull()])
        await refresh()
    }
}
