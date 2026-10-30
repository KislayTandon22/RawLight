import SwiftUI
import Observation
import PhotosUI

@MainActor @Observable
final class AppModel {
    let engine = Engine(demo: false)
    var libraryError: String?
    private var opened = false
    var photoIDs: [UInt64] = []
    var openPhoto: UInt64?
    var thumbs: [UInt64: UIImage] = [:]

    func load() async {
        if !opened {
            opened = true
            let dir = URL.documentsDirectory.appending(path: "RawLight Library", directoryHint: .isDirectory)
            let fresh = !FileManager.default.fileExists(atPath: dir.path)
            libraryError = await engine.openLibrary(at: dir, seedDemo: fresh)
        }
        photoIDs = await engine.visibleIDs()
    }

    func thumbnail(_ id: UInt64) async {
        guard thumbs[id] == nil, let img = await engine.render(id, maxEdge: 360, kind: .thumb)?.image else { return }
        thumbs[id] = img
    }

    var importing = false
    var importMessage: String?

    /// Copies the picked files into the app's Documents/Imports and adds them to the library.
    func importPicked(_ items: [PhotosPickerItem]) async {
        importing = true
        defer { importing = false }
        let dir = URL.documentsDirectory.appending(path: "Imports", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var paths: [String] = []
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
            let url = dir.appending(path: "\(UUID().uuidString).\(ext)")
            if (try? data.write(to: url)) != nil { paths.append(url.path) }
        }
        guard !paths.isEmpty else { importMessage = "Couldn't read the selected photos"; return }
        do {
            _ = try await engine.execute("library.import", ["paths": paths, "mode": "copy"])
            await load()
            importMessage = nil
        } catch {
            importMessage = error.localizedDescription
        }
    }

    /// Imports a folder (or files) chosen in the Files picker; the library copies them in.
    func importURLs(_ urls: [URL]) async {
        importing = true
        defer { importing = false }
        var paths: [String] = []
        var scoped: [URL] = []
        for u in urls where u.startAccessingSecurityScopedResource() { scoped.append(u); paths.append(u.path) }
        defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
        guard !paths.isEmpty else { importMessage = "No access to the selected items"; return }
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
