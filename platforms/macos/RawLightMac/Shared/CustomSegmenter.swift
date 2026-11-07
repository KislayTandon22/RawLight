import Foundation
import CoreML
import CoreGraphics

/// Lets the user bring their own Core ML model for the Sky and Background masks.
///
/// A model qualifies when it has one image input and produces a mask: an image, or an array shaped `[H, W]`, `[1, H, W]` or
/// `[1, 1, H, W]`, covering the whole photo, where larger values mean "this is the region". Probabilities (0 to 1), 8-bit
/// values (0 to 255) and logits all work. The model is compiled once and kept in the app's Application Support folder.
@Observable final class CustomSegmenter {
    static let shared = CustomSegmenter()
    enum Role: String, CaseIterable { case sky, background
        var title: String { self == .sky ? "Sky" : "Background" }
        /// Marker the Sky/Background tiles put in an Object mask's point, so the segmenter knows which model to run.
        var marker: Float { self == .sky ? 0.00001 : 0.00002 }
    }

    /// Names shown in Settings; refreshed after an install or removal.
    var names: [Role: String] = [:]
    var error: String?

    private var models: [Role: MLModel] = [:]
    private let lock = NSLock()

    private init() { for r in Role.allCases { if let n = UserDefaults.standard.string(forKey: "custom.\(r.rawValue).name"), FileManager.default.fileExists(atPath: folder(r).path) { names[r] = n } } }

    func isInstalled(_ r: Role) -> Bool { names[r] != nil }
    func invert(_ r: Role) -> Bool { UserDefaults.standard.bool(forKey: "custom.\(r.rawValue).invert") }
    func setInvert(_ r: Role, _ on: Bool) { UserDefaults.standard.set(on, forKey: "custom.\(r.rawValue).invert") }

    private func base() -> URL {
        let d = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appending(path: "RawLight/CustomModels", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func folder(_ r: Role) -> URL { base().appending(path: "\(r.rawValue).mlmodelc", directoryHint: .isDirectory) }

    /// Compiles (when needed) and stores the picked model, then checks it can be loaded and has an image input.
    func install(_ picked: URL, as role: Role) async {
        error = nil
        let access = picked.startAccessingSecurityScopedResource()
        defer { if access { picked.stopAccessingSecurityScopedResource() } }
        do {
            let compiled: URL = picked.pathExtension == "mlmodelc" ? picked : try await MLModel.compileModel(at: picked)
            let dest = folder(role)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: compiled, to: dest)
            let m = try MLModel(contentsOf: dest)
            guard m.modelDescription.inputDescriptionsByName.values.contains(where: { $0.imageConstraint != nil }) else {
                try? FileManager.default.removeItem(at: dest)
                error = "That model has no image input, so it can't take a photo."
                return
            }
            lock.lock(); models[role] = m; lock.unlock()
            let name = picked.deletingPathExtension().lastPathComponent
            UserDefaults.standard.set(name, forKey: "custom.\(role.rawValue).name")
            names[role] = name
        } catch {
            self.error = "Couldn't use that model: \(error.localizedDescription)"
        }
    }

    func remove(_ role: Role) {
        try? FileManager.default.removeItem(at: folder(role))
        lock.lock(); models[role] = nil; lock.unlock()
        UserDefaults.standard.removeObject(forKey: "custom.\(role.rawValue).name")
        names[role] = nil
    }

    private func model(_ r: Role) -> MLModel? {
        lock.lock(); defer { lock.unlock() }
        if let m = models[r] { return m }
        guard isInstalled(r), let m = try? MLModel(contentsOf: folder(r)) else { return nil }
        models[r] = m
        return m
    }

    /// Runs the role's model on the photo and writes `side × side` logits (±8, positive = selected). False on any failure.
    func run(_ role: Role, rgb: UnsafePointer<UInt8>, w: Int, h: Int, out: UnsafeMutablePointer<Float>, side: Int) -> Bool {
        guard let m = model(role), w > 0, h > 0,
              let input = m.modelDescription.inputDescriptionsByName.first(where: { $0.value.imageConstraint != nil }),
              let constraint = input.value.imageConstraint, let cg = Self.image(rgb: rgb, w: w, h: h),
              let value = try? MLFeatureValue(cgImage: cg, constraint: constraint, options: nil),
              let result = try? m.prediction(from: MLDictionaryFeatureProvider(dictionary: [input.key: value])) else { return false }
        for name in result.featureNames {
            guard let f = result.featureValue(for: name) else { continue }
            var plane: [Float]?, pw = 0, ph = 0
            if let buf = f.imageBufferValue { (plane, pw, ph) = Self.read(buf) }
            else if let arr = f.multiArrayValue { (plane, pw, ph) = Self.read(arr) }
            guard var p = plane, pw > 1, ph > 1 else { continue }
            if invert(role) { Self.invertInPlace(&p) }
            Self.resample(p, pw, ph, into: out, side: side)
            return true
        }
        return false
    }

    private static func image(rgb: UnsafePointer<UInt8>, w: Int, h: Int) -> CGImage? {
        var rgba = [UInt8](repeating: 255, count: w * h * 4)
        for i in 0..<(w * h) { rgba[i * 4] = rgb[i * 3]; rgba[i * 4 + 1] = rgb[i * 3 + 1]; rgba[i * 4 + 2] = rgb[i * 3 + 2] }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: space,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    // MARK: reading outputs

    private static func read(_ buf: CVPixelBuffer) -> ([Float]?, Int, Int) {
        CVPixelBufferLockBaseAddress(buf, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buf, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buf) else { return (nil, 0, 0) }
        let w = CVPixelBufferGetWidth(buf), h = CVPixelBufferGetHeight(buf), rb = CVPixelBufferGetBytesPerRow(buf)
        var out = [Float](repeating: 0, count: w * h)
        switch CVPixelBufferGetPixelFormatType(buf) {
        case kCVPixelFormatType_OneComponent8:
            for y in 0..<h { for x in 0..<w { out[y * w + x] = Float(base.load(fromByteOffset: y * rb + x, as: UInt8.self)) / 255 } }
        case kCVPixelFormatType_OneComponent16Half:
            for y in 0..<h { for x in 0..<w { out[y * w + x] = Float(base.load(fromByteOffset: y * rb + x * 2, as: Float16.self)) } }
        case kCVPixelFormatType_OneComponent32Float:
            for y in 0..<h { for x in 0..<w { out[y * w + x] = base.load(fromByteOffset: y * rb + x * 4, as: Float32.self) } }
        case kCVPixelFormatType_32BGRA, kCVPixelFormatType_32ARGB, kCVPixelFormatType_32RGBA:
            for y in 0..<h { for x in 0..<w { out[y * w + x] = Float(base.load(fromByteOffset: y * rb + x * 4 + 1, as: UInt8.self)) / 255 } }
        default: return (nil, 0, 0)
        }
        return (out, w, h)
    }

    private static func read(_ arr: MLMultiArray) -> ([Float]?, Int, Int) {
        let shape = arr.shape.map(\.intValue)
        guard shape.count >= 2, let h = shape.dropLast().last, let w = shape.last, h > 0, w > 0, w * h <= 4096 * 4096 else { return (nil, 0, 0) }
        let strides = arr.strides.map(\.intValue)
        let sy = strides[strides.count - 2], sx = strides[strides.count - 1]
        var out = [Float](repeating: 0, count: w * h)   // the first channel / batch entry
        switch arr.dataType {
        case .float32:
            let p = arr.dataPointer.bindMemory(to: Float32.self, capacity: arr.count)
            for y in 0..<h { for x in 0..<w { out[y * w + x] = p[y * sy + x * sx] } }
        case .float16:
            let p = arr.dataPointer.bindMemory(to: Float16.self, capacity: arr.count)
            for y in 0..<h { for x in 0..<w { out[y * w + x] = Float(p[y * sy + x * sx]) } }
        default:
            for y in 0..<h { for x in 0..<w { out[y * w + x] = arr[y * sy + x * sx].floatValue } }
        }
        return (out, w, h)
    }

    /// Flips "region" and "not region", whatever scale the model used.
    private static func invertInPlace(_ p: inout [Float]) {
        guard let lo = p.min(), let hi = p.max() else { return }
        if lo < 0 { for i in p.indices { p[i] = -p[i] } }
        else if hi > 1.5 { for i in p.indices { p[i] = 255 - p[i] } }
        else { for i in p.indices { p[i] = 1 - p[i] } }
    }

    /// Bilinear resample to `side × side` logits.
    private static func resample(_ p: [Float], _ pw: Int, _ ph: Int, into out: UnsafeMutablePointer<Float>, side: Int) {
        let lo = p.min() ?? 0, hi = p.max() ?? 1
        func logit(_ v: Float) -> Float {
            if lo < 0 { return max(-8, min(8, v)) }                // already logits
            if hi > 1.5 { return max(-8, min(8, (v / 255 - 0.5) * 16)) }   // 8-bit
            return max(-8, min(8, (v - 0.5) * 16))                  // probability
        }
        for sy in 0..<side {
            let fy = (Float(sy) + 0.5) / Float(side) * Float(ph) - 0.5
            let y0 = max(0, min(ph - 1, Int(floor(fy)))), y1 = min(ph - 1, y0 + 1), ty = max(0, min(1, fy - Float(y0)))
            for sx in 0..<side {
                let fx = (Float(sx) + 0.5) / Float(side) * Float(pw) - 0.5
                let x0 = max(0, min(pw - 1, Int(floor(fx)))), x1 = min(pw - 1, x0 + 1), tx = max(0, min(1, fx - Float(x0)))
                let v = (p[y0 * pw + x0] * (1 - tx) + p[y0 * pw + x1] * tx) * (1 - ty) + (p[y1 * pw + x0] * (1 - tx) + p[y1 * pw + x1] * tx) * ty
                out[sy * side + sx] = logit(v)
            }
        }
    }
}
