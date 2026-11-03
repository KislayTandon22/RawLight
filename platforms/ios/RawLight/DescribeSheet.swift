import SwiftUI

/// Pick a word from the list; the mask is whatever that word names in the photo.
struct DescribeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let onPick: (Int, String) -> Void

    private var matches: [(Int, String)] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let all = Array(TextMask.shared.phrases.enumerated())
        return (q.isEmpty ? all : all.filter { $0.element.lowercased().contains(q) }).map { ($0.offset, $0.element) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Mask by word").font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).panelBackground(in: Circle()) }
            }
            TextField("Search words (dog, car, wheel…)", text: $query)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(12).background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            Text("Works best for things you can point at. Trees, mountains and water are not found reliably; use Sky or Background for those.")
                .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                    ForEach(matches, id: \.0) { m in
                        Button { onPick(m.0, m.1); dismiss() } label: {
                            Text(m.1).font(.subheadline.weight(.medium)).lineLimit(1).frame(maxWidth: .infinity).frame(height: 44)
                                .background(Color.white.opacity(0.1), in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }
                if matches.isEmpty { Text("No word like that yet.").foregroundStyle(.secondary).padding(.top, 20) }
            }
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationBackground(.ultraThinMaterial)
        .presentationCornerRadius(28)
    }
}
