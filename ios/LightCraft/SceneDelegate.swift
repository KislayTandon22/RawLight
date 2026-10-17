import UIKit
import ObjectiveC

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private static var hasHooked = false

    override init() {
        super.init()
        Self.enableWindowSceneAttachmentHook()
    }

    static func enableWindowSceneAttachmentHook() {
        guard !hasHooked else { return }
        hasHooked = true

        let origInit = #selector(UIWindow.init(frame:))
        let swizInit = #selector(UIWindow.lc_initWithFrame(_:))

        if let m1 = class_getInstanceMethod(UIWindow.self, origInit),
           let m2 = class_getInstanceMethod(UIWindow.self, swizInit) {
            method_exchangeImplementations(m1, m2)
        }
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Forward launch & active notifications to winit
        NotificationCenter.default.post(
            name: UIApplication.didFinishLaunchingNotification,
            object: UIApplication.shared
        )
        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification,
            object: UIApplication.shared
        )

        self.bindWindows(to: windowScene)

        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak windowScene] notif in
            guard let ws = windowScene else { return }
            if let win = notif.object as? UIWindow {
                self?.bind(window: win, to: ws)
            }
            self?.bindWindows(to: ws)
        }

        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak windowScene] notif in
            guard let ws = windowScene else { return }
            if let win = notif.object as? UIWindow {
                self?.bind(window: win, to: ws)
            }
            self?.bindWindows(to: ws)
        }

        for delay in [0.02, 0.05, 0.1, 0.25, 0.5, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak windowScene] in
                guard let ws = windowScene else { return }
                self?.bindWindows(to: ws)
                NotificationCenter.default.post(
                    name: UIApplication.didBecomeActiveNotification,
                    object: UIApplication.shared
                )
            }
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        bindWindows(to: windowScene)
        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification,
            object: UIApplication.shared
        )
    }

    func sceneWillResignActive(_ scene: UIScene) {
        NotificationCenter.default.post(
            name: UIApplication.willResignActiveNotification,
            object: UIApplication.shared
        )
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        bindWindows(to: windowScene)
        NotificationCenter.default.post(
            name: UIApplication.willEnterForegroundNotification,
            object: UIApplication.shared
        )
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification,
            object: UIApplication.shared
        )
    }

    private func bind(window: UIWindow, to windowScene: UIWindowScene) {
        if window.windowScene !== windowScene {
            window.windowScene = windowScene
        }
        window.frame = windowScene.coordinateSpace.bounds
        if !window.isKeyWindow {
            window.makeKeyAndVisible()
        }
        if self.window == nil {
            self.window = window
        }
    }

    private func bindWindows(to windowScene: UIWindowScene) {
        for win in UIApplication.shared.windows {
            bind(window: win, to: windowScene)
        }
    }
}

extension UIWindow {
    @objc func lc_initWithFrame(_ frame: CGRect) -> UIWindow {
        let win = self.lc_initWithFrame(frame)
        if let ws = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            win.windowScene = ws
        }
        return win
    }
}
