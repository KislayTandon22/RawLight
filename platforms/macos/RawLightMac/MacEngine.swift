import AppKit
import Foundation

/// Minimal macOS wrapper over the Rust C ABI (same calls as the iPad `Engine`).
final class MacEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "rawlight.engine", qos: .userInitiated)
    private let thumbQueue: OperationQueue = {
        let q = OperationQueue(); q.maxConcurrentOperationCount = 4; q.qualityOfService = .utility; return q
    }()
    private var session: OpaquePointer?

    init(demo: Bool) {
        queue.sync { self.session = rl_session_new(demo ? 1 : 0) }
    }
    deinit { if let s = session { rl_session_free(s) } }

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

    func thumbnail(_ id: UInt64, edge: Int) async -> NSImage? {
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

    private static func image(rgba: Data, width: Int, height: Int) -> NSImage? {
        guard let provider = CGDataProvider(data: rgba as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        guard let cg = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                               space: space, bitmapInfo: info, provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }
}
