import UIKit
import ObjectiveC

@_silgen_name("lightcraft_post_action")
func lightcraft_post_action(_ action: Int32)

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private static var hasHooked = false

    override init() {
        super.init()
        NSLog("[RawLight] SceneDelegate init")
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
            NSLog("[RawLight] Swizzled UIWindow initWithFrame")
        }
    }

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        NSLog("[RawLight] Scene willConnectTo session")

        self.bindWindows(to: windowScene)

        DispatchQueue.main.async {
            NSLog("[RawLight] Posting didBecomeActiveNotification after scene connection")
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
                NSLog("[RawLight] Window didBecomeVisible: %@", win)
                self?.bind(window: win, to: ws)
            }
        }
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        NSLog("[RawLight] sceneDidBecomeActive")
        bindWindows(to: windowScene)

        NotificationCenter.default.post(
            name: UIApplication.didBecomeActiveNotification,
            object: UIApplication.shared
        )
    }

    func sceneWillResignActive(_ scene: UIScene) {
        NSLog("[RawLight] sceneWillResignActive")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        guard let windowScene = scene as? UIWindowScene else { return }
        NSLog("[RawLight] sceneWillEnterForeground")
        bindWindows(to: windowScene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        NSLog("[RawLight] sceneDidEnterBackground")
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        didUpdate previousCoordinateSpace: UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        NSLog("[RawLight] windowScene didUpdate coordinateSpace: %@", NSCoder.string(for: windowScene.coordinateSpace.bounds))
        bindWindows(to: windowScene)
    }

    private func bind(window: UIWindow, to windowScene: UIWindowScene) {
        let className = String(describing: type(of: window))
        if className.contains("UITextEffects") || className.contains("SystemOverlay") || className.contains("Keyboard") {
            return
        }
        if window.windowScene !== windowScene {
            window.windowScene = windowScene
            NSLog("[RawLight] Attached window %@ to windowScene %@", window, windowScene)
        }
        window.overrideUserInterfaceStyle = .dark
        window.rootViewController?.overrideUserInterfaceStyle = .dark
        window.frame = windowScene.coordinateSpace.bounds
        ios_update_safe_area()
        if self.window == nil {
            self.window = window
            window.makeKeyAndVisible()
        }

        // Attach Apple Pencil double-tap interaction (iPadOS 12.1+)
        if #available(iOS 12.1, *) {
            var hasPencil = false
            for interaction in window.interactions {
                if interaction is UIPencilInteraction {
                    hasPencil = true
                    break
                }
            }
            if !hasPencil {
                let pencil = UIPencilInteraction()
                pencil.delegate = self
                window.addInteraction(pencil)
                NSLog("[RawLight] Attached UIPencilInteraction to window")
            }
            if !(window.gestureRecognizers ?? []).contains(where: { $0 is PencilStrokeRecognizer }) {
                window.addGestureRecognizer(PencilStrokeRecognizer(target: nil, action: nil))
                NSLog("[RawLight] Attached Pencil stroke recognizer to window")
            }
        }

    }

    private func bindWindows(to windowScene: UIWindowScene) {
        for win in windowScene.windows {
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


extension SceneDelegate: UIPencilInteractionDelegate {
    @available(iOS 12.1, *)
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        NSLog("[RawLight] UIPencilInteraction double-tap -> posting ZoomToggle action (3)")
        lightcraft_post_action(3)
    }
}
