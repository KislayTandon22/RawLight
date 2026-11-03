import Foundation
import CoreML
import CoreGraphics

/// Mask from a word: OWL-ViT (Apache-2.0, Core ML, 8-bit weights) finds a box for what the word names, then MobileSAM cuts out
/// what is inside each box. The words are a fixed list whose text embeddings were computed ahead of time, so the app carries no
/// text model or tokenizer. Objects work well; scattered things (trees, mountains, water) do not, and Sky has its own tile.
final class TextMask {
    static let shared = TextMask()
    static let size = 768
    /// Below this the phrase is taken as not being in the photo (absent phrases scored under 0.012 in testing).
    static let threshold: Float = 0.035
    static let marker: Float = 0.5   // an Object mask's point is (0, marker + (index + 1) / 1000)

    let phrases: [String]
    private let embeds: [Float]          // phrases.count × 512, each row unit length
    private let model: MLModel?
    private let lock = NSLock()

    var available: Bool { model != nil && !phrases.isEmpty && MobileSAM.shared.available }

    private init() {
        var names: [String] = [], rows: [Float] = []
        if let u = Bundle.main.url(forResource: "phrases", withExtension: "json"), let d = try? Data(contentsOf: u),
           let a = try? JSONDecoder().decode([String].self, from: d),
           let eu = Bundle.main.url(forResource: "text_embeds", withExtension: "f16"), let ed = try? Data(contentsOf: eu), ed.count == a.count * 512 * 2 {
            names = a
            rows = ed.withUnsafeBytes { raw in raw.bindMemory(to: Float16.self).map { Float($0) } }
        }
        phrases = names; embeds = rows
        let cfg = MLModelConfiguration(); cfg.computeUnits = .all
        if let u = Bundle.main.url(forResource: "owlvit_image_int8", withExtension: "mlmodelc") { model = try? MLModel(contentsOf: u, configuration: cfg) } else { model = nil }
    }

    /// The point an Object mask carries so the segmenter knows which phrase to look for.
    static func point(for index: Int) -> [Double] { [0.0, Double(marker) + Double(index + 1) / 1000] }
    static func index(ofMarker y: Float) -> Int? {
        guard y >= marker + 0.0005 else { return nil }
        return Int(((y - marker) * 1000).rounded()) - 1
    }

    /// Writes `side × side` logits for phrase `index`; 1 on success, 0 when it is not in the photo, negative on failure.
    func run(index: Int, rgb: UnsafePointer<UInt8>, w: Int, h: Int, key: UInt64, out: UnsafeMutablePointer<Float>, side: Int) -> Int32 {
        guard available, phrases.indices.contains(index), w > 0, h > 0 else { return -7 }
        lock.lock(); defer { lock.unlock() }
        guard let input = pixels(rgb: rgb, w: w, h: h), let result = try? model?.prediction(from: try MLDictionaryFeatureProvider(dictionary: ["pixel_values": input])),
              let cls = result.featureValue(for: "class_embeds")?.multiArrayValue, let boxes = result.featureValue(for: "pred_boxes")?.multiArrayValue,
              let shift = result.featureValue(for: "logit_shift")?.multiArrayValue, let scale = result.featureValue(for: "logit_scale")?.multiArrayValue
        else { return -8 }
        let n = 576
        let c = floats(cls), b = floats(boxes), sh = floats(shift), sc = floats(scale)
        guard c.count == n * 512, b.count == n * 4, sh.count == n, sc.count == n else { return -8 }
        let q = embeds[(index * 512)..<((index + 1) * 512)]
        var scores = [Float](repeating: 0, count: n)
        for i in 0..<n {
            var dot: Float = 0
            for (k, qv) in q.enumerated() { dot += c[i * 512 + k] * qv }
            scores[i] = 1 / (1 + exp(-(dot + sh[i]) * sc[i]))
        }
        guard let top = scores.max(), top >= Self.threshold else { return 0 }
        // boxes that score at least half the best, with overlapping ones dropped, at most five
        var order = scores.indices.filter { scores[$0] >= top * 0.5 }.sorted { scores[$0] > scores[$1] }
        var kept: [(Float, Float, Float, Float)] = []
        func box(_ i: Int) -> (Float, Float, Float, Float) {
            let cx = b[i * 4], cy = b[i * 4 + 1], bw = b[i * 4 + 2], bh = b[i * 4 + 3]
            return (max(0, cx - bw / 2), max(0, cy - bh / 2), min(1, cx + bw / 2), min(1, cy + bh / 2))
        }
        func iou(_ a: (Float, Float, Float, Float), _ z: (Float, Float, Float, Float)) -> Float {
            let iw = max(0, min(a.2, z.2) - max(a.0, z.0)), ih = max(0, min(a.3, z.3) - max(a.1, z.1))
            let inter = iw * ih, union = (a.2 - a.0) * (a.3 - a.1) + (z.2 - z.0) * (z.3 - z.1) - inter
            return union > 0 ? inter / union : 0
        }
        while let i = order.first, kept.count < 5 {
            let bi = box(i)
            if bi.2 > bi.0, bi.3 > bi.1 { kept.append(bi) }
            order.removeAll { iou(bi, box($0)) > 0.3 || $0 == i }
        }
        guard !kept.isEmpty else { return 0 }
        return MobileSAM.shared.segment(rgb: rgb, w: w, h: h, key: key, boxes: kept, out: out, side: side) ? 1 : -9
    }

    /// The photo squeezed to 768 × 768, scaled to 0...1 and normalised with CLIP's mean and std, channels first.
    private func pixels(rgb: UnsafePointer<UInt8>, w: Int, h: Int) -> MLMultiArray? {
        let s = Self.size
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { rgba[i * 4] = rgb[i * 3]; rgba[i * 4 + 1] = rgb[i * 3 + 1]; rgba[i * 4 + 2] = rgb[i * 3 + 2] }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil,
                               shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        var px = [UInt8](repeating: 0, count: s * s * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: s, height: s, bitsPerComponent: 8, bytesPerRow: s * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: s, height: s))
            return true
        }
        guard drawn, let arr = try? MLMultiArray(shape: [1, 3, s as NSNumber, s as NSNumber], dataType: .float16) else { return nil }
        let p = arr.dataPointer.bindMemory(to: Float16.self, capacity: arr.count)
        let mean: [Float] = [0.48145466, 0.4578275, 0.40821073], std: [Float] = [0.26862954, 0.26130258, 0.27577711]
        let plane = s * s
        for i in 0..<plane { for c in 0..<3 { p[c * plane + i] = Float16((Float(px[i * 4 + c]) / 255 - mean[c]) / std[c]) } }
        return arr
    }

    /// A `[rows, cols]` array as a flat row-major list. Core ML pads rows, so this reads through the strides.
    private func floats(_ a: MLMultiArray) -> [Float] {
        let shape = a.shape.map(\.intValue), strides = a.strides.map(\.intValue)
        guard shape.count == 2 else { return [] }
        let rows = shape[0], cols = shape[1]
        var out = [Float](repeating: 0, count: rows * cols)
        switch a.dataType {
        case .float16:
            let p = a.dataPointer.bindMemory(to: Float16.self, capacity: a.count * 2)
            for r in 0..<rows { for c in 0..<cols { out[r * cols + c] = Float(p[r * strides[0] + c * strides[1]]) } }
        case .float32:
            let p = a.dataPointer.bindMemory(to: Float32.self, capacity: a.count * 2)
            for r in 0..<rows { for c in 0..<cols { out[r * cols + c] = p[r * strides[0] + c * strides[1]] } }
        default:
            for r in 0..<rows { for c in 0..<cols { out[r * cols + c] = a[r * strides[0] + c * strides[1]].floatValue } }
        }
        return out
    }
}
