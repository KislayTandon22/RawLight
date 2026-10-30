import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let id = model.openPhoto {
                EditorView(photoID: id)
            } else {
                LibraryView()
            }
        }
        .task {
            await model.start()
            // Debug aid: RAWLIGHT_OPEN=1 opens the first photo on launch (used for screenshots).
            if ProcessInfo.processInfo.environment["RAWLIGHT_OPEN"] != nil { model.openPhoto = model.photoIDs.first }
        }
    }
}
