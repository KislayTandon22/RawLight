import SwiftUI

private let bandColors: [Color] = [
    Color(hex: "#e0383c"), Color(hex: "#e8862e"), Color(hex: "#e6d030"), Color(hex: "#3cc050"),
    Color(hex: "#30c4c0"), Color(hex: "#3a6ee8"), Color(hex: "#9a48d8"), Color(hex: "#d840b0"),
]

private func trackGradient(_ t: Track) -> LinearGradient? {
    func g(_ c: [Color]) -> LinearGradient { LinearGradient(colors: c, startPoint: .leading, endPoint: .trailing) }
    switch t {
    case .temp: return g([Color(hex: "#3f8cff"), Color(hex: "#d8d8d8"), Color(hex: "#ffb82e")])
    case .tint: return g([Color(hex: "#3cc46e"), Color(hex: "#d8d8d8"), Color(hex: "#e040c0")])
    case .rainbow: return g((0...6).map { Color(hue: Double($0) / 6, saturation: 0.85, brightness: 0.95) })
    case .gradient(let from, let to): return g([Color(hex: from), Color(hex: to)])
    case .hue(let b):
        let c = bandColors[b % 8], p = bandColors[(b + 7) % 8], n = bandColors[(b + 1) % 8]
        return g([p, c, n])
    case .sat(let b): return g([Color(hex: "#7a7a7a"), bandColors[b % 8]])
    case .lum(let b): return g([Color(hex: "#141414"), bandColors[b % 8], Color(hex: "#f2f2f2")])
    case .plain, .centered: return nil
    }
}

/// 44pt capsule slider. Colour tracks come from the engine's track kind; plain and centred
/// tracks fill in the accent colour from the neutral point.
struct ColorSlider: View {
    let control: Control
    let onChange: (Double) -> Void
    let onEnd: () -> Void
    let reset: () -> Void

    private var fraction: Double { (control.value - control.min) / max(control.max - control.min, .ulpOfOne) }
    private var neutral: Double { (control.def - control.min) / max(control.max - control.min, .ulpOfOne) }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(control.label).font(.subheadline)
                Spacer()
                Text(String(format: "%.\(control.decimals)f", control.value))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise").font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28).fieldBackground(in: Circle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).opacity(control.value == control.def ? 0.3 : 1)
            }
            GeometryReader { geo in
                let w = geo.size.width, h: CGFloat = 30
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(height: h)
                    if let g = trackGradient(control.track) {
                        Capsule().fill(g).frame(height: h)
                    } else {
                        let a = min(fraction, neutral), b = max(fraction, neutral)
                        Capsule().fill(Theme.accent).frame(width: max((b - a) * w, 0), height: h).offset(x: a * w)
                    }
                    Circle().fill(.white).frame(width: h + 4, height: h + 4)
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .offset(x: min(max(fraction * w - (h + 4) / 2, -2), w - (h + 4) / 2 + 2))
                }
                .frame(height: 44)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let f = min(max(v.location.x / w, 0), 1)
                        var val = control.min + f * (control.max - control.min)
                        if control.step > 0 { val = (val / control.step).rounded() * control.step }
                        // snap to the neutral point so zero is easy to hit
                        if abs(f - neutral) < 0.015 { val = control.def }
                        onChange(min(max(val, control.min), control.max))
                    }
                    .onEnded { _ in onEnd() })
            }
            .frame(height: 44)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
