import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 120), spacing: 6)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(model.photoIDs, id: \.self) { id in
                    Button { model.openPhoto = id } label: {
                        Color(white: 0.12)
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if let img = model.thumbs[id] {
                                    Image(uiImage: img).resizable().scaledToFill()
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .task { await model.thumbnail(id) }
                }
            }
            .padding(8)
            .padding(.bottom, 80)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("All Photos").font(.headline)
                Spacer()
                Text("\(model.photoIDs.count) photos").font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 20).frame(height: 60)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 8)
        }
    }
}
