import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

/// Apple's Core Image noise reduction (GPU accelerated), applied on top of the engine's render for
/// the preview and for JPEG / PNG exports. A per-photo strength 0...100 kept on the device; it is
/// classical filtering, not a machine-learning model.
enum AppleDenoise {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    static func level(_ id: UInt64) -> Double { UserDefaults.standard.double(forKey: "appleDenoise.\(id)") }
    static func setLevel(_ v: Double, for id: UInt64) {
        if v <= 0 { UserDefaults.standard.removeObject(forKey: "appleDenoise.\(id)") } else { UserDefaults.standard.set(v, forKey: "appleDenoise.\(id)") }
    }

    private static func filtered(_ input: CIImage, level: Double) -> CIImage? {
        let f = CIFilter.noiseReduction()
        f.inputImage = input
        f.noiseLevel = Float(level / 100 * 0.1)
        f.sharpness = Float(0.4 + level / 100 * 0.3)
        return f.outputImage?.cropped(to: input.extent)
    }

    /// The image with noise reduction at `level`; the image itself when the level is 0 or filtering fails.
    static func apply(_ image: UIImage, level: Double) -> UIImage {
        guard level > 0, let cg = image.cgImage, let out = filtered(CIImage(cgImage: cg), level: level), let done = context.createCGImage(out, from: out.extent) else { return image }
        return UIImage(cgImage: done, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Rewrites an exported JPEG or PNG file with noise reduction, keeping its metadata. Other formats are left alone.
    @discardableResult
    static func apply(toFile url: URL, level: Double, quality: Double) -> Bool {
        guard level > 0, ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased()),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil), let type = CGImageSourceGetType(src),
              let ci = CIImage(contentsOf: url), let out = filtered(ci, level: level),
              let cg = context.createCGImage(out, from: out.extent, format: .RGBA8, colorSpace: ci.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else { return false }
        var props = (CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImageDestinationLossyCompressionQuality] = quality / 100
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }
}
