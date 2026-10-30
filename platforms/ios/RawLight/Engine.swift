import Foundation
import UIKit

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
    var centered: Bool { min < 0 && max > 0 }
}

/// Thin Swift wrapper over the Rust C ABI. All engine work runs on one serial queue.
final class Engine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "rawlight.engine", qos: .userInitiated)
    private var session: OpaquePointer?

    init(demo: Bool) {
        queue.sync { self.session = rl_session_new(demo ? 1 : 0) }
    }

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

    deinit { if let s = session { rl_session_free(s) } }

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

    /// Render a photo with its current edits, fitted in `maxEdge` x `maxEdge`.
    func render(_ id: UInt64, maxEdge: Int) async -> UIImage? {
        await withCheckedContinuation { cont in
            queue.async {
                var w: UInt32 = 0, h: UInt32 = 0, len: UInt = 0
                guard let p = rl_render(self.session, id, UInt32(maxEdge), UInt32(maxEdge), &w, &h, &len) else {
                    return cont.resume(returning: nil)
                }
                let data = Data(bytes: p, count: Int(len))
                rl_buffer_free(p, len)
                cont.resume(returning: Self.image(rgba: data, width: Int(w), height: Int(h)))
            }
        }
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
                           step: (d["step"] as? NSNumber)?.doubleValue ?? 1, decimals: (d["decimals"] as? NSNumber)?.intValue ?? 0)
        }
    }
}

enum EngineError: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let m) = self { return m }; return nil }
}
