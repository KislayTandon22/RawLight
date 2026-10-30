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
    /// Called when the finger lifts, with the final value (read from here, not from a possibly stale `Control`).
    let onEnd: (Double) -> Void
    @State private var live: Double?
    let reset: () -> Void
    /// A slimmer row without its own card, for long lists such as the colour mixer.
    var compact = false

    private var fraction: Double { (control.value - control.min) / max(control.max - control.min, .ulpOfOne) }
    private var neutral: Double { (control.def - control.min) / max(control.max - control.min, .ulpOfOne) }

    var body: some View {
        let row = VStack(spacing: compact ? 1 : 4) {
            HStack {
                Text(control.label).font(compact ? .footnote : .subheadline)
                Spacer()
                Text(String(format: "%.\(control.decimals)f", control.value))
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).accessibilityIdentifier("value.\(control.id)")
                Button(action: reset) {
                    Image(systemName: "arrow.counterclockwise").font(.caption.weight(.semibold))
                        .frame(width: 28, height: 28).fieldBackground(in: Circle())
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).opacity(control.value == control.def ? 0.3 : 1)
            }
            GeometryReader { geo in
                let w = geo.size.width, h: CGFloat = compact ? 20 : 30
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
                .frame(height: compact ? 32 : 44)
                .overlay {
                    SliderTouch(onChanged: { x in
                        let f = min(max(x / w, 0), 1)
                        var val = control.min + f * (control.max - control.min)
                        if control.step > 0 { val = (val / control.step).rounded() * control.step }
                        // snap to the neutral point so zero is easy to hit
                        if abs(f - neutral) < 0.015 { val = control.def }
                        let v = min(max(val, control.min), control.max)
                        live = v
                        onChange(v)
                    }, onEnded: { onEnd(live ?? control.value); live = nil })
                }
                .accessibilityElement().accessibilityIdentifier("slider.\(control.id)")
            }
            .frame(height: compact ? 32 : 44)
        }
        return Group {
            if compact { row.padding(.horizontal, 6).padding(.vertical, 1) }
            else { row.padding(.horizontal, 12).padding(.vertical, 6).fieldBackground(in: RoundedRectangle(cornerRadius: 16, style: .continuous)) }
        }
    }
}
