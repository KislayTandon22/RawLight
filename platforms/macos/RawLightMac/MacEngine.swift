import AppKit
import Foundation

/// Minimal macOS wrapper over the Rust C ABI (same calls as the iPad `Engine`).
final class MacEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "rawlight.engine", qos: .userInitiated)
    private let thumbQueue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 4; q.qualityOfService = .utility; return q
    }()
    private var session: OpaquePointer?
    private let thumbCache: NSCache<NSString, NSImage> = { let c = NSCache<NSString, NSImage>(); c.countLimit = 600; return c }()

    init(demo: Bool) {
        queue.sync { self.session = rl_session_new(demo ? 1 : 0) }
    }
    deinit { if let s = session { rl_session_free(s) } }

    /// Opens (or creates) a persistent library folder; returns an error message, or nil on success.
    func openLibrary(at dir: URL, seedDemo: Bool = false) async -> String? {
        await withCheckedContinuation { cont in
            queue.async {
                guard let raw = rl_open_library(self.session, dir.path, seedDemo ? 1 : 0) else { return cont.resume(returning: "no reply") }
                defer { rl_string_free(raw) }
                let obj = try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any]
                cont.resume(returning: obj?["error"] as? String)
            }
        }
    }

    func visibleIDs() async -> [UInt64] {
        await withCheckedContinuation { cont in
            queue.async {
                guard let raw = rl_visible_ids(self.session) else { return cont.resume(returning: []) }
                defer { rl_string_free(raw) }
                let obj = try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any]
                cont.resume(returning: (obj?["ok"] as? [NSNumber])?.map { $0.uint64Value } ?? [])
            }
        }
    }

    func thumbnail(_ id: UInt64, edge: Int, version: Int = 0) async -> NSImage? {
        let key = "\(id)-\(edge)-\(version)" as NSString
        if let hit = thumbCache.object(forKey: key) { return hit }
        let img = await renderThumbnail(id, edge: edge)
        if let img { thumbCache.setObject(img, forKey: key) }
        return img
    }

    private func renderThumbnail(_ id: UInt64, edge: Int) async -> NSImage? {
        let job: OpaquePointer? = await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: rl_job_new(self.session, id, UInt32(edge), UInt32(edge), 1)) }
        }
        guard let job else { return nil }
        let img: NSImage? = await withCheckedContinuation { cont in
            thumbQueue.addOperation {
                var w: UInt32 = 0, h: UInt32 = 0, len: UInt = 0
                guard let p = rl_job_run(job, &w, &h, &len, nil) else { return cont.resume(returning: nil) }
                let data = Data(bytes: p, count: Int(len))
                rl_buffer_free(p, len)
                cont.resume(returning: Self.image(rgba: data, width: Int(w), height: Int(h)))
            }
        }
        queue.async { rl_job_finish(self.session, job) }
        return img
    }

    @discardableResult
    func execute(_ id: String, _ params: [String: Any] = [:]) async throws -> Any {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                cont.resume(with: Result {
                    let data = try JSONSerialization.data(withJSONObject: params)
                    guard let raw = rl_execute(self.session, id, String(decoding: data, as: UTF8.self)) else { throw MacEngineError.message("no reply") }
                    defer { rl_string_free(raw) }
                    let obj = try JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8), options: [.fragmentsAllowed])
                    guard let dict = obj as? [String: Any] else { throw MacEngineError.message("bad reply") }
                    if let e = dict["error"] as? String { throw MacEngineError.message(e) }
                    return dict["ok"] ?? NSNull()
                })
            }
        }
    }

    /// kind: 0 full, 2 draft (fast, while a slider moves).
    func render(_ id: UInt64, maxEdge: Int, kind: Int32 = 0) async -> (image: NSImage, histogram: [UInt32])? {
        let job: OpaquePointer? = await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: rl_job_new(self.session, id, UInt32(maxEdge), UInt32(maxEdge), kind)) }
        }
        guard let job else { return nil }
        let out: (NSImage, [UInt32])? = await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInteractive).async {
                let t0 = DispatchTime.now()
                defer { if ProcessInfo.processInfo.environment["RAWLIGHT_TIMING"] != nil { NSLog("[RawLight] render %d px kind %d: %.0f ms", maxEdge, kind, Double(DispatchTime.now().uptimeNanoseconds - t0.uptimeNanoseconds) / 1e6) } }
                var w: UInt32 = 0, h: UInt32 = 0, len: UInt = 0
                var hist = [UInt32](repeating: 0, count: 1024)
                guard let p = rl_job_run(job, &w, &h, &len, &hist) else { return cont.resume(returning: nil) }
                let data = Data(bytes: p, count: Int(len))
                rl_buffer_free(p, len)
                guard let img = Self.image(rgba: data, width: Int(w), height: Int(h)) else { return cont.resume(returning: nil) }
                cont.resume(returning: (img, hist))
            }
        }
        queue.async { rl_job_finish(self.session, job) }
        return out
    }

    /// A preview of `id` with the watermark drawn by the engine, exactly as export does.
    func renderWatermarked(_ id: UInt64, maxEdge: Int, watermark: [String: Any], exportShortEdge: Int) async -> NSImage? {
        guard let data = try? JSONSerialization.data(withJSONObject: watermark) else { return nil }
        let json = String(decoding: data, as: UTF8.self)
        return await withCheckedContinuation { cont in
            queue.async {
                var w: UInt32 = 0, h: UInt32 = 0, len: UInt = 0
                guard let p = rl_render_watermarked(self.session, id, UInt32(maxEdge), UInt32(maxEdge), json, UInt32(max(exportShortEdge, 0)), &w, &h, &len) else {
                    return cont.resume(returning: nil)
                }
                let bytes = Data(bytes: p, count: Int(len))
                rl_buffer_free(p, len)
                cont.resume(returning: Self.image(rgba: bytes, width: Int(w), height: Int(h)))
            }
        }
    }

    /// The text of a portable watermark file: the settings and, for a graphic, the picture itself.
    func watermarkFile(_ watermark: [String: Any], name: String) async throws -> String {
        let r = try await execute("watermark.exportJson", ["watermark": watermark, "name": name]) as? [String: Any]
        guard let json = r?["json"] as? String else { throw MacEngineError.message("bad reply") }
        return json
    }

    /// The watermark in a portable file; a graphic is stored under `dir`.
    func watermarkFromFile(_ json: String, dir: URL) async throws -> (name: String, watermark: [String: Any]) {
        let r = try await execute("watermark.importJson", ["json": json, "dir": dir.path]) as? [String: Any]
        guard let wm = r?["watermark"] as? [String: Any] else { throw MacEngineError.message("bad reply") }
        return (r?["name"] as? String ?? "", wm)
    }

    func controls() async -> [MacControl] {
        guard let arr = try? await execute("develop.controls") as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let id = d["id"] as? String, let label = d["label"] as? String, let section = d["section"] as? String,
                  let mn = (d["min"] as? NSNumber)?.doubleValue, let mx = (d["max"] as? NSNumber)?.doubleValue,
                  let df = (d["default"] as? NSNumber)?.doubleValue, let v = (d["value"] as? NSNumber)?.doubleValue else { return nil }
            return MacControl(id: id, label: label, section: section, min: mn, max: mx, def: df, value: v,
                              decimals: (d["decimals"] as? NSNumber)?.intValue ?? 0,
                              track: (d["track"] as? [String: Any])?["kind"] as? String ?? "plain")
        }
    }

    private static func image(rgba: Data, width: Int, height: Int) -> NSImage? {
        guard let provider = CGDataProvider(data: rgba as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                               space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
}

struct MacControl: Identifiable, Hashable {
    let id: String, label: String, section: String
    let min: Double, max: Double, def: Double
    var value: Double
    let decimals: Int
    let track: String
    var centered: Bool { min < 0 && max > 0 }
}

enum MacEngineError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
