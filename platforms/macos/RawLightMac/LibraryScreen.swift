import SwiftUI

enum MacTheme {
    static let accent = Color(red: 0.95, green: 0.23, blue: 0.36)
    static let bg = Color(white: 0.08)
    static let side = Color(white: 0.105)
    static let bar = Color(white: 0.13)
    static let line = Color.white.opacity(0.08)
    static let dim = Color.white.opacity(0.55)
}

@Observable @MainActor final class LibraryModel {
    let engine = MacEngine(demo: true)
    var ids: [UInt64] = []
    var selection: Set<UInt64> = []
    var thumbSize: Double = 170
    var query = ""
    var module = ProcessInfo.processInfo.environment["RAWLIGHT_MODULE"] == nil && ProcessInfo.processInfo.environment["RAWLIGHT_SKIP_WELCOME"] == nil ? "Welcome" : "Library"
    /// Bumped when a photo's edits change so its thumbnails are redrawn.
    var thumbVersion: [UInt64: Int] = [:]
    var activeID: UInt64?
    var libraryName = "Demo library"
    var libraryError: String?
    var showPalette = false
    var showShortcuts = false
    var importMessage: String?
    var recents: [String] = UserDefaults.standard.stringArray(forKey: "recentLibraries") ?? []
    func load() async { ids = await engine.visibleIDs() }
    func openLibrary(_ url: URL) async {
        if let e = await engine.openLibrary(at: url) { libraryError = e; return }
        libraryError = nil; libraryName = url.lastPathComponent; selection = []; activeID = nil
        recents = ([url.path] + recents.filter { $0 != url.path }).prefix(6).map { $0 }
        UserDefaults.standard.set(recents, forKey: "recentLibraries")
        await load()
    }
    func chooseLibrary() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.canCreateDirectories = true
        p.prompt = "Open Library"; p.message = "Choose a RawLight library folder, or make a new one"
        if p.runModal() == .OK, let u = p.url { Task { await openLibrary(u) } }
    }
    func openDevelop(_ id: UInt64) {
        activeID = id; selection = [id]; module = "Develop"
    }
}

struct LibraryScreen: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        @Bindable var m = model
        Group {
            switch model.module {
            case "Welcome": WelcomeScreen()
            case "Develop": DevelopScreen()
            case "Export": ExportScreen()
            default: library
            }
        }
        .sheet(isPresented: $m.showPalette) { CommandPalette() }
        .sheet(isPresented: $m.showShortcuts) { ShortcutsSheet() }
    }
    private var library: some View {
        VStack(spacing: 0) {
            TopBar()
            Divider().overlay(MacTheme.line)
            HStack(spacing: 0) {
                Sidebar().frame(width: 230)
                Divider().overlay(MacTheme.line)
                Grid()
                Divider().overlay(MacTheme.line)
                RightPanel().frame(width: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().overlay(MacTheme.line)
            StatusBar()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.bg)
    }
}

struct ModuleSwitch: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        HStack(spacing: 4) {
            ForEach(["Library", "Develop", "Export"], id: \.self) { t in
                let on = model.module == t
                Button {
                    if t == "Develop", model.activeID == nil, let f = model.ids.first { model.openDevelop(f) }
                    else { model.module = t }
                } label: {
                    Text(t).font(.system(size: 13, weight: .medium)).padding(.horizontal, 14).frame(height: 26)
                        .background(on ? MacTheme.accent : .clear, in: Capsule())
                        .foregroundStyle(on ? .white : MacTheme.dim)
                }.buttonStyle(.plain)
            }
        }
        .padding(3).background(Color.white.opacity(0.06), in: Capsule())
    }
}

private struct TopBar: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        @Bindable var m = model
        HStack(spacing: 14) {
            Spacer().frame(width: 64)
            ModuleSwitch()
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(MacTheme.dim)
                TextField("Search", text: $m.query).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10).frame(width: 260, height: 28)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            Button { Task { await model.importPhotos() } } label: { Label("Import", systemImage: "square.and.arrow.down") }
                .buttonStyle(.borderedProminent).tint(MacTheme.accent).controlSize(.regular)
        }
        .padding(.horizontal, 14).frame(height: 48).background(MacTheme.bar)
    }
}

private struct Sidebar: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                LibrarySwitcher()
                header("Catalog")
                row("photo.on.rectangle", "All Photographs", "\(model.ids.count)", selected: true)
                row("square.stack", "Quick Collection", "0")
                row("clock", "Previous Import", "\(model.ids.count)")
                header("Albums")
                row("rectangle.stack", "Portfolio", "12")
                row("rectangle.stack", "Travel", "48")
                header("Folders")
                row("folder", model.libraryName, "\(model.ids.count)")
                header("Flags")
                row("flag", "Picked", "0")
                row("xmark.circle", "Rejected", "0")
            }.padding(10)
        }
        .background(MacTheme.side)
    }
    private func header(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(MacTheme.dim)
            .padding(.top, 14).padding(.bottom, 4).padding(.horizontal, 8)
    }
    private func row(_ icon: String, _ t: String, _ n: String, selected: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(selected ? MacTheme.accent : MacTheme.dim)
            Text(t).font(.system(size: 13))
            Spacer()
            Text(n).font(.system(size: 11)).foregroundStyle(MacTheme.dim).monospacedDigit()
        }
        .padding(.horizontal, 8).frame(height: 26)
        .background(selected ? Color.white.opacity(0.09) : .clear, in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct LibrarySwitcher: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        Menu {
            Section("Current") { Text(model.libraryName) }
            if !model.recents.isEmpty {
                Section("Recent libraries") {
                    ForEach(model.recents, id: \.self) { path in
                        Button(URL(fileURLWithPath: path).lastPathComponent) { Task { await model.openLibrary(URL(fileURLWithPath: path)) } }
                    }
                }
            }
            Divider()
            Button("Open or New Library…") { model.chooseLibrary() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive").foregroundStyle(MacTheme.accent)
                VStack(alignment: .leading, spacing: 0) {
                    Text("LIBRARY").font(.system(size: 9, weight: .semibold)).foregroundStyle(MacTheme.dim)
                    Text(model.libraryName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 10)).foregroundStyle(MacTheme.dim)
            }
            .padding(.horizontal, 10).frame(height: 42)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain).menuIndicator(.hidden)
    }
}

private struct Grid: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: model.thumbSize), spacing: 8)], spacing: 8) {
                ForEach(model.ids, id: \.self) { id in Tile(id: id) }
            }.padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MacTheme.bg)
    }
}

private struct Tile: View {
    @Environment(LibraryModel.self) private var model
    let id: UInt64
    @State private var image: NSImage?
    var body: some View {
        let selected = model.selection.contains(id)
        Color(white: 0.14)
            .aspectRatio(1, contentMode: .fit)
            .overlay { if let image { Image(nsImage: image).resizable().scaledToFill() } }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? MacTheme.accent : .clear, lineWidth: 2))
        .onTapGesture(count: 2) { model.openDevelop(id) }
        .onTapGesture { if NSEvent.modifierFlags.contains(.command) { if selected { model.selection.remove(id) } else { model.selection.insert(id) } } else { model.selection = [id] } }
        .task(id: model.thumbVersion[id]) { image = await model.engine.thumbnail(id, edge: 360) }
    }
}

private struct StatusBar: View {
    @Environment(LibraryModel.self) private var model
    var body: some View {
        @Bindable var m = model
        HStack(spacing: 12) {
            Text(model.importMessage ?? "\(model.ids.count) photos · \(model.selection.count) selected").font(.system(size: 11)).foregroundStyle(MacTheme.dim)
            Spacer()
            Image(systemName: "square.grid.3x3").font(.system(size: 11)).foregroundStyle(MacTheme.dim)
            Slider(value: $m.thumbSize, in: 90...320).frame(width: 140).tint(MacTheme.accent).controlSize(.small)
        }
        .padding(.horizontal, 14).frame(height: 28).background(MacTheme.bar)
    }
}
