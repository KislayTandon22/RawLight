import Foundation
import UIKit
import Vision


/// Subject / object selection with `VNGenerateForegroundInstanceMaskRequest` (iPadOS 17+), on the
/// Neural Engine. The instance map of the last photo is kept, so each tap only picks instances.
@available(iOS 17.0, *)
private final class VisionSegmenter {
    private var key: UInt64 = .max
    private var handler: VNImageRequestHandler?
    private var observation: VNInstanceMaskObservation?
    private let lock = NSLock()

    func segment(rgb: UnsafePointer<UInt8>, w: Int, h: Int, key: UInt64, clicks: [(Float, Float, Bool)],
                 out: UnsafeMutablePointer<Float>, side: Int) -> Int32 {
        lock.lock(); defer { lock.unlock() }
        var visionFailed = false
        if key != self.key || handler == nil {
            guard let cg = Self.image(rgb: rgb, w: w, h: h) else { return -3 }
            let request = VNGenerateForegroundInstanceMaskRequest()
            let newHandler = VNImageRequestHandler(cgImage: cg, options: [:])
            do { try newHandler.perform([request]) } catch { visionFailed = true }
            self.key = key
            handler = visionFailed ? nil : newHandler
            observation = visionFailed ? nil : request.results?.first
        }
        // Vision unavailable (older chips, the simulator): taps still work by colour region growing
        if visionFailed || observation == nil || handler == nil {
            let include = clicks.filter { $0.2 }, exclude = clicks.filter { !$0.2 }
            if include.isEmpty { return visionFailed ? -4 : 0 }
            for i in 0..<(side * side) { out[i] = -8 }
            for c in include { let m = RegionGrow.select(rgb: rgb, w: w, h: h, side: side, x: c.0, y: c.1); for i in 0..<m.count where m[i] > 0.5 { out[i] = 8 } }
            for c in exclude { let m = RegionGrow.select(rgb: rgb, w: w, h: h, side: side, x: c.0, y: c.1); for i in 0..<m.count where m[i] > 0.5 { out[i] = -8 } }
            return 1
        }
        guard let observation, let handler else { return 0 }
        var instances = IndexSet()
        var growIn: [(Float, Float)] = [], growOut: [(Float, Float)] = []
        if clicks.isEmpty {
            instances = observation.allInstances
        } else {
            // a tap on something Vision did not call a subject falls back to colour region growing
            for c in clicks {
                let i = instance(at: c, in: observation)
                if c.2 { if let i, i > 0 { instances.insert(i) } else { growIn.append((c.0, c.1)) } }
                else if let i { instances.remove(i) } else { growOut.append((c.0, c.1)) }
            }
        }
        if instances.isEmpty, growIn.isEmpty { return 0 }
        if !instances.isEmpty {
            guard let mask = try? observation.generateScaledMaskForImage(forInstances: instances, from: handler) else { return -5 }
            Self.sample(mask, into: out, side: side)
        } else {
            for i in 0..<(side * side) { out[i] = -8 }
        }
        for g in growIn {
            let cover = RegionGrow.select(rgb: rgb, w: w, h: h, side: side, x: g.0, y: g.1)
            for i in 0..<cover.count where cover[i] > 0.5 { out[i] = 8 }
        }
        for g in growOut {
            let cover = RegionGrow.select(rgb: rgb, w: w, h: h, side: side, x: g.0, y: g.1)
            for i in 0..<cover.count where cover[i] > 0.5 { out[i] = -8 }
        }
        return 1
    }

    /// The instance under a click, or the nearest one within a fingertip so taps near an edge still land.
    private func instance(at c: (Float, Float, Bool), in o: VNInstanceMaskObservation) -> Int? {
        let map = o.instanceMask
        CVPixelBufferLockBaseAddress(map, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(map, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(map) else { return nil }
        let mw = CVPixelBufferGetWidth(map), mh = CVPixelBufferGetHeight(map), rowBytes = CVPixelBufferGetBytesPerRow(map)
        let cx = Int(max(0, min(1, c.0)) * Float(mw - 1)), cy = Int(max(0, min(1, c.1)) * Float(mh - 1))
        let reach = max(2, max(mw, mh) / 22)
        var best: (Int, Int)? = nil  // (distance², instance)
        for dy in stride(from: -reach, through: reach, by: 2) {
            for dx in stride(from: -reach, through: reach, by: 2) {
                let x = cx + dx, y = cy + dy
                if x < 0 || y < 0 || x >= mw || y >= mh { continue }
                let v = Int(base.load(fromByteOffset: y * rowBytes + x, as: UInt8.self))
                if v == 0 { continue }
                let d = dx * dx + dy * dy
                if best == nil || d < best!.0 { best = (d, v) }
            }
        }
        return best?.1
    }

    private static func image(rgb: UnsafePointer<UInt8>, w: Int, h: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) {
            rgba[i * 4] = rgb[i * 3]; rgba[i * 4 + 1] = rgb[i * 3 + 1]; rgba[i * 4 + 2] = rgb[i * 3 + 2]
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Coverage 0...1 (one float per pixel) → `side × side` logits (±8) for the engine's soft mask.
    private static func sample(_ buf: CVPixelBuffer, into out: UnsafeMutablePointer<Float>, side: Int) {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return }
        let bw = CVPixelBufferGetWidth(buf), bh = CVPixelBufferGetHeight(buf), rowBytes = CVPixelBufferGetBytesPerRow(buf)
        for sy in 0..<side {
            for sx in 0..<side {
                var sum: Float = 0
                for (ox, oy) in [(0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75)] as [(Double, Double)] {
                    let x = min(bw - 1, Int((Double(sx) + ox) / Double(side) * Double(bw)))
                    let y = min(bh - 1, Int((Double(sy) + oy) / Double(side) * Double(bh)))
                    sum += base.load(fromByteOffset: y * rowBytes + x * 4, as: Float.self)
                }
                out[sy * side + sx] = (sum / 4 - 0.5) * 16
            }
        }
    }
}

@available(iOS 17.0, *)
private let visionSegmenter = VisionSegmenter()

private func visionSegmentEntry(
    _ rgb: UnsafePointer<UInt8>?, _ w: Int32, _ h: Int32, _ key: UInt64,
    _ clicks: UnsafePointer<Float>?, _ n: Int32, _ out: UnsafeMutablePointer<Float>?, _ side: Int32
) -> Int32 {
    guard #available(iOS 17.0, *) else { return -2 }
    guard let rgb, let out, w > 0, h > 0, side > 0 else { return -1 }
    var list: [(Float, Float, Bool)] = []
    if let clicks { for i in 0..<Int(max(0, n)) { list.append((clicks[i * 3], clicks[i * 3 + 1], clicks[i * 3 + 2] > 0.5)) } }
    return visionSegmenter.segment(rgb: rgb, w: Int(w), h: Int(h), key: key, clicks: list, out: out, side: Int(side))
}

/// Hand the engine the Vision segmenter (call once at launch).
func installVisionSegmenter() {
    rl_set_segmenter(visionSegmentEntry)
}
