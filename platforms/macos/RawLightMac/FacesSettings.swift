import SwiftUI

/// Settings ▸ Faces: the two small face models ship inside the app and install offline once their terms are accepted.
struct FacesSettings: View {
    @Environment(LibraryModel.self) private var lib
    struct Row: Identifiable { let id: String, name: String, role: String, bytes: Int, installed: Bool, licence: String, notice: String }
    @State private var rows: [Row] = []
    @State private var asking: Row?
    @State private var message: String?

    static func bundled(_ id: String) -> URL? {
        let file = ["yunet-2023mar": "yunet", "sface-2021dec": "sface"][id]
        return file.flatMap { Bundle.main.url(forResource: $0, withExtension: "onnx") }
    }

    var body: some View {
        Form {
            Text("Faces are found and matched on this Mac. The two small models come with RawLight; accept each model's terms to turn it on.").font(.footnote).foregroundStyle(.secondary)
            ForEach(rows.filter { Self.bundled($0.id) != nil }) { r in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.name).font(.system(size: 13, weight: .semibold))
                        Text("\(r.role.capitalized) · \(ByteCountFormatter.string(fromByteCount: Int64(r.bytes), countStyle: .file)) · \(r.licence)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if r.installed { Label("Installed", systemImage: "checkmark.circle.fill").font(.caption) }
                    else { Button("Install…") { asking = r } }
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(.red) }
        }
        .padding(20)
        .task { await refresh() }
        .alert(asking?.name ?? "", isPresented: Binding(get: { asking != nil }, set: { if !$0 { asking = nil } }), presenting: asking) { r in
            Button("Accept and install") { Task { await install(r) } }
            Button("Cancel", role: .cancel) {}
        } message: { r in Text(r.notice) }
    }

    private func refresh() async {
        guard let d = try? await lib.engine.execute("faces.models.list") as? [String: Any], let arr = d["models"] as? [[String: Any]] else { return }
        rows = arr.compactMap { m in
            guard let id = m["id"] as? String else { return nil }
            let lic = m["licence"] as? [String: Any]
            return Row(id: id, name: m["name"] as? String ?? id, role: m["role"] as? String ?? "", bytes: (m["sizeBytes"] as? NSNumber)?.intValue ?? 0,
                       installed: m["installed"] as? Bool ?? false, licence: lic?["name"] as? String ?? "", notice: lic?["notice"] as? String ?? "")
        }
    }

    private func install(_ r: Row) async {
        guard let url = Self.bundled(r.id) else { return }
        do { _ = try await lib.engine.execute("faces.models.install", ["path": url.path, "acknowledged": true, "activate": !r.role.lowercased().contains("detect")]); message = nil }
        catch { message = error.localizedDescription }
        await refresh()
    }
}
