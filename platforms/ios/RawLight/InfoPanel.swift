import SwiftUI

/// Info mode: camera details, title / caption / copyright, GPS and keywords for the open photo.
struct InfoPanel: View {
    let engine: Engine
    let photoID: UInt64
    @State private var facts: [(String, String)] = []
    @State private var title = ""
    @State private var caption = ""
    @State private var creator = ""
    @State private var copyright = ""
    @State private var gps = ""
    @State private var keywords: [String] = []
    @State private var newKeyword = ""
    @State private var message: String?

    private let labels: [(key: String, name: String)] = [
        ("file_name", "File"), ("camera", "Camera"), ("lens", "Lens"), ("width", "Width"), ("height", "Height"),
        ("iso", "ISO"), ("aperture", "Aperture"), ("shutter", "Shutter"), ("focal_length", "Focal length"), ("captured", "Captured"), ("size", "Size"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !facts.isEmpty {
                VStack(spacing: 6) {
                    ForEach(facts, id: \.0) { f in
                        HStack(alignment: .firstTextBaseline) { Text(f.0).font(.subheadline).foregroundStyle(.secondary); Spacer(); Text(f.1).font(.subheadline).multilineTextAlignment(.trailing) }
                    }
                }
                .padding(14).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            group("Description") {
                field("Title", $title) { save(["title": title]) }
                field("Caption", $caption) { save(["caption": caption]) }
                field("Creator", $creator) { save(["creator": creator]) }
                field("Copyright", $copyright) { save(["copyright": copyright]) }
            }
            group("Location") {
                field("Latitude, longitude", $gps) { save(["gps": gps.trimmingCharacters(in: .whitespaces).isEmpty ? NSNull() : gps]) }
            }
            group("Keywords") {
                if !keywords.isEmpty {
                    FlowChips(items: keywords) { k in
                        Button { save(["removeKeywords": [k]]) } label: {
                            HStack(spacing: 4) { Text(k); Image(systemName: "xmark").font(.caption2.weight(.bold)) }
                                .font(.subheadline).padding(.horizontal, 12).frame(height: 34).fieldBackground(in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add keyword", text: $newKeyword).textInputAutocapitalization(.never).submitLabel(.done).onSubmit(addKeyword)
                        .accessibilityIdentifier("info.keyword")
                    Button("Add", action: addKeyword).buttonStyle(.borderedProminent).tint(Theme.accent).disabled(newKeyword.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal, 14).frame(height: 48).fieldBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.accentSoft) }
        }
        .task(id: photoID) { await load() }
    }

    private func group<C: View>(_ name: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(name).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary); content() }
    }

    private func field(_ placeholder: String, _ text: Binding<String>, commit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: text).submitLabel(.done).onSubmit(commit)
            .padding(.horizontal, 14).frame(height: 46).fieldBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func addKeyword() {
        let k = newKeyword.trimmingCharacters(in: .whitespaces)
        guard !k.isEmpty else { return }
        newKeyword = ""
        save(["addKeywords": [k]])
    }

    private func save(_ values: [String: Any]) {
        Task {
            var p = values; p["ids"] = [photoID]
            do { _ = try await engine.execute("photo.setMeta", p); message = nil } catch { message = error.localizedDescription }
            await load()
        }
    }

    private func load() async {
        guard let d = try? await engine.execute("photo.inspect", ["id": photoID]) as? [String: Any] else { return }
        facts = labels.compactMap { l in
            guard let v = d[l.key], !(v is NSNull) else { return nil }
            let s = "\(v)"
            return s.isEmpty ? nil : (l.name, s)
        }
        let meta = (d["meta"] as? [String: Any]) ?? d
        func str(_ k: String) -> String { (meta[k] as? String) ?? (d[k] as? String) ?? "" }
        title = str("title"); caption = str("caption"); creator = str("creator"); copyright = str("copyright")
        if let g = meta["gps"] as? [Double], g.count == 2 { gps = String(format: "%.5f, %.5f", g[0], g[1]) }
        else if let g = meta["gps"] as? [String: Any], let la = g["lat"] as? Double, let lo = g["lon"] as? Double { gps = String(format: "%.5f, %.5f", la, lo) }
        else { gps = "" }
        keywords = (meta["keywords"] as? [String]) ?? (d["keywords"] as? [String]) ?? []
    }
}

/// Chips that wrap onto as many lines as they need.
struct FlowChips<Item: Hashable, Chip: View>: View {
    let items: [Item]
    @ViewBuilder let chip: (Item) -> Chip
    var body: some View { FlowLayout(spacing: 8) { ForEach(items, id: \.self) { chip($0) } } }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 300).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, f) in arrange(subviews, width: bounds.width).frames.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxW: CGFloat = 0
        var frames: [CGRect] = []
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0, x + sz.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: sz))
            x += sz.width + spacing; rowH = max(rowH, sz.height); maxW = max(maxW, x - spacing)
        }
        return (frames, CGSize(width: maxW, height: y + rowH))
    }
}
