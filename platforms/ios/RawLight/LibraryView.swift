import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var showFiles = false
    @State private var picked: [PhotosPickerItem] = []
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
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.folder, .image, .rawImage, .data], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { Task { await model.importURLs(urls) } }
        }
        .overlay(alignment: .bottom) {
            if let m = model.importMessage {
                Text(m).font(.subheadline).padding(.horizontal, 16).frame(height: 44)
                    .background(.ultraThinMaterial, in: Capsule()).padding(.bottom, 24)
                    .task { try? await Task.sleep(for: .seconds(4)); model.importMessage = nil }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text("All Photos").font(.headline)
                Spacer()
                Text("\(model.photoIDs.count) photos").font(.subheadline).foregroundStyle(.secondary)
                if model.importing { ProgressView() }
                Menu {
                    Button { showFiles = true } label: { Label("Folder or Files…", systemImage: "folder") }
                } label: {
                    Image(systemName: "folder.badge.plus").font(.title3).frame(width: 44, height: 44)
                }
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
                    Label("Import", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16).frame(height: 44)
                        .background(Color(red: 0.04, green: 0.52, blue: 1), in: Capsule())
                        .foregroundStyle(.white)
                }
                .onChange(of: picked) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await model.importPicked(items); picked = [] }
                }
            }
            .padding(.horizontal, 20).frame(height: 60)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 8)
        }
    }
}
