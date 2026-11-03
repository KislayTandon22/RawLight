import SwiftUI

@main
struct RawLightMacApp: App {
    @State private var model = LibraryModel()
    init() {
        // Headless check of every flow, with no window and no screen: see SelfTest.swift.
        if let report = ProcessInfo.processInfo.environment["RAWLIGHT_SELFTEST"] {
            NSApplication.shared.setActivationPolicy(.prohibited)
            Task { @MainActor in await SelfTest.run(report: report) }
        }
    }
    var body: some Scene {
        WindowGroup {
            LibraryScreen()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    model.installKeys()
                    if let folder = ProcessInfo.processInfo.environment["RAWLIGHT_SCRIPT"] {
                        await ScriptRun.run(folder: folder, logPath: ProcessInfo.processInfo.environment["RAWLIGHT_SCRIPT_LOG"] ?? "/tmp/rawlight-script.txt", model: model)
                        return
                    }
                    await model.load()
                    // Start the GPU pipeline now, so the first Develop picture is not the one that pays for it.
                    if let f = model.ids.first { Task.detached(priority: .utility) { _ = await model.engine.render(f, maxEdge: 64, kind: 2) } }
                    if ProcessInfo.processInfo.environment["RAWLIGHT_MODULE"] == "develop", let f = model.ids.dropFirst(3).first { model.openDevelop(f); if ProcessInfo.processInfo.environment["RAWLIGHT_MODULE_NEXT"] == "export" { model.module = "Export" } }
                    if let sheet = ProcessInfo.processInfo.environment["RAWLIGHT_SHEET"] { model.showPalette = sheet == "palette"; model.showShortcuts = sheet == "shortcuts" }
                    if ProcessInfo.processInfo.environment["RAWLIGHT_SELECT"] != nil { model.selection = Set(model.ids.prefix(2)) }
                    // Debug aid: RAWLIGHT_SHOT=/path.png saves the window contents and quits (no screen-recording permission needed).
                    guard let path = ProcessInfo.processInfo.environment["RAWLIGHT_SHOT"] else { return }
                    try? await Task.sleep(for: .seconds(6))
                    if let v = NSApp.windows.first?.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                        v.cacheDisplay(in: v.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
                    }
                    NSApp.terminate(nil)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
        .commands { RawLightCommands(model: model) }
        Settings { SettingsView().environment(model).preferredColorScheme(.dark) }
    }
}
