import SwiftUI

/// Auto / B&W / HDR pills, white balance and profile menus, copy/paste settings.
struct QuickEditBar: View {
    let engine: Engine
    let onChange: () -> Void
    @State private var bw = false
    @State private var profileID = "lc.color"
    @State private var profiles: [(id: String, name: String, group: String)] = []
    @State private var wb = "asShot"
    @State private var message: String?

    private let wbModes = [("asShot", "As shot"), ("auto", "Auto"), ("daylight", "Daylight"), ("cloudy", "Cloudy"), ("shade", "Shade"),
                           ("tungsten", "Tungsten"), ("fluorescent", "Fluorescent"), ("flash", "Flash")]

    var body: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    pill("Auto", "wand.and.stars") { await run("develop.auto") }
                    pill("B&W", "circle.lefthalf.filled", on: bw) { await run("develop.treatment", ["bw": !bw]) }
                    if bw { pill("Auto B&W", "slider.horizontal.below.rectangle") { await run("develop.autoBwMix") } }
                    pill("HDR", "sun.max") { await run("develop.hdr") }
                    Menu {
                        Button("Paste from previous") { Task { await run("develop.pastePrevious") } }
                        Button("Match exposure") { Task { await run("develop.matchExposure") } }
                    } label: { chip("More", "ellipsis") }
                }
            }
            HStack {
                Text("Profile").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(Dictionary(grouping: profiles, by: \.group).keys.sorted(), id: \.self) { g in
                        Section(g) {
                            ForEach(profiles.filter { $0.group == g }, id: \.id) { p in
                                Button { Task { await run("develop.profile", ["id": p.id]) } } label: {
                                    if p.id == profileID { Label(p.name, systemImage: "checkmark") } else { Text(p.name) }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) { Text(profiles.first { $0.id == profileID }?.name ?? "Color"); Image(systemName: "chevron.up.chevron.down").font(.caption) }
                        .font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 40).fieldBackground(in: Capsule())
                }
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.accentSoft).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .task { await load() }
    }

    private func pill(_ title: String, _ symbol: String, on: Bool = false, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 40)
                .fieldBackground(on, in: Capsule()).foregroundStyle(on ? .white : .primary)
        }
    }
    private func chip(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 40)
            .fieldBackground(in: Capsule()).foregroundStyle(.primary)
    }

    private func load() async {
        let d = await engine.developState()
        bw = (d["treatment"] as? String) == "bw"
        profileID = ((d["profile"] as? [String: Any])?["id"] as? String) ?? "lc.color"
        wb = ((d["wb"] as? [String: Any])?["mode"] as? String) ?? "asShot"
        if profiles.isEmpty, let arr = try? await engine.execute("profiles.list") as? [[String: Any]] {
            profiles = arr.compactMap { d in
                guard let id = d["id"] as? String, let n = d["name"] as? String else { return nil }
                return (id, n, d["group"] as? String ?? "Other")
            }
        }
    }

    private func run(_ id: String, _ p: [String: Any] = [:]) async {
        do { _ = try await engine.execute(id, p); message = nil } catch { message = error.localizedDescription }
        await load()
        onChange()
    }
}
