import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        self.attachPendingWindows(to: windowScene)

        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak windowScene] _ in
            guard let ws = windowScene else { return }
            self?.attachPendingWindows(to: ws)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        if let windowScene = scene as? UIWindowScene {
            attachPendingWindows(to: windowScene)
        }
    }

    private func attachPendingWindows(to windowScene: UIWindowScene) {
        for w in UIApplication.shared.windows {
            if w.windowScene == nil {
                w.windowScene = windowScene
                if self.window == nil {
                    self.window = w
                }
            }
        }
    }
}
