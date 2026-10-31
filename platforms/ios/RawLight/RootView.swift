import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage("onboarded") private var onboarded = false
    private var debugLaunch: Bool { ["RAWLIGHT_FRESH", "RAWLIGHT_OPEN", "RAWLIGHT_IMPORT"].contains { ProcessInfo.processInfo.environment[$0] != nil } }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if !onboarded && !debugLaunch {
                OnboardingView { onboarded = true }
            } else if let id = model.openPhoto {
                EditorView(photoID: id)
            } else {
                LibraryView()
            }
        }
        .task {
            await model.start()
            // Debug aid: RAWLIGHT_OPEN=1 opens the first photo on launch (used for screenshots).
            // Debug aid: RAWLIGHT_IMPORT=/path/photo.jpg imports that file and opens it.
            if let path = ProcessInfo.processInfo.environment["RAWLIGHT_IMPORT"] {
                let before = Set(model.photoIDs)
                await model.importURLs([URL(fileURLWithPath: path)])
                await model.load()
                model.openPhoto = model.photoIDs.first { !before.contains($0) } ?? model.photoIDs.first
            } else if ProcessInfo.processInfo.environment["RAWLIGHT_OPEN"] != nil { model.openPhoto = model.photoIDs.first }
        }
    }
}
