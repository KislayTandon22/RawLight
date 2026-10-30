import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The engine has no HEIC decoder, so HEIC/HEIF photos are converted to high-quality JPEG
/// (metadata and colour profile kept) before they are imported.
enum HEICConverter {
    static func isHEIC(_ url: URL) -> Bool { ["heic", "heif", "hif"].contains(url.pathExtension.lowercased()) }

    /// Converts one file; returns the JPEG's URL in `dir`, or nil when it can't be read.
    static func convert(_ src: URL, into dir: URL) -> URL? {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil) else { return nil }
        let out = dir.appending(path: src.deletingPathExtension().lastPathComponent + "-" + String(UUID().uuidString.prefix(6)) + ".jpg")
        guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.97, kCGImageDestinationMergeMetadata: true]
        CGImageDestinationAddImageFromSource(dest, source, 0, options as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out : nil
    }

    /// Converts every HEIC under `url` (a file or a folder) into `dir`; returns the JPEGs.
    static func convertAll(under url: URL, into dir: URL) -> [URL] {
        if !url.hasDirectoryPath { return isHEIC(url) ? convert(url, into: dir).map { [$0] } ?? [] : [] }
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return (walk.compactMap { $0 as? URL }).filter(isHEIC).compactMap { convert($0, into: dir) }
    }
}
