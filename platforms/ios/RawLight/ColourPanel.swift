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
                ColorSlider(control: c, onChange: { set(id, $0, false) }, onEnd: { set(id, c.value, true) }, reset: { set(id, c.def, true) })
            }
        }
    }
    private var hasBW: Bool { ctl("bw.red") != nil }

    var body: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Basic", "Mixer", "Grading", "More"], id: \.self) { t in
                        Button { withAnimation(.snappy) { tab = t } } label: {
                            Text(t).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 38)
                                .background(tab == t ? Theme.accent : Theme.field, in: Capsule()).foregroundStyle(tab == t ? .white : .primary)
                        }
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
            hint("Warm or cool the whole photo, then set overall colour strength.")
            slider("wb.temp"); slider("wb.tint"); slider("color.vibrance"); slider("color.saturation")
        }
    }

    private var mixer: some View {
        VStack(spacing: 8) {
            hint("Pick a colour, then shift its hue, saturation and brightness.")
            Button { picking.toggle() } label: {
                Label(picking ? "Tap a colour in the photo…" : "Pick colour from photo", systemImage: "eyedropper")
                    .font(.subheadline.weight(.medium)).frame(maxWidth: .infinity).frame(height: 44)
                    .background(picking ? Theme.accent : Theme.field, in: Capsule()).foregroundStyle(picking ? .white : .primary)
            }
            HStack(spacing: 10) {
                ForEach(bands, id: \.id) { b in
                    Button { withAnimation(.snappy) { band = b.id } } label: {
                        Circle().fill(b.color).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.white, lineWidth: band == b.id ? 3 : 0))
                            .frame(width: 38, height: 44)
                    }
                    .accessibilityLabel(b.name)
                }
            }
            slider("mixer.\(band).hue", label: "Hue"); slider("mixer.\(band).sat", label: "Saturation"); slider("mixer.\(band).lum", label: "Luminance")
            Button("Reset \(bands.first { $0.id == band }?.name ?? "colour")") {
                for k in ["hue", "sat", "lum"] { if let c = ctl("mixer.\(band).\(k)") { set(c.id, c.def, true) } }
            }.font(.footnote).buttonStyle(.bordered).tint(Theme.accent)
        }
    }

    private var grading: some View {
        VStack(spacing: 8) {
            hint("Tint the shadows, midtones and highlights separately.")
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
