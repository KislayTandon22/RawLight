import SwiftUI

enum Theme {
    /// RawLight rose: red with a slight pink lean.
    static let accent = Color(red: 0.95, green: 0.23, blue: 0.36)
    static let accentSoft = Color(red: 1.0, green: 0.47, blue: 0.59)
    static let panel = Color(white: 0.11)
    static let field = Color.white.opacity(0.07)
}

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        let v = UInt64(s, radix: 16) ?? 0x7a7a7a
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
}

private struct FieldBackground<S: Shape>: ViewModifier {
    let selected: Bool
    let shape: S
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(selected ? Glass.regular.tint(Theme.accent).interactive() : Glass.regular.interactive(), in: shape)
        } else {
            content.background(selected ? Theme.accent : Theme.field, in: shape)
        }
    }
}

private struct PanelBackground<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.glassEffect(.regular, in: shape) } else { content.background(.ultraThinMaterial, in: shape) }
    }
}

extension View {
    /// A control or row background: Liquid Glass on iOS 26+ (accent-tinted when selected), flat fill before.
    func fieldBackground<S: Shape>(_ selected: Bool = false, in shape: S) -> some View { modifier(FieldBackground(selected: selected, shape: shape)) }
    /// A floating panel or bar: Liquid Glass on iOS 26+, material before.
    func panelBackground<S: Shape>(in shape: S) -> some View { modifier(PanelBackground(shape: shape)) }
}
