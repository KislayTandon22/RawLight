import SwiftUI

/// The Colour group, split into small steps instead of one long list:
/// Basic (white balance, vibrance, saturation), Mixer (one colour at a time), Grading (shadows,
/// midtones, highlights), B&W mix and Calibration.
struct ColourPanel: View {
    let controls: [Control]
    let set: (String, Double, Bool) -> Void
    @Binding var tab: String
    @Binding var band: String
    @Binding var picking: Bool
    @State private var range = "shadows"
    @State private var extra = "B&W"

    private let bands: [(id: String, name: String, color: Color)] = [
        ("red", "Red", Color(hex: "#e0383c")), ("orange", "Orange", Color(hex: "#e8862e")), ("yellow", "Yellow", Color(hex: "#e6d030")),
        ("green", "Green", Color(hex: "#3cc050")), ("aqua", "Aqua", Color(hex: "#30c4c0")), ("blue", "Blue", Color(hex: "#3a6ee8")),
        ("purple", "Purple", Color(hex: "#9a48d8")), ("magenta", "Magenta", Color(hex: "#d840b0")),
    ]
    private let ranges = [("shadows", "Shadows"), ("midtones", "Midtones"), ("highlights", "Highlights"), ("global", "Global")]

    private func ctl(_ id: String) -> Control? { controls.first { $0.id == id } }
    private func slider(_ id: String, label: String? = nil) -> some View {
        Group {
            if var c = ctl(id) {
                let _ = { if let label { c = Control(id: c.id, label: label, section: c.section, min: c.min, max: c.max, def: c.def, value: c.value, step: c.step, decimals: c.decimals, track: c.track) } }()
                ColorSlider(control: c, onChange: { set(id, $0, false) }, onEnd: { v in set(id, v, true) }, reset: { set(id, c.def, true) }, compact: tab != "Basic")
            }
        }
    }
    private var hasBW: Bool { ctl("bw.red") != nil }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(["Basic", "Mixer", "Grading", "More"], id: \.self) { t in
                    Button { withAnimation(.snappy) { tab = t } } label: {
                        Text(t).font(.subheadline.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8).frame(maxWidth: .infinity).frame(height: 38)
                            .fieldBackground(tab == t, in: Capsule()).foregroundStyle(tab == t ? .white : .primary)
                    }
                }
            }
            Group {
                switch tab {
                case "Basic": basic
                case "Mixer": mixer
                case "Grading": grading
                default: more
                }
            }
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
    }

    private var basic: some View {
        VStack(spacing: 8) {
            hint("Set overall colour strength. White balance is in the Light tab.")
            slider("color.vibrance"); slider("color.saturation")
        }
    }

    private var mixer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Button { picking.toggle() } label: {
                    Image(systemName: "eyedropper").font(.system(size: 15, weight: .medium))
                        .frame(width: 34, height: 34).fieldBackground(picking, in: Circle()).foregroundStyle(picking ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityLabel("Pick colour from photo")
                ForEach(bands, id: \.id) { b in
                    Button { withAnimation(.snappy) { band = b.id } } label: {
                        Circle().fill(b.color).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(.white, lineWidth: band == b.id ? 3 : 0))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityLabel(b.name)
                }
            }
            if picking { hint("Tap a colour in the photo") }
            slider("mixer.\(band).hue", label: "Hue"); slider("mixer.\(band).sat", label: "Saturation"); slider("mixer.\(band).lum", label: "Luminance")
            Button("Reset \(bands.first { $0.id == band }?.name ?? "colour")") {
                for k in ["hue", "sat", "lum"] { if let c = ctl("mixer.\(band).\(k)") { set(c.id, c.def, true) } }
            }.font(.footnote).buttonStyle(.bordered).tint(Theme.accent)
        }
    }

    private var grading: some View {
        VStack(spacing: 8) {
            Picker("Range", selection: $range) { ForEach(ranges, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.segmented)
            slider("grading.\(range).hue", label: "Hue"); slider("grading.\(range).sat", label: "Saturation"); slider("grading.\(range).lum", label: "Luminance")
            if range == "global" { EmptyView() } else { slider("grading.blending"); slider("grading.balance") }
        }
    }

    private var more: some View {
        VStack(spacing: 8) {
            Picker("More", selection: $extra) { Text("B&W mix").tag("B&W"); Text("Calibration").tag("Calibration") }.pickerStyle(.segmented)
            if extra == "B&W" { bw } else { calibration }
        }
    }

    private var bw: some View {
        VStack(spacing: 8) {
            hint(hasBW ? "Choose how bright each colour turns out in black and white." : "Turn on B&W to use the mix.")
            ForEach(bands, id: \.id) { slider("bw.\($0.id)") }
        }
    }

    private var calibration: some View {
        VStack(spacing: 8) {
            hint("Fine-tune how the camera renders red, green and blue.")
            slider("calibration.shadowsTint")
            ForEach(["red", "green", "blue"], id: \.self) { c in slider("calibration.\(c)Hue"); slider("calibration.\(c)Sat") }
        }
    }
}
