import SwiftUI

/// The user's look choices, kept in UserDefaults. Observable so every view that reads `Theme.accent` redraws when it changes.
@Observable final class ThemeStore {
    static let shared = ThemeStore()
    static let accents: [(name: String, label: String, base: Color, soft: Color)] = [
        ("rose", "Rose", Color(red: 0.95, green: 0.23, blue: 0.36), Color(red: 1.0, green: 0.47, blue: 0.59)),
        ("blue", "Blue", Color(red: 0.0, green: 0.45, blue: 0.9), Color(red: 0.4, green: 0.7, blue: 1.0)),
        ("amber", "Amber", Color(red: 0.9, green: 0.6, blue: 0.0), Color(red: 1.0, green: 0.78, blue: 0.35)),
        ("teal", "Teal", Color(red: 0.0, green: 0.62, blue: 0.55), Color(red: 0.4, green: 0.85, blue: 0.78)),
        ("violet", "Violet", Color(red: 0.55, green: 0.35, blue: 0.9), Color(red: 0.74, green: 0.62, blue: 1.0)),
    ]
    var accentName = UserDefaults.standard.string(forKey: "accent") ?? "rose" { didSet { UserDefaults.standard.set(accentName, forKey: "accent") } }
    /// "dark" (default), "light" or "system".
    var appearance = UserDefaults.standard.string(forKey: "appearance") ?? "dark" { didSet { UserDefaults.standard.set(appearance, forKey: "appearance") } }
    var scheme: ColorScheme? { appearance == "light" ? .light : appearance == "system" ? nil : .dark }
    var current: (name: String, label: String, base: Color, soft: Color) { Self.accents.first { $0.name == accentName } ?? Self.accents[0] }
}

enum Theme {
    /// The accent colour (RawLight rose unless the user picked another in Settings).
    static var accent: Color { ThemeStore.shared.current.base }
    static var accentSoft: Color { ThemeStore.shared.current.soft }
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
            content.glassEffect(selected ? Glass.regular.tint(Theme.accent.opacity(0.42)).interactive() : Glass.regular.interactive(), in: shape)
        } else {
            content.background(selected ? Theme.accent.opacity(0.55) : Theme.field, in: shape)
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

/// Test and screenshot launch switches (RAWLIGHT_*). They exist only in Debug builds; a shipped app ignores the environment.
enum DebugEnv {
    static var vars: [String: String] {
        #if DEBUG
        ProcessInfo.processInfo.environment
        #else
        [:]
        #endif
    }
}
