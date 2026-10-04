import Foundation
import UIKit
import ObjectiveC

// App-wide layer for plugins: shows alerts / toasts in ANY part of the app and
// reports which "zone" the user has entered. Everything that touches the
// window goes through the Objective-C runtime on purpose - this module is also
// linked into app extensions, where UIApplication.shared is unavailable at
// compile time.

private func wewSharedApplication() -> NSObject? {
    guard let cls = NSClassFromString("UIApplication") as? NSObject.Type else {
        return nil
    }
    return cls.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? NSObject
}

private func wewKeyWindow() -> UIWindow? {
    guard let app = wewSharedApplication(), let windows = app.value(forKey: "windows") as? [UIWindow] else {
        return nil
    }
    if let key = windows.first(where: { $0.isKeyWindow && !$0.isHidden }) {
        return key
    }
    return windows.last(where: { !$0.isHidden && $0.windowLevel == .normal })
}

private func wewTopViewController() -> UIViewController? {
    var top = wewKeyWindow()?.rootViewController
    while let presented = top?.presentedViewController {
        top = presented
    }
    return top
}

enum WewZoneNames {
    // Maps a view controller class name to a stable zone id.
    static func zone(for className: String) -> String? {
        if className.contains("ChatListController") { return "chats" }
        if className.contains("ChatController") { return "chat" }
        if className.contains("PeerInfoScreen") { return "profile" }
        if className.contains("ContactsController") { return "contacts" }
        if className.contains("CallListController") { return "calls" }
        if className.contains("ItemListController") || className.contains("SettingsController") { return "settings" }
        return nil
    }
}

public final class WewPluginPresenter {
    public static let shared = WewPluginPresenter()

    private enum Pending {
        case alert(String, String)
        case toast(String)
    }

    // Only touched on the main thread.
    private var pending: [Pending] = []
    private var flushScheduled = false

    private init() {}

    public func alert(title: String, text: String) {
        DispatchQueue.main.async {
            if !self.presentAlert(title: title, text: text) {
                self.enqueue(.alert(title, text))
            }
        }
    }

    public func toast(_ text: String) {
        DispatchQueue.main.async {
            if !self.presentToast(text) {
                self.enqueue(.toast(text))
            }
        }
    }

    // Called on app activation and on every zone change.
    public func flush() {
        guard !self.pending.isEmpty else { return }
        let items = self.pending
        self.pending = []
        for item in items {
            switch item {
            case let .alert(title, text):
                if !self.presentAlert(title: title, text: text) { self.pending.append(item) }
            case let .toast(text):
                if !self.presentToast(text) { self.pending.append(item) }
            }
        }
        if !self.pending.isEmpty {
            self.scheduleFlush()
        }
    }

    private func enqueue(_ item: Pending) {
        self.pending.append(item)
        if self.pending.count > 6 {
            self.pending.removeFirst()
        }
        self.scheduleFlush()
    }

    // No window yet (early app start): try again shortly, a few times.
    private func scheduleFlush(attempt: Int = 0) {
        guard !self.flushScheduled, attempt < 12 else { return }
        self.flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.flushScheduled = false
            let before = self.pending.count
            self.flush()
            if self.pending.count == before && before > 0 {
                self.scheduleFlush(attempt: attempt + 1)
            }
        }
    }

    private func presentAlert(title: String, text: String) -> Bool {
        guard let top = wewTopViewController() else {
            return false
        }
        // Do not stack alerts on top of each other.
        if top is UIAlertController {
            return false
        }
        let alert = UIAlertController(title: title, message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        top.present(alert, animated: true, completion: nil)
        return true
    }

    private func presentToast(_ text: String) -> Bool {
        guard let window = wewKeyWindow() else {
            return false
        }
        let container = UIView()
        container.backgroundColor = UIColor(white: 0.08, alpha: 0.94)
        container.layer.cornerRadius = 14.0
        container.isUserInteractionEnabled = false

        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14.0, weight: .medium)
        label.numberOfLines = 3
        label.textAlignment = .center

        let maxWidth = window.bounds.width - 56.0
        let size = label.sizeThatFits(CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude))
        let width = min(maxWidth, ceil(size.width)) + 28.0
        let height = ceil(size.height) + 20.0
        let top = window.safeAreaInsets.top + 10.0
        container.frame = CGRect(x: floor((window.bounds.width - width) / 2.0), y: top, width: width, height: height)
        label.frame = CGRect(x: 14.0, y: 10.0, width: width - 28.0, height: height - 20.0)
        container.addSubview(label)
        container.alpha = 0.0
        window.addSubview(container)
        window.bringSubviewToFront(container)

        UIView.animate(withDuration: 0.2) {
            container.alpha = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            UIView.animate(withDuration: 0.25, animations: {
                container.alpha = 0.0
            }, completion: { _ in
                container.removeFromSuperview()
            })
        }
        return true
    }
}

extension UIViewController {
    @objc fileprivate func wew_viewDidAppear(_ animated: Bool) {
        // After the exchange this calls the ORIGINAL implementation.
        self.wew_viewDidAppear(animated)
        WewZones.noteAppeared(self)
    }
}

public final class WewZones {
    private static var installed = false
    private static var lastZone: String?
    private static var lastTime: TimeInterval = 0

    // Main thread only; never runs inside an app extension.
    public static func install() {
        guard !installed, !Bundle.main.bundlePath.hasSuffix(".appex") else {
            return
        }
        installed = true

        if let original = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.viewDidAppear(_:))),
           let replacement = class_getInstanceMethod(UIViewController.self, #selector(UIViewController.wew_viewDidAppear(_:))) {
            method_exchangeImplementations(original, replacement)
        }

        NotificationCenter.default.addObserver(forName: Notification.Name("UIApplicationDidBecomeActiveNotification"), object: nil, queue: .main) { _ in
            WewPluginPresenter.shared.flush()
            WewPluginManager.shared.dispatchAll(event: "app.foreground", args: [])
        }

        // The first entry into the app after the plugin system came up.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            WewPluginPresenter.shared.flush()
            WewPluginManager.shared.dispatchAll(event: "app.open", args: [])
        }
    }

    fileprivate static func noteAppeared(_ controller: UIViewController) {
        let className = String(describing: type(of: controller))
        guard let zone = WewZoneNames.zone(for: className) else {
            return
        }
        let now = Date().timeIntervalSince1970
        if zone == lastZone && now - lastTime < 1.5 {
            return
        }
        lastZone = zone
        lastTime = now

        WewPluginPresenter.shared.flush()
        WewPluginManager.shared.dispatchAll(event: "zone.open", args: [zone, className])
    }
}
