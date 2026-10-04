import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import AccountContext

// MARK: - Colours

func wewHexColor(_ string: String?) -> UIColor? {
    guard var value = string?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
        return nil
    }
    if value.hasPrefix("#") {
        value.removeFirst()
    }
    guard value.count == 6, let number = UInt32(value, radix: 16) else {
        return nil
    }
    return UIColor(rgb: number)
}

// MARK: - Theme applied to every WewPagram menu

private func wewFontSize(_ name: String?) -> PresentationFontSize? {
    switch name {
    case "small":
        return .small
    case "regular":
        return .regular
    case "medium":
        return .medium
    case "large":
        return .large
    case "xlarge":
        return .extraLarge
    default:
        return nil
    }
}

// Resolves "<pluginId>|<file>" to a picture shipped by an enabled plugin.
func wewMenuBackgroundPath() -> String? {
    guard let reference = WewPagramSettings.shared.menuTheme.backgroundImage else {
        return nil
    }
    let parts = reference.split(separator: "|", maxSplits: 1).map(String.init)
    guard parts.count == 2, let plugin = WewPluginManager.shared.plugin(id: parts[0]), plugin.enabled else {
        return nil
    }
    return plugin.filePath(parts[1])
}

func wewThemed(_ data: PresentationData) -> PresentationData {
    let menu = WewPagramSettings.shared.menuTheme
    var theme = data.theme

    // 1. light / dark, independent from the rest of the app
    if let dark = menu.dark, dark != theme.overallDarkAppearance {
        theme = makeDefaultPresentationTheme(reference: dark ? .night : .day, serviceBackgroundColor: nil)
    }

    // 2. colours
    let hasImage = wewMenuBackgroundPath() != nil
    let background = wewHexColor(menu.background)
    let card = wewHexColor(menu.card)
    let text = wewHexColor(menu.text)
    let accent = wewHexColor(menu.accent)

    if hasImage || background != nil || card != nil || text != nil || accent != nil {
        var blocksBackground: UIColor? = background
        var itemBackground: UIColor? = card
        if hasImage {
            // The picture shows through: the page is transparent, rows are slightly see-through.
            blocksBackground = UIColor.clear
            let base = card ?? theme.list.itemBlocksBackgroundColor
            itemBackground = base.withAlphaComponent(0.82)
        } else if background != nil && card == nil {
            itemBackground = nil
        }

        let list = theme.list.withUpdated(
            blocksBackgroundColor: blocksBackground,
            plainBackgroundColor: blocksBackground,
            itemPrimaryTextColor: text,
            itemAccentColor: accent,
            itemBlocksBackgroundColor: itemBackground
        )

        var rootController = theme.rootController
        if let accent = accent {
            let navigationBar = rootController.navigationBar.withUpdated(buttonColor: accent, accentTextColor: accent)
            rootController = rootController.withUpdated(navigationBar: navigationBar)
        }

        theme = PresentationTheme(
            name: theme.name,
            index: theme.index,
            referenceTheme: theme.referenceTheme,
            overallDarkAppearance: theme.overallDarkAppearance,
            intro: theme.intro,
            passcode: theme.passcode,
            rootController: rootController,
            list: list,
            chatList: theme.chatList,
            chat: theme.chat,
            actionSheet: theme.actionSheet,
            contextMenu: theme.contextMenu,
            inAppNotification: theme.inAppNotification,
            chart: theme.chart,
            preview: theme.preview
        )
    }

    var result = data.withUpdated(theme: theme)

    // 3. text size of the lists
    if let size = wewFontSize(menu.fontSize) {
        result = result.withUpdate(listsFontSize: size)
    }
    return result
}

func wewThemedSignal(context: AccountContext) -> Signal<PresentationData, NoError> {
    return combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, WewPagramSettings.shared.themeRevision.get())
    |> map { data, _ -> PresentationData in
        return wewThemed(data)
    }
}

// Is the menu currently dark? (used by the moon / sun button)
func wewMenuIsDark(_ data: PresentationData) -> Bool {
    return wewThemed(data).theme.overallDarkAppearance
}

// MARK: - Controller factory

// Every WewPagram screen is created through here, so the theme, the
// background picture and the falling sakura are the same everywhere.
func wewMakeController<ItemGenerationArguments>(context: AccountContext, state: Signal<(ItemListControllerState, (ItemListNodeState, ItemGenerationArguments)), NoError>) -> ItemListController {
    let initial = context.sharedContext.currentPresentationData.with { wewThemed($0) }
    let controller = ItemListController(
        presentationData: ItemListPresentationData(initial),
        updatedPresentationData: wewThemedSignal(context: context) |> map { ItemListPresentationData($0) },
        state: state,
        tabBarItem: nil
    )
    WewMenuDecorations.attach(to: controller)
    return controller
}

// MARK: - Decorations: background picture + falling sakura

private let wewDecorationTag = 0x57455701

final class WewMenuDecorations {
    private weak var controller: ViewController?
    private var backgroundView: UIImageView?
    private var sakuraView: WewSakuraView?
    private var themeDisposable: Disposable?
    private var loadedPath: String?

    private init() {}

    deinit {
        self.themeDisposable?.dispose()
    }

    static func attach(to controller: ItemListController) {
        let decorations = WewMenuDecorations()
        decorations.controller = controller

        // The controller owns the helper through these closures.
        controller.didAppear = { [weak controller] _ in
            guard let controller = controller else { return }
            decorations.install(in: controller)
            decorations.update()
            decorations.sakuraView?.start()
        }
        controller.didDisappear = { _ in
            decorations.sakuraView?.stop()
        }
        decorations.themeDisposable = (WewPagramSettings.shared.themeRevision.get() |> deliverOnMainQueue).start(next: { [weak decorations] _ in
            decorations?.update()
        })
    }

    private func install(in controller: ViewController) {
        let host = controller.view
        if self.sakuraView != nil || host?.viewWithTag(wewDecorationTag) != nil {
            return
        }
        guard let host = host else { return }

        let background = UIImageView(frame: host.bounds)
        background.tag = wewDecorationTag
        background.contentMode = .scaleAspectFill
        background.clipsToBounds = true
        background.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        background.isUserInteractionEnabled = false
        background.alpha = 0.0
        host.insertSubview(background, at: 0)
        self.backgroundView = background

        let sakura = WewSakuraView(frame: host.bounds)
        sakura.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sakura.isUserInteractionEnabled = false
        host.addSubview(sakura)
        self.sakuraView = sakura
    }

    // Smooth cross-fades whenever the appearance changes.
    private func update() {
        guard let background = self.backgroundView, let sakura = self.sakuraView else {
            return
        }
        let menu = WewPagramSettings.shared.menuTheme
        let path = wewMenuBackgroundPath()
        if path != self.loadedPath {
            self.loadedPath = path
            background.image = path.flatMap { UIImage(contentsOfFile: $0) }
        }
        let backgroundAlpha: CGFloat = path == nil ? 0.0 : 1.0
        if background.alpha != backgroundAlpha {
            UIView.animate(withDuration: 0.35) {
                background.alpha = backgroundAlpha
            }
        }
        sakura.setEnabled(menu.sakuraOn)
    }
}

// MARK: - Falling sakura (GPU particles, so it stays smooth)

final class WewSakuraView: UIView {
    private let emitter = CAEmitterLayer()
    private var enabledByUser = true
    private var running = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .clear
        self.layer.addSublayer(self.emitter)
        self.configureEmitter()
        self.alpha = 0.0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        self.emitter.frame = self.bounds
        self.emitter.emitterPosition = CGPoint(x: self.bounds.width / 2.0, y: -24.0)
        self.emitter.emitterSize = CGSize(width: self.bounds.width + 120.0, height: 1.0)
    }

    func setEnabled(_ value: Bool) {
        self.enabledByUser = value
        self.apply(animated: true)
    }

    func start() {
        self.running = true
        self.apply(animated: true)
    }

    func stop() {
        self.running = false
        self.apply(animated: false)
    }

    private func apply(animated: Bool) {
        let visible = self.running && self.enabledByUser
        self.emitter.birthRate = visible ? 1.0 : 0.0
        let alpha: CGFloat = visible ? 1.0 : 0.0
        if animated {
            UIView.animate(withDuration: 0.6) {
                self.alpha = alpha
            }
        } else {
            self.alpha = alpha
        }
    }

    private func configureEmitter() {
        self.emitter.emitterShape = .line
        self.emitter.renderMode = .oldestFirst
        self.emitter.birthRate = 0.0

        var cells: [CAEmitterCell] = []
        // three petal sizes, like the layers on the site
        for (index, size) in [CGFloat(12.0), CGFloat(17.0), CGFloat(23.0)].enumerated() {
            guard let image = WewSakuraView.petalImage(size: size, shade: index) else { continue }
            let cell = CAEmitterCell()
            cell.contents = image.cgImage
            cell.birthRate = 1.1 + Float(index) * 0.35
            cell.lifetime = 16.0
            cell.lifetimeRange = 4.0
            cell.velocity = 34.0 + CGFloat(index) * 10.0
            cell.velocityRange = 22.0
            cell.emissionLongitude = .pi / 2.0
            cell.emissionRange = .pi / 5.0
            cell.xAcceleration = -4.0
            cell.yAcceleration = 3.0
            cell.spin = 0.35
            cell.spinRange = 1.1
            cell.scale = 0.75
            cell.scaleRange = 0.35
            cell.alphaRange = 0.25
            cell.alphaSpeed = -0.01
            cells.append(cell)
        }
        self.emitter.emitterCells = cells
    }

    // A soft pink petal drawn in code (no image resources needed).
    private static func petalImage(size: CGFloat, shade: Int) -> UIImage? {
        let width = size
        let height = size * 0.62
        let pinks: [UIColor] = [UIColor(red: 1.0, green: 0.74, blue: 0.84, alpha: 0.92), UIColor(red: 0.99, green: 0.62, blue: 0.78, alpha: 0.88), UIColor(red: 1.0, green: 0.82, blue: 0.9, alpha: 0.9)]
        let color = pinks[shade % pinks.count]
        return generateImage(CGSize(width: width, height: height), rotatedContext: { size, context in
            context.clear(CGRect(origin: .zero, size: size))
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 0.0, y: size.height / 2.0))
            path.addQuadCurve(to: CGPoint(x: size.width, y: size.height / 2.0), controlPoint: CGPoint(x: size.width * 0.45, y: -size.height * 0.25))
            path.addQuadCurve(to: CGPoint(x: 0.0, y: size.height / 2.0), controlPoint: CGPoint(x: size.width * 0.45, y: size.height * 1.25))
            path.close()
            context.setFillColor(color.cgColor)
            context.addPath(path.cgPath)
            context.fillPath()

            context.setStrokeColor(UIColor(white: 1.0, alpha: 0.35).cgColor)
            context.setLineWidth(0.6)
            context.move(to: CGPoint(x: size.width * 0.12, y: size.height / 2.0))
            context.addLine(to: CGPoint(x: size.width * 0.82, y: size.height / 2.0))
            context.strokePath()
        })
    }
}
