import SwiftUI
import Observation

@MainActor @Observable
final class AppModel {
    let engine = Engine(demo: true)
    var photoIDs: [UInt64] = []
    var openPhoto: UInt64?
    var thumbs: [UInt64: UIImage] = [:]

    func load() async {
        photoIDs = await engine.visibleIDs()
    }

    func thumbnail(_ id: UInt64) async {
        guard thumbs[id] == nil, let img = await engine.render(id, maxEdge: 360) else { return }
        thumbs[id] = img
    }
}
