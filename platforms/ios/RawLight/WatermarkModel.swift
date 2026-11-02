import SwiftUI
import UIKit

/// A watermark as the engine's `app.export` `watermark` object (see docs/watermarks.md). Sizes are fractions of the photo's short edge.
struct Watermark: Equatable {
    enum Anchor: String, CaseIterable, Identifiable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
        var id: String { rawValue }
        /// An arrow towards the corner or edge the watermark sits at, a dot for the middle.
        var symbol: String {
            switch self {
            case .topLeft: "arrow.up.left"
            case .top: "arrow.up"
            case .topRight: "arrow.up.right"
            case .left: "arrow.left"
            case .center: "circle.fill"
            case .right: "arrow.right"
            case .bottomLeft: "arrow.down.left"
            case .bottom: "arrow.down"
            case .bottomRight: "arrow.down.right"
            }
        }
        var label: String {
            switch self {
            case .topLeft: "Top left"
            case .top: "Top"
            case .topRight: "Top right"
            case .left: "Left"
            case .center: "Centre"
            case .right: "Right"
            case .bottomLeft: "Bottom left"
            case .bottom: "Bottom"
            case .bottomRight: "Bottom right"
            }
        }
    }

    var text = "© "
    var imagePath = ""
    var imageWidth = 0.2
    var vertical = false
    var size = 0.035
    var opacity = 0.7
    var anchor = Anchor.bottomRight
    var insetX = 0.025
    var insetY = 0.025
    var rotation = 0
    var color = Color.white
    var shadow = true
    var borderWidth = 0.0
    var borderColor = Color.white
    var padding = 0.0
    var backgroundOpacity = 0.0
    var backgroundColor = Color.black
    var radius = 0.0

    var isGraphic: Bool { !imagePath.isEmpty }
    /// Whether anything would be drawn.
    var hasContent: Bool { isGraphic || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The object `app.export` takes as `watermark`.
    var params: [String: Any] {
        var d: [String: Any] = [
            "text": text, "vertical": vertical, "size": size, "opacity": opacity, "anchor": anchor.rawValue,
            "insetX": insetX, "insetY": insetY, "rotation": rotation, "color": Self.rgb(color), "shadow": shadow,
            "imageWidth": imageWidth, "borderWidth": borderWidth, "borderColor": Self.rgb(borderColor), "padding": padding,
            "backgroundOpacity": backgroundOpacity, "backgroundColor": Self.rgb(backgroundColor), "radius": radius,
        ]
        if isGraphic { d["image"] = imagePath }
        return d
    }

    /// From an engine watermark object (an imported file); missing keys keep their defaults.
    init(params d: [String: Any] = [:]) {
        func num(_ k: String, _ v: Double) -> Double { (d[k] as? NSNumber)?.doubleValue ?? v }
        text = d["text"] as? String ?? text
        imagePath = d["image"] as? String ?? ""
        imageWidth = num("imageWidth", imageWidth)
        vertical = d["vertical"] as? Bool ?? vertical
        size = num("size", size)
        opacity = num("opacity", opacity)
        anchor = Anchor(rawValue: d["anchor"] as? String ?? "") ?? anchor
        insetX = num("insetX", insetX)
        insetY = num("insetY", insetY)
        rotation = Int(num("rotation", 0))
        color = Self.color(d["color"], color)
        shadow = d["shadow"] as? Bool ?? shadow
        borderWidth = num("borderWidth", 0)
        borderColor = Self.color(d["borderColor"], borderColor)
        padding = num("padding", 0)
        backgroundOpacity = num("backgroundOpacity", 0)
        backgroundColor = Self.color(d["backgroundColor"], backgroundColor)
        radius = num("radius", 0)
    }

    static func rgb(_ c: Color) -> [Int] {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return [r, g, b].map { Int(($0 * 255).rounded().clamped(0, 255)) }
    }

    static func color(_ v: Any?, _ fallback: Color) -> Color {
        guard let a = v as? [NSNumber], a.count == 3 else { return fallback }
        return Color(red: a[0].doubleValue / 255, green: a[1].doubleValue / 255, blue: a[2].doubleValue / 255)
    }
}

private extension CGFloat {
    func clamped(_ lo: CGFloat, _ hi: CGFloat) -> CGFloat { Swift.min(Swift.max(self, lo), hi) }
}

/// Saved watermarks: one portable `.json` each (the same file Export / Import watermark use) in Application Support/RawLight/watermarks.
@MainActor @Observable
final class WatermarkStore {
    static let shared = WatermarkStore()
    private(set) var names: [String] = []

    static var directory: URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        let dir = base.appending(path: "RawLight/watermarks", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() { reload() }

    /// Keep a copy of a picture the user chose (a logo) inside the app, so the watermark still works after the picker's access ends.
    /// Returns the copy's path.
    static func copyLogo(from url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let dir = directory.appending(path: "logos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appending(path: "\(UUID().uuidString).\(url.pathExtension.lowercased() == "png" ? "png" : "jpg")")
        try FileManager.default.copyItem(at: url, to: dest)
        return dest.path
    }

    func reload() {
        let files = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil)) ?? []
        names = files.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func fileName(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        return name.components(separatedBy: bad).joined(separator: "-").trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    }

    func save(_ w: Watermark, as name: String, engine: Engine) async throws {
        let stem = Self.fileName(name)
        guard !stem.isEmpty else { throw EngineError.message("Give the watermark a name") }
        let json = try await engine.watermarkFile(w.params, name: stem)
        try json.write(to: Self.directory.appending(path: "\(stem).json"), atomically: true, encoding: .utf8)
        reload()
    }

    func load(_ name: String, engine: Engine) async throws -> Watermark {
        let json = try String(contentsOf: Self.directory.appending(path: "\(Self.fileName(name)).json"), encoding: .utf8)
        return Watermark(params: try await engine.watermarkFromFile(json, dir: Self.directory).watermark)
    }

    func delete(_ name: String) {
        try? FileManager.default.removeItem(at: Self.directory.appending(path: "\(Self.fileName(name)).json"))
        reload()
    }

    /// Add the watermark in a file someone shared; returns its name.
    func importFile(_ url: URL, engine: Engine) async throws -> (name: String, watermark: Watermark) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let json = try String(contentsOf: url, encoding: .utf8)
        let r = try await engine.watermarkFromFile(json, dir: Self.directory)
        let name = r.name.isEmpty ? url.deletingPathExtension().lastPathComponent : r.name
        let w = Watermark(params: r.watermark)
        try await save(w, as: name, engine: engine)
        return (name, w)
    }
}
