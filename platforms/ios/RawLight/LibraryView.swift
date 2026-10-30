import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var picked: [PhotosPickerItem] = []
    @State private var showFiles = false
    @State private var showFilters = false
    @State private var showLibraries = false
    @State private var newAlbum = ""
    @State private var askAlbum = false
    @State private var exporting = false

    var body: some View {
        @Bindable var m = model
        ScrollView {
            if model.photoIDs.isEmpty { emptyState } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: model.gridSize), spacing: 6)], spacing: 6) {
                    ForEach(model.photoIDs, id: \.self) { id in tile(id) }
                }
                .padding(8).padding(.bottom, 90)
            }
        }
        .safeAreaInset(edge: .top) { topBar }
        .overlay(alignment: .bottom) { bottomBar }
        .overlay(alignment: .bottom) {
            if let msg = model.importMessage {
                Text(msg).font(.subheadline).padding(.horizontal, 16).frame(height: 44).panelBackground(in: Capsule()).padding(.bottom, 100)
                    .task { try? await Task.sleep(for: .seconds(4)); model.importMessage = nil }
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.folder, .image, .rawImage, .data], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { Task { await model.importURLs(urls) } }
        }
        .sheet(isPresented: $exporting) { ExportSheet(ids: Array(model.selection)) }
        .sheet(isPresented: $showFilters) { FilterSheet().presentationDetents([.medium]) }
        .sheet(isPresented: $showLibraries) { LibrariesSheet() }
        .alert("New album", isPresented: $askAlbum) {
            TextField("Name", text: $newAlbum)
            Button("Create") { let n = newAlbum; newAlbum = ""; Task { await model.createAlbum(n) } }
            Button("Cancel", role: .cancel) { newAlbum = "" }
        }
    }

    // MARK: top bar

    private var topBar: some View {
        @Bindable var m = model
        return HStack(spacing: 6) {
            Menu {
                Section("Library") {
                    Button { Task { await model.setSource(.all, label: "All Photos") } } label: { Label("All Photos", systemImage: "photo.on.rectangle") }
                    Button { Task { await model.setSource(.recentlyAdded, label: "Recently Added") } } label: { Label("Recently Added", systemImage: "clock") }
                    Button { Task { await model.setSource(.picks, label: "Picks") } } label: { Label("Picks", systemImage: "flag") }
                    Button { Task { await model.setSource(.recentlyDeleted, label: "Recently Deleted") } } label: { Label("Recently Deleted", systemImage: "trash") }
                }
                if !model.albums.isEmpty { Menu("Albums") { albumItems(model.albums) } }
                Divider()
                Button { showLibraries = true } label: { Label("Libraries…", systemImage: "externaldrive") }
            } label: {
                HStack(spacing: 4) { Text(model.sourceLabel).font(.headline).lineLimit(1); Image(systemName: "chevron.down").font(.caption.weight(.bold)) }
                    .padding(.horizontal, 12).frame(height: 44)
            }
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search", text: $m.search).submitLabel(.search).autocorrectionDisabled()
                    .onSubmit { Task { await model.applyFilters() } }
                if !model.search.isEmpty { Button { Task { await model.clearFilters() } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) } }
            }
            .padding(.horizontal, 12).frame(height: 40).fieldBackground(in: Capsule()).frame(minWidth: 120)
            Menu {
                ForEach([("captureDate", false, "Newest first"), ("captureDate", true, "Oldest first"), ("importDate", false, "Import date"),
                         ("editDate", false, "Edit date"), ("fileName", true, "File name"), ("rating", false, "Rating"), ("fileSize", false, "File size")], id: \.2) { s in
                    Button { model.sortKey = s.0; model.ascending = s.1; Task { await model.applySort() } } label: {
                        if model.sortLabel == s.2 { Label(s.2, systemImage: "checkmark") } else { Text(s.2) }
                    }
                }
            } label: { icon("arrow.up.arrow.down") }
            Button { showFilters = true } label: {
                Label("Filter", systemImage: "line.3.horizontal.decrease").labelStyle(.titleAndIcon).font(.subheadline.weight(.medium))
                    .padding(.horizontal, 12).frame(height: 40)
                    .fieldBackground(model.filtersActive, in: Capsule()).foregroundStyle(model.filtersActive ? .white : .primary)
            }
            Button { model.selecting.toggle(); if !model.selecting { model.selection = [] } } label: {
                Text(model.selecting ? "Done" : "Select").font(.subheadline.weight(.medium)).padding(.horizontal, 12).frame(height: 40)
                    .fieldBackground(model.selecting, in: Capsule())
            }
            Menu {
                Button { showFiles = true } label: { Label("Folder or Files…", systemImage: "folder") }
                PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) { Label("From Photos…", systemImage: "photo") }
                if !model.sources.isEmpty {
                    Section("Recent sources") {
                        ForEach(model.sources) { s in Button { Task { await model.importSource(s) } } label: { Label(s.name, systemImage: "folder.fill") } }
                        Button("Forget sources", role: .destructive) { model.forgetSources() }
                    }
                }
            } label: {
                Label("Import", systemImage: "plus").font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 40)
                    .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
            }
            .onChange(of: picked) { _, items in
                guard !items.isEmpty else { return }
                Task { await model.importPicked(items); picked = [] }
            }
        }
        .padding(.horizontal, 10).frame(height: 60)
        .panelBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .padding(.horizontal, 8).padding(.top, 4)
    }

    private func icon(_ s: String) -> some View {
        Image(systemName: s).font(.body.weight(.medium)).frame(width: 40, height: 40).fieldBackground(in: Circle())
    }

    private func albumItems(_ items: [AlbumItem]) -> AnyView {
        AnyView(ForEach(items) { a in
            if a.folder { Menu(a.name) { albumItems(a.children) } }
            else { Button("\(a.name) (\(a.count))") { Task { await model.setSource(.album(a.id), label: a.name) } } }
        })
    }

    // MARK: grid

    private func tile(_ id: UInt64) -> some View {
        let info = model.infos[id]
        let selected = model.selection.contains(id)
        return Button {
            if model.selecting { model.toggle(id) } else { model.openPhoto = id }
        } label: {
            Color(white: 0.12).aspectRatio(1, contentMode: .fit)
                .overlay { if let img = model.thumbs[id] { Image(uiImage: img).resizable().scaledToFill() } }
                .overlay(alignment: .topLeading) {
                    if info?.flag == "pick" { Image(systemName: "flag.fill").font(.caption).foregroundStyle(Theme.accent).padding(6) }
                    else if info?.flag == "reject" { Image(systemName: "xmark.circle.fill").font(.caption).foregroundStyle(.gray).padding(6) }
                }
                .overlay(alignment: .bottomLeading) {
                    if let r = info?.rating, r > 0 {
                        HStack(spacing: 1) { ForEach(0..<r, id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: 8)) } }
                            .foregroundStyle(Theme.accentSoft).padding(.horizontal, 6).padding(.vertical, 3)
                            .background(.black.opacity(0.45), in: Capsule()).padding(5)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if info?.edited == true { Circle().fill(Theme.accentSoft).frame(width: 7, height: 7).padding(7) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if model.selecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3)
                            .foregroundStyle(selected ? Theme.accent : .white).padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(selected ? Theme.accent : .clear, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tile")
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.4).onEnded { _ in if !model.selecting { model.selecting = true; model.selection = [id] } })
        .task { await model.thumbnail(id); await model.loadInfo(id) }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image("Logo").resizable().scaledToFit().frame(width: 110).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            Text(model.filtersActive ? "No photos match" : "No photos yet").font(.title2.weight(.semibold))
            Text(model.filtersActive ? "Try clearing the filters." : "Import photos from Files, a folder, or your Photos library.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            if model.filtersActive { Button("Clear filters") { Task { await model.clearFilters() } }.buttonStyle(.borderedProminent) }
            else { Button { showFiles = true } label: { Label("Import", systemImage: "plus") }.buttonStyle(.borderedProminent) }
        }
        .padding(.top, 120).frame(maxWidth: .infinity)
    }

    // MARK: bottom bar

    private var bottomBar: some View {
        @Bindable var m = model
        return Group {
            if model.selecting {
                HStack(spacing: 6) {
                    Text("\(model.selection.count) selected").font(.subheadline.weight(.medium)).padding(.horizontal, 8)
                    Button("All") { model.selectAll() }.buttonStyle(.bordered).tint(.gray)
                    Spacer()
                    Menu { ForEach(0...5, id: \.self) { r in Button(r == 0 ? "No rating" : String(repeating: "★", count: r)) { Task { await model.batch("photo.rate", ["rating": r]) } } } } label: { icon("star") }
                    Button { Task { await model.batch("photo.pick") } } label: { icon("flag") }
                    Button { Task { await model.batch("photo.reject") } } label: { icon("xmark.circle") }
                    Menu {
                        Button("New album…") { askAlbum = true }
                        ForEach(flat(model.albums).filter { !$0.folder }) { a in
                            Button(a.name) { Task { await model.batch("album.addPhotos", ["id": a.id]) } }
                        }
                    } label: { icon("rectangle.stack.badge.plus") }
                    Button { if !model.selection.isEmpty { exporting = true } } label: {
                        Label("Export", systemImage: "square.and.arrow.up").font(.subheadline.weight(.semibold)).padding(.horizontal, 12).frame(height: 40)
                            .fieldBackground(!model.selection.isEmpty, in: Capsule()).foregroundStyle(model.selection.isEmpty ? Color.secondary : .white)
                    }
                    if model.source == .recentlyDeleted { Button { Task { await model.batch("photo.restore", clear: true) } } label: { icon("arrow.uturn.backward") } }
                    else { Button(role: .destructive) { Task { await model.batch("photo.delete", clear: true) } } label: { icon("trash") } }
                }
                .padding(.horizontal, 10).frame(height: 60)
                .panelBackground(in: RoundedRectangle(cornerRadius: 28, style: .continuous)).padding(.horizontal, 8).padding(.bottom, 8)
            } else {
                HStack(spacing: 8) {
                    Text("\(model.photoIDs.count) photos · \(model.sortLabel)").font(.footnote.weight(.medium)).padding(.horizontal, 14).frame(height: 40)
                        .panelBackground(in: Capsule())
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.3x3").font(.caption)
                        Slider(value: $m.gridSize, in: 80...260).frame(width: 130).tint(Theme.accent)
                        Image(systemName: "square.grid.2x2").font(.caption)
                    }
                    .padding(.horizontal, 14).frame(height: 40).panelBackground(in: Capsule())
                }
                .padding(.horizontal, 12).padding(.bottom, 10)
            }
        }
    }

    private func flat(_ a: [AlbumItem]) -> [AlbumItem] { a.flatMap { [$0] + flat($0.children) } }
}

struct FilterSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var m = model
        VStack(spacing: 16) {
            HStack {
                Text("Filter").font(.title2.weight(.semibold)); Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).panelBackground(in: Circle()) }
            }
            HStack { Text("Rating"); Spacer()
                ForEach(1...5, id: \.self) { n in
                    Button { m.filterRating = m.filterRating == n ? 0 : n } label: {
                        Image(systemName: n <= m.filterRating ? "star.fill" : "star").foregroundStyle(n <= m.filterRating ? Theme.accentSoft : .secondary).frame(width: 36, height: 44)
                    }
                }
            }
            Picker("Flag", selection: Binding(get: { m.filterFlag ?? "any" }, set: { m.filterFlag = $0 == "any" ? nil : $0 })) {
                Text("Any").tag("any"); Text("Picked").tag("pick"); Text("Rejected").tag("reject"); Text("Unflagged").tag("none")
            }.pickerStyle(.segmented)
            Toggle("Edited only", isOn: $m.filterEdited).tint(Theme.accent)
            Spacer()
            HStack {
                Button("Clear") { Task { await model.clearFilters(); dismiss() } }.buttonStyle(.bordered).tint(.gray)
                Button { Task { await model.applyFilters(); dismiss() } } label: { Text("Apply").font(.headline).frame(maxWidth: .infinity).frame(height: 50).background(Theme.accent, in: Capsule()).foregroundStyle(.white) }
            }
        }
        .padding(20).presentationBackground(.ultraThinMaterial).presentationCornerRadius(28)
    }
}

struct LibrariesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var demo = false
    @State private var toDelete: LibraryEntry?

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Libraries").font(.title2.weight(.semibold)); Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).panelBackground(in: Circle()) }
            }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(model.libraries) { lib in
                        HStack {
                            Button { Task { await model.open(lib, seedDemo: false); dismiss() } } label: {
                                HStack { Image(systemName: lib == model.currentLibrary ? "checkmark.circle.fill" : "circle").foregroundStyle(lib == model.currentLibrary ? Theme.accent : .secondary)
                                    Text(lib.name); Spacer() }.frame(height: 48)
                            }.buttonStyle(.plain)
                            if lib != model.currentLibrary { Button { toDelete = lib } label: { Image(systemName: "trash").foregroundStyle(.secondary).frame(width: 44, height: 44) } }
                        }
                        .padding(.horizontal, 12).fieldBackground(in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            VStack(spacing: 10) {
                TextField("New library name", text: $name).textFieldStyle(.roundedBorder)
                Toggle("Fill with demo photos", isOn: $demo).tint(Theme.accent)
                Button { Task { await model.createLibrary(name: name, demo: demo); dismiss() } } label: {
                    Text("Create library").font(.headline).frame(maxWidth: .infinity).frame(height: 50).background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).presentationBackground(.ultraThinMaterial).presentationCornerRadius(28)
        .confirmationDialog("Delete this library and its photos?", isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }), titleVisibility: .visible) {
            Button("Delete library", role: .destructive) { if let l = toDelete { model.deleteLibrary(l) }; toDelete = nil }
        } message: { Text("Photos copied into it are removed from this device. This can't be undone.") }
    }
}
