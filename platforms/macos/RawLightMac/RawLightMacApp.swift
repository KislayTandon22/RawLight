import SwiftUI

@main
struct RawLightMacApp: App {
    @State private var model = LibraryModel()
    var body: some Scene {
        WindowGroup {
            LibraryScreen()
                .environment(model)
                .preferredColorScheme(.dark)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    await model.load()
                    if ProcessInfo.processInfo.environment["RAWLIGHT_MODULE"] == "develop", let f = model.ids.dropFirst(3).first { model.openDevelop(f); if ProcessInfo.processInfo.environment["RAWLIGHT_MODULE_NEXT"] == "export" { model.module = "Export" } }
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
        Settings { SettingsView().preferredColorScheme(.dark) }
    }
}
