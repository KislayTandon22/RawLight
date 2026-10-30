import Foundation
import UIKit

/// How the engine wants a slider track drawn (`track` in `develop.controls`).
enum Track: Hashable {
    case plain, centered, temp, tint, rainbow
    case gradient(from: String, to: String)
    case hue(band: Int), sat(band: Int), lum(band: Int)
}

/// One develop control as described by the engine (`develop.controls`).
struct Control: Identifiable, Hashable {
    let id: String
    let label: String
    let section: String
    let min: Double
    let max: Double
    let def: Double
    var value: Double
    let step: Double
    let decimals: Int
    let track: Track
}

struct Rendered {
    let image: UIImage
    /// 4 x 256 bins: red, green, blue, luma.
    let histogram: [UInt32]
}

/// Thin Swift wrapper over the Rust C ABI. Commands run on one serial queue; renders are detached
/// jobs that run on worker queues so a slow render never blocks a command or another render.
final class Engine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "rawlight.engine", qos: .userInitiated)
    private let thumbQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .utility
        return q
    }()
    private var session: OpaquePointer?

    init(demo: Bool) {
        queue.sync { self.session = rl_session_new(demo ? 1 : 0) }
    }

    deinit { if let s = session { rl_session_free(s) } }

    /// Open the persistent library; returns an error message, or nil on success.
    func openLibrary(at dir: URL, seedDemo: Bool) async -> String? {
        await withCheckedContinuation { cont in
            queue.async {
                guard let raw = rl_open_library(self.session, dir.path, seedDemo ? 1 : 0) else { return cont.resume(returning: "no reply") }
                defer { rl_string_free(raw) }
                let obj = try? JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8)) as? [String: Any]
                cont.resume(returning: obj?["error"] as? String)
            }
        }
    }

    @discardableResult
    func execute(_ id: String, _ params: [String: Any] = [:]) async throws -> Any {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                cont.resume(with: Result { try self.executeSync(id, params) })
            }
        }
    }

    private func executeSync(_ id: String, _ params: [String: Any]) throws -> Any {
        let data = try JSONSerialization.data(withJSONObject: params)
        let json = String(decoding: data, as: UTF8.self)
        guard let raw = rl_execute(session, id, json) else { throw EngineError.message("no reply") }
        defer { rl_string_free(raw) }
        let obj = try JSONSerialization.jsonObject(with: Data(String(cString: raw).utf8), options: [.fragmentsAllowed])
        guard let dict = obj as? [String: Any] else { throw EngineError.message("bad reply") }
        if let e = dict["error"] as? String { throw EngineError.message(e) }
        return dict["ok"] ?? NSNull()
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

    enum Kind: Int32 { case full = 0, thumb = 1, draft = 2 }

    /// Render a photo with its current edits, fitted in `maxEdge` x `maxEdge`.
    func render(_ id: UInt64, maxEdge: Int, kind: Kind = .full) async -> Rendered? {
        // 1. build the job on the command queue (cheap)
        let job: OpaquePointer? = await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: rl_job_new(self.session, id, UInt32(maxEdge), UInt32(maxEdge), kind.rawValue)) }
        }
        guard let job else { return nil }
        // 2. run it off the command queue (slow)
        let result: Rendered? = await withCheckedContinuation { cont in
            let work = {
                var w: UInt32 = 0, h: UInt32 = 0, len: UInt = 0
                var hist = [UInt32](repeating: 0, count: 1024)
                guard let p = rl_job_run(job, &w, &h, &len, &hist) else { return cont.resume(returning: nil) }
                let data = Data(bytes: p, count: Int(len))
                rl_buffer_free(p, len)
                guard let img = Self.image(rgba: data, width: Int(w), height: Int(h)) else { return cont.resume(returning: nil) }
                cont.resume(returning: Rendered(image: img, histogram: hist))
            }
            if kind == .thumb { thumbQueue.addOperation(work) } else { DispatchQueue.global(qos: .userInteractive).async(execute: work) }
        }
        // 3. return it so the session keeps the decoded source and thumbnail
        queue.async { rl_job_finish(self.session, job) }
        return result
    }

    private static func image(rgba: Data, width: Int, height: Int) -> UIImage? {
        guard let provider = CGDataProvider(data: rgba as CFData) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                               space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info, provider: provider,
                               decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func controls() async -> [Control] {
        guard let arr = try? await execute("develop.controls") as? [[String: Any]] else { return [] }
        return arr.compactMap { d in
            guard let id = d["id"] as? String, let label = d["label"] as? String, let section = d["section"] as? String,
                  let mn = (d["min"] as? NSNumber)?.doubleValue, let mx = (d["max"] as? NSNumber)?.doubleValue,
                  let df = (d["default"] as? NSNumber)?.doubleValue, let v = (d["value"] as? NSNumber)?.doubleValue else { return nil }
            return Control(id: id, label: label, section: section, min: mn, max: mx, def: df, value: v,
                           step: (d["step"] as? NSNumber)?.doubleValue ?? 1, decimals: (d["decimals"] as? NSNumber)?.intValue ?? 0,
                           track: Self.track(d["track"] as? [String: Any]))
        }
    }

    private static func track(_ t: [String: Any]?) -> Track {
        guard let t, let kind = t["kind"] as? String else { return .plain }
        let band = (t["band"] as? NSNumber)?.intValue ?? 0
        switch kind {
        case "centered": return .centered
        case "temp": return .temp
        case "tint": return .tint
        case "rainbow": return .rainbow
        case "hue": return .hue(band: band)
        case "sat": return .sat(band: band)
        case "lum": return .lum(band: band)
        case "gradient": return .gradient(from: t["from"] as? String ?? "#7a7a7a", to: t["to"] as? String ?? "#ffffff")
        default: return .plain
        }
    }

    /// Facts about the active photo (`photo.inspect`): name, rating, flag.
    func info() async -> PhotoInfo? {
        guard let d = try? await execute("photo.inspect") as? [String: Any] else { return nil }
        return PhotoInfo(name: d["file_name"] as? String ?? "", rating: (d["rating"] as? NSNumber)?.intValue ?? 0,
                         flag: d["flag"] as? String ?? "none", edited: !(d["edited"] is NSNull) && d["edited"] != nil)
    }

    /// Point curve of one channel from `develop.get`.
    func curve(_ channel: String) async -> [CGPoint] {
        guard let d = try? await execute("develop.get") as? [String: Any],
              let c = (d["curve"] as? [String: Any])?[channel] as? [[NSNumber]] else { return [] }
        return c.compactMap { $0.count == 2 ? CGPoint(x: $0[0].doubleValue, y: $0[1].doubleValue) : nil }
    }
}

struct PhotoInfo { var name: String; var rating: Int; var flag: String; var edited: Bool }

enum EngineError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
