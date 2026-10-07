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
    // Screens that only wrap other screens (or belong to UIKit itself): no zone events, no overlays.
    static func isContainer(_ className: String) -> Bool {
        for prefix in ["UI", "_", "NS", "SF", "AV", "PU", "QL", "MF", "WK", "SK"] where className.hasPrefix(prefix) {
            return true
        }
        return className.contains("NavigationController") || className.contains("TabBarController") || className.contains("RootController") || className.contains("Container")
    }

    // Maps a view controller class name to a stable zone id.
    static func zone(for className: String) -> String? {
        if className.hasPrefix("AuthorizationSequence") { return "login" }
        if className.contains("GiftStoreScreen") || className.contains("GiftAuction") { return "market" }
        if className.hasPrefix("Gift") || className.hasPrefix("PremiumGift") { return "gifts" }
        if className.hasPrefix("Stars") { return "stars" }
        if className.hasPrefix("Premium") { return "premium" }
        if className.contains("StoryContainerScreen") { return "stories" }
        if className.contains("CameraScreen") { return "camera" }
        if className.contains("GalleryController") { return "gallery" }
        if className.contains("ShareController") { return "share" }
        if className.contains("StickerPackScreen") { return "stickers" }
        if className.contains("MediaPickerScreen") || className.contains("AttachmentController") { return "media" }
        if className.contains("MiniApp") || className.contains("WebApp") { return "miniapps" }
        if className.contains("ChatFolder") { return "folders" }
        if className.contains("CallController") || className.contains("VoiceChat") { return "calls" }
        if className.contains("ChatListController") { return "chats" }
        if className.contains("ChatController") { return "chat" }
        if className.contains("PeerInfoScreen") { return "profile" }
        if className.contains("ContactsController") { return "contacts" }
        if className.contains("CallListController") { return "calls" }
        if className.contains("ItemListController") || className.contains("SettingsController") { return "settings" }
        return nil
    }
}

public struct WewOverlay {
    public var pluginId: String
    public var id: String
    public var zone: String      // a zone id, or "*" for every screen
    public var kind: String      // banner | button
    public var text: String
    public var color: String?
    public var textColor: String?
    public var bottom: Bool
    public var key: String
}

private func wewColor(_ hex: String?, fallback: UIColor) -> UIColor {
    guard var value = hex?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return fallback }
    if value.hasPrefix("#") { value.removeFirst() }
    guard value.count == 6, let number = UInt32(value, radix: 16) else { return fallback }
    return UIColor(red: CGFloat((number >> 16) & 0xff) / 255.0, green: CGFloat((number >> 8) & 0xff) / 255.0, blue: CGFloat(number & 0xff) / 255.0, alpha: 1.0)
}

private final class WewPassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        return view === self ? nil : view
    }
}

private final class WewButtonTarget: NSObject {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    @objc func fire() {
        self.action()
    }
}

private var wewButtonTargetKey: UInt8 = 0

// Small native elements plugins can pin to any screen (login, gifts, market, stars,
// chats, profile, ...) without rebuilding the app. Only a fixed set of kinds exists,
// so a plugin can decorate a screen but cannot reach into Telegram's own views.
public final class WewOverlays {
    public static let shared = WewOverlays()

    private static let containerTag = 0x57455701

    private let lock = NSLock()
    private var items: [WewOverlay] = []
    private var tints: [String: String] = [:]

    private init() {}

    func add(_ overlay: WewOverlay) {
        self.lock.lock()
        self.items.removeAll(where: { $0.pluginId == overlay.pluginId && $0.id == overlay.id })
        if self.items.filter({ $0.pluginId == overlay.pluginId }).count < 8 {
            self.items.append(overlay)
        }
        self.lock.unlock()
        DispatchQueue.main.async {
            WewZones.refreshCurrent()
        }
    }

    func remove(pluginId: String, id: String) {
        self.lock.lock()
        self.items.removeAll(where: { $0.pluginId == pluginId && $0.id == id })
        self.lock.unlock()
        DispatchQueue.main.async {
            WewZones.refreshCurrent()
        }
    }

    func clearAll() {
        self.lock.lock()
        self.items = []
        self.tints = [:]
        self.lock.unlock()
        DispatchQueue.main.async {
            WewOverlays.shared.applyTint()
            WewZones.refreshCurrent()
        }
    }

    func setTint(_ hex: String?, pluginId: String) {
        self.lock.lock()
        self.tints[pluginId] = hex
        self.lock.unlock()
        DispatchQueue.main.async {
            WewOverlays.shared.applyTint()
        }
    }

    private func applyTint() {
        self.lock.lock()
        let hex = self.tints.sorted(by: { $0.key < $1.key }).compactMap({ $0.value }).last
        self.lock.unlock()
        guard let window = wewKeyWindow() else { return }
        window.tintColor = hex.flatMap { wewColor($0, fallback: .clear) }
    }

    func haptic() {
        DispatchQueue.main.async {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }

    func copy(_ text: String) {
        DispatchQueue.main.async {
            UIPasteboard.general.string = text
        }
    }

    func open(_ url: URL) {
        DispatchQueue.main.async {
            guard let app = wewSharedApplication() else { return }
            let selector = NSSelectorFromString("openURL:options:completionHandler:")
            guard app.responds(to: selector) else { return }
            typealias OpenFunction = @convention(c) (AnyObject, Selector, URL, [AnyHashable: Any], ((Bool) -> Void)?) -> Void
            let function = unsafeBitCast(app.method(for: selector), to: OpenFunction.self)
            function(app, selector, url, [:], nil)
        }
    }

    // Main thread.
    func apply(to controller: UIViewController, zone: String) {
        guard controller.isViewLoaded else { return }
        let view = controller.view!
        view.viewWithTag(WewOverlays.containerTag)?.removeFromSuperview()

        self.lock.lock()
        let matching = self.items.filter { $0.zone == zone || $0.zone == "*" }
        self.lock.unlock()
        guard !matching.isEmpty else { return }

        let container = WewPassthroughView(frame: view.bounds)
        container.tag = WewOverlays.containerTag
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.backgroundColor = .clear

        var topY = view.safeAreaInsets.top + 6.0
        var bottomY = view.bounds.height - view.safeAreaInsets.bottom - 84.0
        let maxWidth = view.bounds.width - 32.0

        for item in matching {
            let background = wewColor(item.color, fallback: item.kind == "button" ? UIColor(red: 0.56, green: 0.48, blue: 1.0, alpha: 1.0) : UIColor(white: 0.1, alpha: 0.9))
            let foreground = wewColor(item.textColor, fallback: .white)
            let label = UILabel()
            label.text = item.text
            label.font = UIFont.systemFont(ofSize: item.kind == "button" ? 15.0 : 13.0, weight: .semibold)
            label.textColor = foreground
            label.textAlignment = .center
            label.numberOfLines = 2
            let fit = label.sizeThatFits(CGSize(width: maxWidth - 28.0, height: CGFloat.greatestFiniteMagnitude))
            let width = min(maxWidth, ceil(fit.width) + 28.0)
            let height = max(item.kind == "button" ? 38.0 : 28.0, ceil(fit.height) + 14.0)
            let y: CGFloat
            if item.bottom {
                bottomY -= height
                y = bottomY
                bottomY -= 8.0
            } else {
                y = topY
                topY += height + 6.0
            }
            let frame = CGRect(x: floor((view.bounds.width - width) / 2.0), y: y, width: width, height: height)

            if item.kind == "button" {
                let button = UIButton(type: .custom)
                button.frame = frame
                button.backgroundColor = background
                button.layer.cornerRadius = height / 2.0
                button.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
                label.frame = button.bounds
                label.isUserInteractionEnabled = false
                button.addSubview(label)
                let pluginId = item.pluginId
                let key = item.key
                let target = WewButtonTarget(action: {
                    WewPluginManager.shared.dispatch(pluginId: pluginId, event: "button", args: [key])
                })
                objc_setAssociatedObject(button, &wewButtonTargetKey, target, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                button.addTarget(target, action: #selector(WewButtonTarget.fire), for: .touchUpInside)
                container.addSubview(button)
            } else {
                let box = UIView(frame: frame)
                box.backgroundColor = background
                box.layer.cornerRadius = 10.0
                box.isUserInteractionEnabled = false
                box.autoresizingMask = [.flexibleLeftMargin, .flexibleRightMargin]
                label.frame = box.bounds
                box.addSubview(label)
                container.addSubview(box)
            }
        }
        view.addSubview(container)
        view.bringSubviewToFront(container)
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

    private static weak var lastController: UIViewController?
    private static var lastControllerZone: String = "other"
    private static var lastOtherClass: String?

    // Re-applies overlays on the screen that is currently on top (a plugin just added one).
    static func refreshCurrent() {
        guard let controller = lastController else { return }
        WewOverlays.shared.apply(to: controller, zone: lastControllerZone)
    }

    fileprivate static func noteAppeared(_ controller: UIViewController) {
        let className = String(describing: type(of: controller))
        if WewZoneNames.isContainer(className) {
            return
        }
        let known = WewZoneNames.zone(for: className)
        let zone = known ?? "other"
        lastController = controller
        lastControllerZone = zone
        WewOverlays.shared.apply(to: controller, zone: zone)

        let now = Date().timeIntervalSince1970
        if known == nil {
            // Any other screen is reported as zone "other"; the class name tells which.
            if className == lastOtherClass && now - lastTime < 1.5 {
                return
            }
            lastOtherClass = className
            lastTime = now
            WewPluginManager.shared.dispatchAll(event: "zone.open", args: ["other", className])
            return
        }
        if zone == lastZone && now - lastTime < 1.5 {
            return
        }
        lastZone = zone
        lastTime = now

        WewPluginPresenter.shared.flush()
        WewPluginManager.shared.dispatchAll(event: "zone.open", args: [zone, className])
    }
}
