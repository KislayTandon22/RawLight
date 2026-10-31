import SwiftUI

@main
struct RawLightApp: App {
    @State private var model = AppModel()

    init() { installVisionSegmenter() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(ThemeStore.shared.scheme)
                .tint(Theme.accent)
        }
    }
}
