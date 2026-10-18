//
//  PhotoPickerBridge.swift
//  LightCraft iPad
//
//  Clean-room Swift bridge for native iPad photo import (PHPicker)
//  and file/catalog import (UIDocumentPicker).
//

import UIKit
import PhotosUI
import UniformTypeIdentifiers

public typealias PickerCompletion = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void

final class PhotoPickerManager: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
    static let shared = PhotoPickerManager()

    private var activeCompletion: PickerCompletion?
    private var activeContext: UnsafeMutableRawPointer?

    private let importDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Imported", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private let exportDirectory: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    // MARK: - Entry Point

    func showPicker(
        kind: UInt32,
        title: String?,
        filterName: String?,
        filterExts: [String],
        fileName: String?,
        context: UnsafeMutableRawPointer?,
        completion: @escaping PickerCompletion
    ) {
        self.activeContext = context
        self.activeCompletion = completion

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            guard let presenter = self.topViewController() else {
                NSLog("[PhotoPickerBridge] Error: No top view controller found")
                self.finish(with: [])
                return
            }

            switch kind {
            case 0: // PickKind::Files
                if filterExts.contains("lrcat") || filterExts.contains("lcpreset") {
                    self.presentDocumentPicker(forTypes: filterExts, multiple: true, from: presenter)
                } else {
                    self.presentPHPicker(multiple: true, from: presenter)
                }

            case 1: // PickKind::File
                if filterExts.contains("lrcat") {
                    self.presentDocumentPicker(forTypes: ["lrcat"], multiple: false, from: presenter)
                } else {
                    self.presentPHPicker(multiple: false, from: presenter)
                }

            case 2: // PickKind::Folder
                self.presentFolderPicker(from: presenter)

            case 3: // PickKind::Save
                let suggestedName = fileName ?? "Export"
                let saveUrl = self.exportDirectory.appendingPathComponent(suggestedName)
                self.finish(with: [saveUrl.path])

            default:
                self.finish(with: [])
            }
        }
    }

    // MARK: - PHPicker (Photo Library & ProRAW)

    private func presentPHPicker(multiple: Bool, from presenter: UIViewController) {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = multiple ? 0 : 1
        config.filter = .images
        config.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        picker.modalPresentationStyle = .pageSheet
        presenter.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)

        guard !results.isNilOrEmpty else {
            finish(with: [])
            return
        }

        let group = DispatchGroup()
        var importedPaths: [String] = []
        let lock = NSLock()

        for (index, result) in results.enumerated() {
            group.enter()
            let provider = result.itemProvider

            if provider.hasItemConformingToTypeIdentifier(UTType.rawImage.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.rawImage.identifier) { [weak self] url, error in
                    defer { group.leave() }
                    guard let self = self, let url = url, error == nil else { return }
                    if let saved = self.copyToSandbox(from: url, prefix: "raw_\(index)") {
                        lock.lock()
                        importedPaths.append(saved)
                        lock.unlock()
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
                    defer { group.leave() }
                    guard let self = self, let url = url, error == nil else { return }
                    if let saved = self.copyToSandbox(from: url, prefix: "img_\(index)") {
                        lock.lock()
                        importedPaths.append(saved)
                        lock.unlock()
                    }
                }
            } else {
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.finish(with: importedPaths)
        }
    }

    // MARK: - Document Picker (Files, SD Cards, SSDs, Lightroom Catalogs)

    private func presentDocumentPicker(forTypes exts: [String], multiple: Bool, from presenter: UIViewController) {
        var contentTypes: [UTType] = []
        for ext in exts {
            if let type = UTType(filenameExtension: ext) {
                contentTypes.append(type)
            }
        }
        if contentTypes.isEmpty {
            contentTypes = [.item]
        }

        let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = multiple
        picker.modalPresentationStyle = .pageSheet
        presenter.present(picker, animated: true)
    }

    private func presentFolderPicker(from presenter: UIViewController) {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .pageSheet
        presenter.present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        var paths: [String] = []
        for url in urls {
            let shouldStop = url.startAccessingSecurityScopedResource()
            defer {
                if shouldStop { url.stopAccessingSecurityScopedResource() }
            }

            if url.hasDirectoryPath {
                paths.append(url.path)
            } else if let saved = copyToSandbox(from: url, prefix: "doc") {
                paths.append(saved)
            }
        }
        finish(with: paths)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finish(with: [])
    }

    // MARK: - Helper

    private func copyToSandbox(from source: URL, prefix: String) -> String? {
        let ext = source.pathExtension
        let name = "\(prefix)_\(UUID().uuidString.prefix(8)).\(ext)"
        let destination = importDirectory.appendingPathComponent(name)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return destination.path
        } catch {
            NSLog("[PhotoPickerBridge] Failed to copy item: %@", error.localizedDescription)
            return nil
        }
    }

    private func finish(with paths: [String]) {
        guard let completion = activeCompletion else { return }
        let context = activeContext
        activeCompletion = nil
        activeContext = nil

        let jsonData = (try? JSONSerialization.data(withJSONObject: paths, options: [])) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        jsonString.withCString { cStr in
            completion(context, cStr)
        }
    }

    func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let window = scenes.first?.windows.first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first else {
            return nil
        }
        var top = window.rootViewController
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}

private extension Collection {
    var isNilOrEmpty: Bool {
        return isEmpty
    }
}

// MARK: - C FFI Exported Functions

@_cdecl("ios_show_native_picker")
public func ios_show_native_picker(
    kind: UInt32,
    title: UnsafePointer<CChar>?,
    filterName: UnsafePointer<CChar>?,
    filterExts: UnsafePointer<CChar>?,
    fileName: UnsafePointer<CChar>?,
    context: UnsafeMutableRawPointer?,
    completion: @escaping PickerCompletion
) {
    let titleStr = title.flatMap { String(cString: $0) }
    let filterNameStr = filterName.flatMap { String(cString: $0) }
    let filterExtsStr = filterExts.flatMap { String(cString: $0) } ?? ""
    let fileNameStr = fileName.flatMap { String(cString: $0) }

    let exts = filterExtsStr.split(separator: ",").map { String($0) }

    PhotoPickerManager.shared.showPicker(
        kind: kind,
        title: titleStr,
        filterName: filterNameStr,
        filterExts: exts,
        fileName: fileNameStr,
        context: context,
        completion: completion
    )
}

@_cdecl("ios_share_file")
public func ios_share_file(_ path_cstr: UnsafePointer<CChar>?) -> Bool {
    guard let path_cstr = path_cstr else { return false }
    let path = String(cString: path_cstr)
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: path) else { return false }

    DispatchQueue.main.async {
        guard let presenter = PhotoPickerManager.shared.topViewController() else { return }
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activityVC, animated: true)
    }
    return true
}

@_cdecl("ios_share_files")
public func ios_share_files(_ paths_json: UnsafePointer<CChar>?) -> Bool {
    guard let paths_json = paths_json else { return false }
    let jsonStr = String(cString: paths_json)
    guard let data = jsonStr.data(using: .utf8),
          let paths = try? JSONDecoder().decode([String].self, from: data) else {
        return false
    }
    let urls = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    guard !urls.isEmpty else { return false }

    DispatchQueue.main.async {
        guard let presenter = PhotoPickerManager.shared.topViewController() else { return }
        let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(activityVC, animated: true)
    }
    return true
}

@_cdecl("ios_open_url")
public func ios_open_url(_ cstr: UnsafePointer<CChar>?) -> Bool {
    guard let cstr = cstr else { return false }
    let str = String(cString: cstr)
    guard let url = URL(string: str), url.scheme == "https" else { return false }
    DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }
    return true
}

@_cdecl("ios_log")
public func ios_log(_ cstr: UnsafePointer<CChar>?) {
    guard let cstr = cstr else { return }
    let str = String(cString: cstr)
    NSLog("%@", str)
}
