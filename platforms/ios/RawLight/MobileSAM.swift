import Foundation
import CoreML
import CoreGraphics

/// Tap-to-select with MobileSAM (Apache-2.0), run through Core ML on device. The image is encoded once per photo; every tap
/// (include or exclude) only runs the small decoder. The prompt encoding follows the SAM paper and the reference
/// Swift port in john-rocky/SamKit (Apache-2.0); see assets/ATTRIBUTION.md.
final class MobileSAM {
    static let shared = MobileSAM()

    private let encoder: MLModel?
    private let decoder: MLModel?
    private let weights: Prompt?
    private let lock = NSLock()
    private var cacheKey: UInt64 = .max
    private var embeddings: MLMultiArray?
    private var scale: Float = 1
    private var scaledW = 0, scaledH = 0

    private let size = 1024, embedDim = 256, embedSide = 64, maxPoints = 9

    struct Prompt {
        let gaussian: [Float]          // 2 × 128, row-major
        let points: [[Float]]          // 4 × 256: negative, positive, box corners
        let notAPoint: [Float]
        let noMask: [Float]
    }

    var available: Bool { encoder != nil && decoder != nil && weights != nil }

    private init() {
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .all   // the configuration the conversion was verified against
        func load(_ name: String) -> MLModel? {
            guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { return nil }
            return try? MLModel(contentsOf: url, configuration: cfg)
        }
        encoder = load("mobile_sam_encoder")
        decoder = load("mobile_sam_decoder")
        if let url = Bundle.main.url(forResource: "mobile_sam_prompt_encoder_weights", withExtension: "json"),
           let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let gm = json["gaussian_matrix"] as? [[Double]], let pe = json["point_embeddings"] as? [[Double]],
           let nap = json["not_a_point_embed"] as? [Double], let nm = json["no_mask_embed"] as? [Double] {
            weights = Prompt(gaussian: gm.flatMap { $0.map { Float($0) } }, points: pe.map { $0.map { Float($0) } },
                             notAPoint: nap.map { Float($0) }, noMask: nm.map { Float($0) })
        } else { weights = nil }
    }

    /// Writes `side × side` logits (±8, positive = selected) for the photo; false when the model isn't available or failed.
    func segment(rgb: UnsafePointer<UInt8>, w: Int, h: Int, key: UInt64, clicks: [(Float, Float, Bool)],
                 out: UnsafeMutablePointer<Float>, side: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard available, let encoder, let decoder, let weights, w > 0, h > 0, !clicks.isEmpty else { return false }
        do {
            if key != cacheKey || embeddings == nil {
                guard let input = image(rgb: rgb, w: w, h: h) else { return false }
                let r = try encoder.prediction(from: try MLDictionaryFeatureProvider(dictionary: ["image": input]))
                embeddings = r.featureValue(for: "image_embeddings")?.multiArrayValue
                cacheKey = key
            }
            guard let embeddings else { return false }
            let pts = Array(clicks.suffix(maxPoints))
            let sparse = try sparseEmbeddings(pts, weights: weights, w: w, h: h)
            let dense = try denseEmbeddings(weights)
            let result = try decoder.prediction(from: try MLDictionaryFeatureProvider(dictionary: [
                "image_embeddings": embeddings, "sparse_embeddings": sparse, "dense_embeddings": dense]))
            guard let masks = result.featureValue(for: "masks")?.multiArrayValue,
                  let iou = result.featureValue(for: "iou_predictions")?.multiArrayValue else { return false }
            sample(masks, index: pick(masks, iou, single: pts.count == 1), w: w, h: h, into: out, side: side)
            return true
        } catch { return false }
    }

    // MARK: input

    /// Resize so the long side is 1024, normalise with SAM's mean and std, pad bottom and right with zeros.
    private func image(rgb: UnsafePointer<UInt8>, w: Int, h: Int) -> MLMultiArray? {
        scale = Float(size) / Float(max(w, h))
        scaledW = max(1, Int((Float(w) * scale).rounded())); scaledH = max(1, Int((Float(h) * scale).rounded()))
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { rgba[i * 4] = rgb[i * 3]; rgba[i * 4 + 1] = rgb[i * 3 + 1]; rgba[i * 4 + 2] = rgb[i * 3 + 2] }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                               decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        var px = [UInt8](repeating: 0, count: scaledW * scaledH * 4)
        let drawn: Bool = px.withUnsafeMutableBytes { buf in
            guard let ctx = CGContext(data: buf.baseAddress, width: scaledW, height: scaledH, bitsPerComponent: 8, bytesPerRow: scaledW * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: scaledW, height: scaledH))
            return true
        }
        guard drawn, let arr = try? MLMultiArray(shape: [1, 3, size as NSNumber, size as NSNumber], dataType: .float32) else { return nil }
        let p = arr.dataPointer.bindMemory(to: Float32.self, capacity: arr.count)
        p.update(repeating: 0, count: arr.count)
        let mean: [Float] = [123.675, 116.28, 103.53], std: [Float] = [58.395, 57.12, 57.375]
        let plane = size * size
        for y in 0..<scaledH {
            for x in 0..<scaledW {
                let o = (y * scaledW + x) * 4
                for c in 0..<3 { p[c * plane + y * size + x] = (Float(px[o + c]) - mean[c]) / std[c] }
            }
        }
        return arr
    }

    /// Point tokens (random Fourier position encoding + the learned label embedding) followed by SAM's padding token.
    private func sparseEmbeddings(_ clicks: [(Float, Float, Bool)], weights: Prompt, w: Int, h: Int) throws -> MLMultiArray {
        let n = clicks.count + 1
        let arr = try MLMultiArray(shape: [1, n as NSNumber, embedDim as NSNumber], dataType: .float32)
        let p = arr.dataPointer.bindMemory(to: Float32.self, capacity: arr.count)
        let half = embedDim / 2
        for (i, c) in clicks.enumerated() {
            let mx = c.0 * Float(w) * scale + 0.5, my = c.1 * Float(h) * scale + 0.5
            let sx = 2 * (mx / Float(size)) - 1, sy = 2 * (my / Float(size)) - 1
            let label = weights.points[c.2 ? 1 : 0]
            for j in 0..<half {
                let angle = (sx * weights.gaussian[j] + sy * weights.gaussian[half + j]) * 2 * .pi
                p[i * embedDim + j] = sin(angle) + label[j]
                p[i * embedDim + half + j] = cos(angle) + label[half + j]
            }
        }
        for d in 0..<embedDim { p[(n - 1) * embedDim + d] = weights.notAPoint[d] }
        return arr
    }

    private func denseEmbeddings(_ weights: Prompt) throws -> MLMultiArray {
        let arr = try MLMultiArray(shape: [1, embedDim as NSNumber, embedSide as NSNumber, embedSide as NSNumber], dataType: .float32)
        let p = arr.dataPointer.bindMemory(to: Float32.self, capacity: arr.count)
        let plane = embedSide * embedSide
        for c in 0..<embedDim { (p + c * plane).update(repeating: weights.noMask[c], count: plane) }
        return arr
    }

    // MARK: output

    /// SAM returns nested guesses (part, larger part, whole object). One tap is ambiguous, and the highest-scoring guess is
    /// often just a part (a head, a wing), so with a single tap take the largest guess that is still confident.
    /// With several taps the user has said what they mean, so the best score wins.
    private func pick(_ masks: MLMultiArray, _ iou: MLMultiArray, single: Bool) -> Int {
        let count = min(masks.shape.count > 1 ? masks.shape[1].intValue : 1, iou.count)
        guard count > 1 else { return 0 }
        var best = 0
        for k in 1..<count where iou[k].floatValue > iou[best].floatValue { best = k }
        guard single else { return best }
        let strides = masks.strides.map { $0.intValue }
        let base = masks.dataPointer.bindMemory(to: Float32.self, capacity: masks.count)
        func area(_ k: Int) -> Int {
            var n = 0
            for y in 0..<256 { for x in 0..<256 where base[k * strides[1] + y * strides[2] + x * strides[3]] > 0 { n += 1 } }
            return n
        }
        let floor = max(0.7, iou[best].floatValue - 0.06)
        let valid = Float(max(1, (scaledW / 4) * (scaledH / 4)))
        let bestArea = area(best)
        var pickIdx = best, bigArea = bestArea
        for k in 0..<count where k != best && iou[k].floatValue >= floor {
            let a = area(k)
            // a guess that swallows the background is not "the whole object": cap it relative to the best one and to the photo
            if a > bigArea, a <= bestArea * 3, Float(a) <= valid * 0.6 { bigArea = a; pickIdx = k }
        }
        return pickIdx
    }

    /// 256×256 logits of the padded model frame → `side × side` logits of the photo (bilinear, clamped to ±8).
    private func sample(_ masks: MLMultiArray, index: Int, w: Int, h: Int, into out: UnsafeMutablePointer<Float>, side: Int) {
        let n = 256
        let strides = masks.strides.map { $0.intValue }
        let base = masks.dataPointer.bindMemory(to: Float32.self, capacity: masks.count)
        func at(_ x: Int, _ y: Int) -> Float { base[index * strides[1] + min(n - 1, max(0, y)) * strides[2] + min(n - 1, max(0, x)) * strides[3]] }
        let k = scale / Float(size / n)   // photo pixels → mask cells
        for sy in 0..<side {
            for sx in 0..<side {
                let fx = (Float(sx) + 0.5) / Float(side) * Float(w) * k - 0.5
                let fy = (Float(sy) + 0.5) / Float(side) * Float(h) * k - 0.5
                let x0 = Int(floor(fx)), y0 = Int(floor(fy))
                let tx = fx - Float(x0), ty = fy - Float(y0)
                let v = (at(x0, y0) * (1 - tx) + at(x0 + 1, y0) * tx) * (1 - ty) + (at(x0, y0 + 1) * (1 - tx) + at(x0 + 1, y0 + 1) * tx) * ty
                out[sy * side + sx] = max(-8, min(8, v))
            }
        }
    }
}
