import SwiftUI
import Observation
import PhotosUI

struct LibraryEntry: Identifiable, Hashable {
    var id: String { url.path }
    let name: String
    let url: URL
}

/// A folder the user imported from, kept as a bookmark so it can be imported from again.
struct ImportSource: Identifiable, Codable, Hashable {
    var id: String { name + String(bookmark.count) }
    let name: String
    let bookmark: Data
}

struct AlbumItem: Identifiable {
    let id: Int
    let name: String
    let count: Int
    let folder: Bool
    let children: [AlbumItem]
}

enum SourceKind: Equatable {
    case all, recentlyAdded, picks, recentlyDeleted, album(Int), folder(String)
}

@MainActor @Observable
final class AppModel {
    var engine = Engine(demo: false)
    var libraries: [LibraryEntry] = []
    var currentLibrary: LibraryEntry?
    var libraryError: String?

    var photoIDs: [UInt64] = []
    var openPhoto: UInt64?
    var thumbs: [UInt64: UIImage] = [:]
    var infos: [UInt64: PhotoInfo] = [:]
    var albums: [AlbumItem] = []

    // view state
    var source: SourceKind = .all
    var sourceLabel = "All Photos"
    var search = ""
    var sortKey = "captureDate"
    var ascending = false
    var filterRating = 0
    var filterFlag: String?
    var filterEdited = false
    var selecting = false
    var selection: Set<UInt64> = []
    var gridSize = 130.0

    var importing = false
    var importMessage: String?
    var started = false
    var sources: [ImportSource] = []

    var filtersActive: Bool { filterRating > 0 || filterFlag != nil || filterEdited || !search.isEmpty }

    var sortLabel: String {
        switch (sortKey, ascending) {
        case ("captureDate", false): "Newest first"
        case ("captureDate", true): "Oldest first"
        case ("importDate", _): "Import date"
        case ("editDate", _): "Edit date"
        case ("fileName", _): "File name"
        case ("rating", _): "Rating"
        case ("fileSize", _): "File size"
        default: "Sorted"
        }
    }

    // MARK: libraries

    private var documents: URL { URL.documentsDirectory }
    private var librariesRoot: URL { documents.appending(path: "Libraries", directoryHint: .isDirectory) }
    private var legacyLibrary: URL { documents.appending(path: "RawLight Library", directoryHint: .isDirectory) }

    // MARK: remembered import sources

    private func loadSources() {
        if let d = UserDefaults.standard.data(forKey: "importSources"), let s = try? JSONDecoder().decode([ImportSource].self, from: d) { sources = s }
    }
    private func remember(_ url: URL) {
        guard url.hasDirectoryPath, let data = try? url.bookmarkData() else { return }
        sources.removeAll { $0.name == url.lastPathComponent }
        sources.insert(ImportSource(name: url.lastPathComponent, bookmark: data), at: 0)
        sources = Array(sources.prefix(8))
        if let d = try? JSONEncoder().encode(sources) { UserDefaults.standard.set(d, forKey: "importSources") }
    }
    func forgetSources() { sources = []; UserDefaults.standard.removeObject(forKey: "importSources") }

    /// Imports again from a remembered folder; files already in the library are skipped by the engine.
    func importSource(_ s: ImportSource) async {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: s.bookmark, bookmarkDataIsStale: &stale) else {
            importMessage = "\(s.name) is no longer available"; return
        }
        importing = true
        defer { importing = false }
        guard url.startAccessingSecurityScopedResource() else { importMessage = "No access to \(s.name)"; return }
        defer { url.stopAccessingSecurityScopedResource() }
        if stale { remember(url) }
        await runImport([url.path])
    }

    func scanLibraries() {
        var list: [LibraryEntry] = []
        if FileManager.default.fileExists(atPath: legacyLibrary.path) { list.append(LibraryEntry(name: "RawLight Library", url: legacyLibrary)) }
        let dirs = (try? FileManager.default.contentsOfDirectory(at: librariesRoot, includingPropertiesForKeys: nil)) ?? []
        for d in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where d.hasDirectoryPath {
            list.append(LibraryEntry(name: d.lastPathComponent, url: d))
        }
        libraries = list
    }

    func start() async {
        guard !started else { return }
        started = true
        loadSources()
        scanLibraries()
        if libraries.isEmpty { await createLibrary(name: "My Library", demo: true); return }
        let saved = UserDefaults.standard.string(forKey: "currentLibrary")
        await open(libraries.first { $0.id == saved } ?? libraries[0], seedDemo: false)
    }

    func open(_ entry: LibraryEntry, seedDemo: Bool) async {
        let e = Engine(demo: false)
        libraryError = await e.openLibrary(at: entry.url, seedDemo: seedDemo)
        engine = e
        currentLibrary = entry
        UserDefaults.standard.set(entry.id, forKey: "currentLibrary")
        thumbs = [:]; infos = [:]; selection = []; selecting = false; openPhoto = nil
        source = .all; sourceLabel = "All Photos"; search = ""; filterRating = 0; filterFlag = nil; filterEdited = false
        await load()
    }

    func createLibrary(name: String, demo: Bool) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty else { return }
        var url = librariesRoot.appending(path: clean, directoryHint: .isDirectory)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) { url = librariesRoot.appending(path: "\(clean) \(n)", directoryHint: .isDirectory); n += 1 }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        scanLibraries()
        await open(LibraryEntry(name: url.lastPathComponent, url: url), seedDemo: demo)
    }

    func deleteLibrary(_ entry: LibraryEntry) {
        guard entry != currentLibrary else { return }
        try? FileManager.default.removeItem(at: entry.url)
        scanLibraries()
    }

    // MARK: browsing

    func load() async {
        photoIDs = await engine.visibleIDs()
        await loadAlbums()
    }

    func loadAlbums() async {
        func parse(_ a: [[String: Any]]) -> [AlbumItem] {
            a.compactMap { d in
                guard let id = (d["id"] as? NSNumber)?.intValue, let name = d["name"] as? String else { return nil }
                return AlbumItem(id: id, name: name, count: (d["count"] as? NSNumber)?.intValue ?? 0, folder: d["folder"] as? Bool ?? false,
                                 children: parse(d["children"] as? [[String: Any]] ?? []))
            }
        }
        albums = parse((try? await engine.execute("albums.list") as? [[String: Any]]) ?? [])
    }

    func setSource(_ s: SourceKind, label: String) async {
        source = s; sourceLabel = label
        var p: [String: Any]
        switch s {
        case .all: p = ["kind": "all"]
        case .recentlyAdded: p = ["kind": "recentlyAdded"]
        case .picks: p = ["kind": "picks"]
        case .recentlyDeleted: p = ["kind": "recentlyDeleted"]
        case .album(let id): p = ["kind": "album", "id": id]
        case .folder(let path): p = ["kind": "libraryFolder", "path": path]
        }
        _ = try? await engine.execute("library.source", p)
        selection = []
        await load()
    }

    func applyFilters() async {
        _ = try? await engine.execute("library.clearFilter")
        var f: [String: Any] = [:]
        if !search.isEmpty { f["text"] = search }
        if filterRating > 0 { f["rating"] = filterRating; f["ratingOp"] = "atLeast" }
        if let flag = filterFlag { f["flag"] = flag }
        if filterEdited { f["edited"] = true }
        if !f.isEmpty { _ = try? await engine.execute("library.filter", f) }
        await load()
    }

    func applySort() async {
        _ = try? await engine.execute("library.sort", ["key": sortKey, "ascending": ascending])
        await load()
    }

    func clearFilters() async {
        search = ""; filterRating = 0; filterFlag = nil; filterEdited = false
        await applyFilters()
    }

    // MARK: tiles

    func thumbnail(_ id: UInt64) async {
        guard thumbs[id] == nil, let img = await engine.render(id, maxEdge: 360, kind: .thumb)?.image else { return }
        thumbs[id] = img
    }

    func loadInfo(_ id: UInt64) async {
        guard infos[id] == nil, let i = await engine.info(id) else { return }
        infos[id] = i
    }

    // MARK: selection and batch actions

    func toggle(_ id: UInt64) { if selection.contains(id) { selection.remove(id) } else { selection.insert(id) } }
    func selectAll() { selection = Set(photoIDs) }

    /// Runs a command on the selected photos, then refreshes the view.
    func batch(_ command: String, _ extra: [String: Any] = [:], clear: Bool = false) async {
        guard !selection.isEmpty else { return }
        var p = extra
        p["ids"] = Array(selection)
        do { _ = try await engine.execute(command, p) } catch { importMessage = error.localizedDescription }
        for id in selection { infos[id] = nil }
        if clear { selection = []; selecting = false }
        await load()
    }

    func createAlbum(_ name: String) async {
        let ids = Array(selection)
        _ = try? await engine.execute("album.create", ["name": name, "addSelected": false])
        await loadAlbums()
        if !ids.isEmpty, let a = albums.first(where: { $0.name == name }) {
            _ = try? await engine.execute("album.addPhotos", ["id": a.id, "ids": ids])
            await loadAlbums()
        }
    }

    // MARK: import

    /// Copies the picked files into the library.
    func importPicked(_ items: [PhotosPickerItem]) async {
        importing = true
        defer { importing = false }
        let dir = FileManager.default.temporaryDirectory.appending(path: "Imports-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var paths: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let url = dir.appending(path: "\(UUID().uuidString).\(ext)")
            if (try? data.write(to: url)) != nil { paths.append(url.path) }
        }
        guard !paths.isEmpty else { importMessage = "Couldn't read the selected photos"; return }
        await runImport(paths)
        try? FileManager.default.removeItem(at: dir)
    }

    /// Imports a folder (or files) chosen in the Files picker.
    func importURLs(_ urls: [URL]) async {
        importing = true
        defer { importing = false }
        var scoped: [URL] = []
        for u in urls where u.startAccessingSecurityScopedResource() { scoped.append(u); remember(u) }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        guard !scoped.isEmpty else { importMessage = "No access to the selected items"; return }
        await runImport(scoped.map(\.path))
    }

    private func runImport(_ paths: [String]) async {
        do {
            let r = try await engine.execute("library.import", ["paths": paths, "mode": "copy"])
            await load()
            let n = ((r as? [String: Any])?["imported"] as? NSNumber)?.intValue ?? 0
            importMessage = "Imported \(n) photo\(n == 1 ? "" : "s")"
        } catch {
            importMessage = error.localizedDescription
        }
    }
}
