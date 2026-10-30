import SwiftUI

/// RGB + luma histogram with clipping markers.
struct HistogramView: View {
    let bins: [UInt32]   // 4 x 256: r, g, b, luma

    var body: some View {
        Canvas { ctx, size in
            guard bins.count == 1024 else { return }
            let peak = max(1, (0..<1024).filter { $0 % 256 > 2 && $0 % 256 < 253 }.map { bins[$0] }.max() ?? 1)
            func path(_ c: Int) -> Path {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: size.height))
                for i in 0..<256 {
                    let v = min(Double(bins[c * 256 + i]) / Double(peak), 1)
                    p.addLine(to: CGPoint(x: Double(i) / 255 * size.width, y: size.height - v * size.height * 0.95))
                }
                p.addLine(to: CGPoint(x: size.width, y: size.height))
                p.closeSubpath()
                return p
            }
            ctx.blendMode = .screen
            ctx.fill(path(0), with: .color(.red.opacity(0.7)))
            ctx.fill(path(1), with: .color(.green.opacity(0.7)))
            ctx.fill(path(2), with: .color(.blue.opacity(0.8)))
        }
        .frame(height: 70)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(alignment: .topLeading) { clip(shadows: true) }
        .overlay(alignment: .topTrailing) { clip(shadows: false) }
    }

    private func clip(shadows: Bool) -> some View {
        let n = bins.count == 1024 ? (shadows ? bins[0] + bins[256] + bins[512] : bins[255] + bins[511] + bins[767]) : 0
        return Image(systemName: "triangle.fill").font(.system(size: 9))
            .foregroundStyle(n > 0 ? Theme.accentSoft : Color.white.opacity(0.25)).padding(6)
            .rotationEffect(.degrees(shadows ? -90 : 90))
    }
}
