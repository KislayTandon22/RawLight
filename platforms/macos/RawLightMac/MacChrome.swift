import SwiftUI
import AppKit

// MARK: model actions

extension LibraryModel {
    /// Choose photos or folders and add them to the library (copied into it).
    func importPhotos() async {
        let p = NSOpenPanel()
        p.canChooseFiles = true; p.canChooseDirectories = true; p.allowsMultipleSelection = true
        p.prompt = "Import"; p.message = "Choose photos or folders to import into the library"
        guard p.runModal() == .OK else { return }
        importMessage = "Importing \(p.urls.count) item\(p.urls.count == 1 ? "" : "s")…"
        do {
            _ = try await engine.execute("library.import", ["paths": p.urls.map(\.path), "mode": "copy"])
            await load()
            importMessage = "Import finished · \(ids.count) photos"
        } catch { importMessage = "Import failed: \(error.localizedDescription)" }
    }

    var targetIDs: [UInt64] { selection.isEmpty ? (activeID.map { [$0] } ?? []) : Array(selection) }

    func rate(_ n: Int) async {
        guard !targetIDs.isEmpty else { return }
        _ = try? await engine.execute("photo.rate", ["ids": targetIDs, "rating": n])
        refreshThumbs()
    }
    func flag(_ cmd: String) async {
        guard !targetIDs.isEmpty else { return }
        _ = try? await engine.execute(cmd, ["ids": targetIDs])
        refreshThumbs()
    }
    func refreshThumbs() { for id in targetIDs { thumbVersion[id, default: 0] += 1 } }
    func go(_ module: String) {
        if module == "Develop", activeID == nil, let f = ids.first { openDevelop(f) } else { self.module = module }
    }
}

// MARK: right panel

struct RightPanel: View {
    @Environment(LibraryModel.self) private var model
    @State private var info: [String: Any] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            section("Selection") {
                Text(model.selection.isEmpty ? "No photo selected" : "\(model.selection.count) selected")
                    .font(.system(size: 13, weight: .semibold))
                Text(model.selection.count == 1 ? "Double-click to open in Develop" : "Rate and flag all at once")
                    .font(.system(size: 11)).foregroundStyle(MacTheme.dim)
            }
            section("Rating") {
                HStack(spacing: 6) {
                    ForEach(1...5, id: \.self) { n in
                        Button { Task { await model.rate(n) } } label: { Image(systemName: "star.fill") }
                            .buttonStyle(.plain).foregroundStyle(MacTheme.accent.opacity(0.85)).help("\(n) star\(n == 1 ? "" : "s")  (\(n))")
                    }
                    Spacer()
                    Button("Clear") { Task { await model.rate(0) } }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(MacTheme.dim)
                }.disabled(model.targetIDs.isEmpty)
            }
            section("Flag") {
                HStack(spacing: 8) {
                    flagButton("Pick", "flag.fill", "photo.pick")
                    flagButton("Reject", "xmark.circle", "photo.reject")
                    flagButton("Clear", "circle.slash", "photo.unflag")
                }.disabled(model.targetIDs.isEmpty)
            }
            section("Quick Develop") {
                Button { model.go("Develop") } label: { Label("Open in Develop", systemImage: "slider.horizontal.3").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).tint(MacTheme.accent).disabled(model.targetIDs.isEmpty)
                Button { model.go("Export") } label: { Label("Export…", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).disabled(model.targetIDs.isEmpty)
            }
            Spacer()
        }
        .padding(14).background(MacTheme.side)
    }
    private func flagButton(_ t: String, _ icon: String, _ cmd: String) -> some View {
        Button { Task { await model.flag(cmd) } } label: { Label(t, systemImage: icon).font(.system(size: 12)) }.buttonStyle(.bordered)
    }
    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(MacTheme.dim)
            c()
        }.padding(.bottom, 18)
    }
}

// MARK: menu bar

struct RawLightCommands: Commands {
    let model: LibraryModel
    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Import Photos…") { Task { await model.importPhotos() } }.keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Open or New Library…") { model.chooseLibrary() }.keyboardShortcut("o", modifiers: .command)
            Divider()
            Button("Export…") { model.go("Export") }.keyboardShortcut("e", modifiers: [.command, .shift])
        }
        CommandMenu("Photo") {
            ForEach(1...5, id: \.self) { n in
                Button("Rate \(n) Star\(n == 1 ? "" : "s")") { Task { await model.rate(n) } }.keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: [])
            }
            Button("Clear Rating") { Task { await model.rate(0) } }.keyboardShortcut("0", modifiers: [])
            Divider()
            Button("Pick") { Task { await model.flag("photo.pick") } }.keyboardShortcut("p", modifiers: [])
            Button("Reject") { Task { await model.flag("photo.reject") } }.keyboardShortcut("x", modifiers: [])
            Button("Remove Flag") { Task { await model.flag("photo.unflag") } }.keyboardShortcut("u", modifiers: [])
        }
        CommandMenu("Go") {
            Button("Library") { model.go("Library") }.keyboardShortcut("1", modifiers: .command)
            Button("Develop") { model.go("Develop") }.keyboardShortcut("2", modifiers: .command)
            Button("Export") { model.go("Export") }.keyboardShortcut("3", modifiers: .command)
            Divider()
            Button("Command Palette…") { model.showPalette = true }.keyboardShortcut("k", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { model.showShortcuts = true }.keyboardShortcut("/", modifiers: .command)
        }
    }
}

// MARK: command palette and shortcut sheet

struct CommandPalette: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var q = ""
    private struct Item: Identifiable { let id = UUID(); let title: String; let key: String; let run: @MainActor () -> Void }
    private var items: [Item] {
        let m = model
        return [
            Item(title: "Go to Library", key: "⌘1") { m.go("Library") },
            Item(title: "Go to Develop", key: "⌘2") { m.go("Develop") },
            Item(title: "Go to Export", key: "⌘3") { m.go("Export") },
            Item(title: "Import Photos…", key: "⇧⌘I") { Task { await m.importPhotos() } },
            Item(title: "Open or New Library…", key: "⌘O") { m.chooseLibrary() },
            Item(title: "Pick", key: "P") { Task { await m.flag("photo.pick") } },
            Item(title: "Reject", key: "X") { Task { await m.flag("photo.reject") } },
            Item(title: "Remove Flag", key: "U") { Task { await m.flag("photo.unflag") } },
            Item(title: "Keyboard Shortcuts", key: "⌘/") { m.showShortcuts = true },
        ] + (1...5).map { n in Item(title: "Rate \(n) star\(n == 1 ? "" : "s")", key: "\(n)") { Task { await m.rate(n) } } }
    }
    private var shown: [Item] { q.isEmpty ? items : items.filter { $0.title.localizedCaseInsensitiveContains(q) } }
    var body: some View {
        VStack(spacing: 0) {
            TextField("Type a command", text: $q).textFieldStyle(.plain).font(.system(size: 17)).padding(16)
                .onSubmit { if let f = shown.first { dismiss(); f.run() } }
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(shown) { it in
                        Button { dismiss(); it.run() } label: {
                            HStack { Text(it.title); Spacer(); Text(it.key).foregroundStyle(MacTheme.dim).font(.system(size: 12, design: .monospaced)) }
                                .padding(.horizontal, 12).frame(height: 32).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }.padding(8)
            }
        }
        .frame(width: 520, height: 400).background(MacTheme.side)
    }
}

struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let rows: [(String, [(String, String)])] = [
        ("Navigate", [("Library", "⌘1"), ("Develop", "⌘2"), ("Export", "⌘3"), ("Command palette", "⇧⌘K")]),
        ("Library", [("Import photos", "⇧⌘I"), ("Open or new library", "⌘O"), ("Select several", "⌘ click"), ("Open in Develop", "double-click")]),
        ("Culling", [("Rate 1 to 5", "1 – 5"), ("Clear rating", "0"), ("Pick", "P"), ("Reject", "X"), ("Remove flag", "U")]),
        ("Export", [("Export…", "⇧⌘E"), ("Shortcuts", "⌘/")]),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Keyboard Shortcuts").font(.title2.weight(.semibold)); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            HStack(alignment: .top, spacing: 28) {
                ForEach(rows, id: \.0) { group in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(group.0.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(MacTheme.accent)
                        ForEach(group.1, id: \.0) { r in
                            HStack { Text(r.0).font(.system(size: 12)); Spacer(minLength: 12); Text(r.1).font(.system(size: 12, design: .monospaced)).foregroundStyle(MacTheme.dim) }
                        }
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(22).frame(width: 760).background(MacTheme.side)
    }
}

// MARK: settings

struct SettingsView: View {
    @AppStorage("thumbSize") private var thumbSize = 170.0
    @AppStorage("exportQuality") private var quality = 90.0
    @AppStorage("exportEdge") private var edge = 3000
    @AppStorage("exportSpace") private var space = "srgb"
    var body: some View {
        TabView {
            Form {
                Slider(value: $thumbSize, in: 90...320) { Text("Grid thumbnail size") }
                Text("Accent colour follows the RawLight red theme.").font(.footnote).foregroundStyle(.secondary)
            }.padding(20).tabItem { Label("General", systemImage: "gearshape") }
            Form {
                Slider(value: $quality, in: 50...100, step: 1) { Text("JPEG quality \(Int(quality))") }
                Picker("Long edge", selection: $edge) { Text("1600").tag(1600); Text("3000").tag(3000); Text("Full").tag(0) }.pickerStyle(.segmented)
                Picker("Colour space", selection: $space) { Text("sRGB").tag("srgb"); Text("Display P3").tag("displayP3"); Text("Adobe RGB").tag("adobeRgb") }.pickerStyle(.segmented)
            }.padding(20).tabItem { Label("Export", systemImage: "square.and.arrow.up") }
            VStack(spacing: 8) {
                Text("RawLight").font(.title.weight(.semibold))
                Text("Version 1.0.0").foregroundStyle(.secondary)
                Text("Contributors").font(.headline).padding(.top, 10)
                Text("Built on the LightCraft engine by the ArtCraft Team and contributors.").multilineTextAlignment(.center).font(.footnote).foregroundStyle(.secondary)
            }.padding(24).tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 280)
    }
}
