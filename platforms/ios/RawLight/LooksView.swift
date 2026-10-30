import SwiftUI

struct PresetItem: Identifiable, Hashable {
    let id: String
    let name: String
    let group: String
    let builtin: Bool
    var favorite: Bool
}

/// Looks: one-tap presets with an amount, favourites, saving the current edit, and point-curve presets.
struct LooksPanel: View {
    let engine: Engine
    let photoID: UInt64
    let onChange: () -> Void
    @State private var presets: [PresetItem] = []
    @State private var applied: String?
    @State private var amount = 100.0
    @State private var curves: [String] = []
    @State private var currentCurve: String?
    @State private var askName = false
    @State private var name = ""
    @State private var message: String?

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Amount").font(.subheadline); Slider(value: $amount, in: 0...200, step: 1) { e in if !e, let a = applied { Task { await apply(a) } } }.tint(Theme.accent)
                Text("\(Int(amount))").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)
            }
            .padding(12).background(Theme.field, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Button { askName = true } label: {
                Label("Save current look", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 44)
                    .background(Theme.accent, in: Capsule()).foregroundStyle(.white)
            }
            if let message { Text(message).font(.footnote).foregroundStyle(Theme.accentSoft) }
            if presets.contains(where: \.favorite) { group("Favourites", presets.filter(\.favorite)) }
            ForEach(Array(Set(presets.map(\.group))).sorted(), id: \.self) { g in group(g, presets.filter { $0.group == g }) }
            if !curves.isEmpty {
                Text("Tone curve presets").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(curves, id: \.self) { c in
                            Button { Task { _ = try? await engine.execute("curve.applyPreset", ["name": c]); currentCurve = c; onChange() } } label: {
                                Text(c).font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 38)
                                    .background(currentCurve == c ? Theme.accent : Theme.field, in: Capsule()).foregroundStyle(currentCurve == c ? .white : .primary)
                            }
                        }
                    }
                }
            }
        }
        .task(id: photoID) { await load() }
        .alert("Save look", isPresented: $askName) {
            TextField("Name", text: $name)
            Button("Save") { let n = name; name = ""; Task { await create(n) } }
            Button("Cancel", role: .cancel) { name = "" }
        }
    }

    private func group(_ title: String, _ items: [PresetItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                ForEach(items) { p in
                    Button { Task { await apply(p.id) } } label: {
                        VStack(spacing: 2) {
                            Text(p.name).font(.footnote.weight(.medium)).lineLimit(2).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity).frame(height: 54).padding(.horizontal, 6)
                        .background(applied == p.id ? Theme.accent : Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(applied == p.id ? .white : .primary)
                        .overlay(alignment: .topTrailing) { if p.favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(Theme.accentSoft).padding(6) } }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(p.favorite ? "Remove favourite" : "Favourite", systemImage: "star") { Task { await fav(p) } }
                        if !p.builtin { Button("Delete", systemImage: "trash", role: .destructive) { Task { await delete(p) } } }
                    }
                }
            }
        }
    }

    private func load() async {
        if let arr = try? await engine.execute("presets.list") as? [[String: Any]] {
            presets = arr.compactMap { d in
                guard let id = d["id"] as? String, let n = d["name"] as? String else { return nil }
                return PresetItem(id: id, name: n, group: d["group"] as? String ?? "Presets", builtin: d["builtin"] as? Bool ?? false, favorite: d["favorite"] as? Bool ?? false)
            }
        }
        if let r = try? await engine.execute("curve.presets") as? [String: Any] {
            curves = ((r["presets"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
            currentCurve = r["current"] as? String
        }
    }
    private func apply(_ id: String) async {
        do { _ = try await engine.execute("preset.apply", ["id": id, "amount": Int(amount)]); applied = id; message = nil } catch { message = error.localizedDescription }
        onChange()
    }
    private func create(_ n: String) async {
        guard !n.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do { _ = try await engine.execute("preset.create", ["name": n, "group": "My Looks"]); message = nil } catch { message = error.localizedDescription }
        await load()
    }
    private func fav(_ p: PresetItem) async { _ = try? await engine.execute("preset.favorite", ["id": p.id, "favorite": !p.favorite]); await load() }
    private func delete(_ p: PresetItem) async { _ = try? await engine.execute("preset.delete", ["id": p.id]); await load() }
}

/// History steps and named snapshots (versions) of the active photo.
struct HistoryPanel: View {
    let engine: Engine
    let photoID: UInt64
    let onChange: () -> Void
    @State private var steps: [String] = []
    @State private var cursor = 0
    @State private var versions: [String] = []
    @State private var askName = false
    @State private var name = ""

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button { askName = true } label: {
                    Label("New snapshot", systemImage: "camera").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).frame(height: 44).background(Theme.accent, in: Capsule()).foregroundStyle(.white)
                }
                Button { Task { await run("history.clear") } } label: {
                    Text("Clear history").font(.subheadline.weight(.medium)).padding(.horizontal, 14).frame(height: 44).background(Theme.field, in: Capsule())
                }.buttonStyle(.plain)
            }
            if !versions.isEmpty {
                Text("Snapshots").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(versions.enumerated()), id: \.offset) { i, v in
                    HStack {
                        Button { Task { await run("version.restore", ["index": i]) } } label: { HStack { Image(systemName: "camera"); Text(v); Spacer() }.frame(height: 44) }.buttonStyle(.plain)
                        Button { Task { await run("version.delete", ["index": i]) } } label: { Image(systemName: "trash").foregroundStyle(.secondary).frame(width: 44, height: 44) }
                    }.padding(.horizontal, 12).background(Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            Text("History").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
            if steps.isEmpty { Text("No edits yet").font(.footnote).foregroundStyle(.secondary) }
            ForEach(Array(steps.enumerated()).reversed(), id: \.offset) { i, s in
                Button { Task { await run("history.restore", ["index": i]) } } label: {
                    HStack { Text(s); Spacer(); if i == cursor { Image(systemName: "checkmark").foregroundStyle(Theme.accent) } }.frame(height: 44)
                }
                .buttonStyle(.plain).padding(.horizontal, 12)
                .background(i == cursor ? Theme.accent.opacity(0.25) : Theme.field, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .opacity(i > cursor ? 0.5 : 1)
            }
        }
        .task(id: photoID) { await load() }
        .alert("Snapshot name", isPresented: $askName) {
            TextField("Name", text: $name)
            Button("Create") { let n = name; name = ""; Task { await run("version.create", n.isEmpty ? [:] : ["name": n]) } }
            Button("Cancel", role: .cancel) { name = "" }
        }
    }

    private func load() async {
        guard let r = try? await engine.execute("history.list") as? [String: Any] else { return }
        steps = (r["history"] as? [String]) ?? []
        cursor = (r["cursor"] as? NSNumber)?.intValue ?? 0
        versions = ((r["versions"] as? [Any]) ?? []).map { ($0 as? String) ?? (($0 as? [String: Any])?["name"] as? String) ?? "Snapshot" }
    }
    private func run(_ id: String, _ p: [String: Any] = [:]) async { _ = try? await engine.execute(id, p); await load(); onChange() }
}
