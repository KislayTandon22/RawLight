import UIKit
import ObjectiveC

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private static var hasHooked = false

    override init() {
        super.init()
        NSLog("[LightCraft-Swift] SceneDelegate init")
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
            NSLog("[LightCraft-Swift] Swizzled UIWindow initWithFrame")
        }
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        NSLog("[LightCraft-Swift] Scene willConnectTo session")

        self.bindWindows(to: windowScene)

        DispatchQueue.main.async {
            NSLog("[LightCraft-Swift] Posting didBecomeActiveNotification after scene connection")
            NotificationCenter.default.post(
                name: UIApplication.didBecomeActiveNotification,
                object: UIApplication.shared
            )
        }

        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification,
            object: nil,
            queue: .main
        ) { [weak self, weak windowScene] notif in
            guard let ws = windowScene else { return }
            if let win = notif.object as? UIWindow {
                NSLog("[LightCraft-Swift] Window didBecomeVisible: %@", win)
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
                NSLog("[LightCraft-Swift] Window didBecomeKey: %@", win)
                self?.bind(window: win, to: ws)
            }
            self?.bindWindows(to: ws)
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        NSLog("[LightCraft-Swift] sceneDidBecomeActive")
        bindWindows(to: windowScene)

        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification,
            object: UIApplication.shared
        )
    }

    func sceneWillResignActive(_ scene: UIScene) {
        NSLog("[LightCraft-Swift] sceneWillResignActive")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        NSLog("[LightCraft-Swift] sceneWillEnterForeground")
        bindWindows(to: windowScene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        NSLog("[LightCraft-Swift] sceneDidEnterBackground")
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        NSLog("[LightCraft-Swift] windowScene didUpdate coordinateSpace: %@", NSCoder.string(for: windowScene.coordinateSpace.bounds))
        bindWindows(to: windowScene)
    }

    private func bind(window: UIWindow, to windowScene: UIWindowScene) {
        if window.windowScene !== windowScene {
            window.windowScene = windowScene
            NSLog("[LightCraft-Swift] Attached window %@ to windowScene %@", window, windowScene)
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
