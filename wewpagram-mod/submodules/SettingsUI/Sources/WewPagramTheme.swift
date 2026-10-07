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

var wewMenuBaseColor: UIColor?

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

    let sakuraBehind = menu.sakuraOn
    if hasImage || sakuraBehind || background != nil || card != nil || text != nil || accent != nil {
        var blocksBackground: UIColor? = background
        var itemBackground: UIColor? = card
        if hasImage || sakuraBehind {
            // Remember the colour the page would have had: a base view paints it behind the petals.
            wewMenuBaseColor = background ?? theme.list.blocksBackgroundColor
        }
        if hasImage || sakuraBehind {
            // The picture / falling petals show through: the page is transparent, rows are slightly see-through.
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
        background.backgroundColor = wewMenuBaseColor
        host.insertSubview(background, at: 0)
        self.backgroundView = background

        let sakura = WewSakuraView(frame: host.bounds)
        sakura.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        sakura.isUserInteractionEnabled = false
        // Behind the list (above the picture), so petals fall in the background.
        host.insertSubview(sakura, aboveSubview: background)
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
        background.backgroundColor = wewMenuBaseColor
        background.image = path == nil ? nil : background.image
        let backgroundAlpha: CGFloat = (path == nil && !menu.sakuraOn) ? 0.0 : 1.0
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
    private var lastLifetime: Float = 0.0

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
        self.emitter.emitterPosition = CGPoint(x: self.bounds.width * 0.6, y: -24.0)
        self.emitter.emitterSize = CGSize(width: self.bounds.width + 240.0, height: 1.0)
        // Long enough for a petal to reach the very bottom of the screen.
        let lifetime = Float(self.bounds.height / 45.0) + 6.0
        if lifetime != self.lastLifetime, let cells = self.emitter.emitterCells {
            self.lastLifetime = lifetime
            for cell in cells {
                cell.lifetime = lifetime
            }
        }
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
        func makeCell(_ image: UIImage, rate: Float, speed: CGFloat) -> CAEmitterCell {
            let cell = CAEmitterCell()
            cell.contents = image.cgImage
            cell.birthRate = rate
            cell.lifetime = 24.0
            cell.velocity = speed
            cell.velocityRange = 18.0
            cell.emissionLongitude = .pi / 2.0
            cell.emissionRange = .pi / 4.0
            cell.xAcceleration = -6.0          // a light breeze to the left
            cell.yAcceleration = 2.0
            cell.spin = 0.2
            cell.spinRange = 1.4
            cell.scale = 0.8
            cell.scaleRange = 0.35
            cell.alphaRange = 0.2
            return cell
        }
        // petals of three sizes
        for (index, size) in [CGFloat(13.0), CGFloat(18.0), CGFloat(24.0)].enumerated() {
            if let image = WewSakuraView.petalImage(size: size, shade: index) {
                cells.append(makeCell(image, rate: 1.0 + Float(index) * 0.3, speed: 50.0 + CGFloat(index) * 8.0))
            }
        }
        // and a few whole blossoms
        for size in [CGFloat(22.0), CGFloat(30.0)] {
            if let image = WewSakuraView.blossomImage(size: size) {
                cells.append(makeCell(image, rate: 0.22, speed: 56.0))
            }
        }
        self.emitter.emitterCells = cells
    }

    // The outline of one cherry petal with the typical notch at the tip (unit square, y down).
    private static func petalPath(in rect: CGRect) -> UIBezierPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        let path = UIBezierPath()
        path.move(to: p(0.5, 1.0))
        path.addCurve(to: p(0.04, 0.24), controlPoint1: p(0.2, 0.86), controlPoint2: p(-0.04, 0.55))
        path.addCurve(to: p(0.5, 0.2), controlPoint1: p(0.1, -0.02), controlPoint2: p(0.38, 0.0))
        path.addCurve(to: p(0.96, 0.24), controlPoint1: p(0.62, 0.0), controlPoint2: p(0.9, -0.02))
        path.addCurve(to: p(0.5, 1.0), controlPoint1: p(1.04, 0.55), controlPoint2: p(0.8, 0.86))
        path.close()
        return path
    }

    private static func fillPetal(_ context: CGContext, rect: CGRect, shade: Int) {
        let tips: [UIColor] = [UIColor(red: 1.0, green: 0.88, blue: 0.93, alpha: 1.0), UIColor(red: 1.0, green: 0.82, blue: 0.9, alpha: 1.0), UIColor(red: 1.0, green: 0.9, blue: 0.95, alpha: 1.0)]
        let bases: [UIColor] = [UIColor(red: 0.98, green: 0.6, blue: 0.76, alpha: 1.0), UIColor(red: 0.96, green: 0.52, blue: 0.7, alpha: 1.0), UIColor(red: 0.99, green: 0.68, blue: 0.82, alpha: 1.0)]
        let path = petalPath(in: rect)
        context.saveGState()
        context.addPath(path.cgPath)
        context.clip()
        let colors = [tips[shade % 3].cgColor, bases[shade % 3].cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0.0, 1.0]) {
            context.drawLinearGradient(gradient, start: CGPoint(x: rect.midX, y: rect.minY), end: CGPoint(x: rect.midX, y: rect.maxY), options: [])
        }
        context.restoreGState()
        context.setStrokeColor(UIColor(white: 1.0, alpha: 0.45).cgColor)
        context.setLineWidth(max(0.5, rect.width * 0.03))
        context.move(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.08))
        context.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.34))
        context.strokePath()
    }

    private static func petalImage(size: CGFloat, shade: Int) -> UIImage? {
        let inset: CGFloat = 2.0
        let width = size * 0.72 + inset * 2.0
        let height = size + inset * 2.0
        return generateImage(CGSize(width: width, height: height), rotatedContext: { imageSize, context in
            context.clear(CGRect(origin: .zero, size: imageSize))
            fillPetal(context, rect: CGRect(x: inset, y: inset, width: size * 0.72, height: size), shade: shade)
        })
    }

    // Five petals around a centre with stamens.
    private static func blossomImage(size: CGFloat) -> UIImage? {
        return generateImage(CGSize(width: size, height: size), rotatedContext: { imageSize, context in
            context.clear(CGRect(origin: .zero, size: imageSize))
            let center = CGPoint(x: imageSize.width / 2.0, y: imageSize.height / 2.0)
            let petalHeight = size * 0.5
            let petalWidth = petalHeight * 0.78
            for i in 0 ..< 5 {
                context.saveGState()
                context.translateBy(x: center.x, y: center.y)
                context.rotate(by: CGFloat(i) * 2.0 * .pi / 5.0)
                fillPetal(context, rect: CGRect(x: -petalWidth / 2.0, y: -petalHeight * 0.98, width: petalWidth, height: petalHeight), shade: i % 3)
                context.restoreGState()
            }
            context.setFillColor(UIColor(red: 0.86, green: 0.3, blue: 0.5, alpha: 1.0).cgColor)
            context.fillEllipse(in: CGRect(x: center.x - size * 0.06, y: center.y - size * 0.06, width: size * 0.12, height: size * 0.12))
            context.setStrokeColor(UIColor(red: 0.9, green: 0.4, blue: 0.58, alpha: 0.9).cgColor)
            context.setLineWidth(0.6)
            for i in 0 ..< 5 {
                let angle = CGFloat(i) * 2.0 * .pi / 5.0 + 0.3
                let end = CGPoint(x: center.x + cos(angle) * size * 0.17, y: center.y + sin(angle) * size * 0.17)
                context.move(to: center)
                context.addLine(to: end)
                context.strokePath()
                context.setFillColor(UIColor(red: 1.0, green: 0.85, blue: 0.4, alpha: 1.0).cgColor)
                context.fillEllipse(in: CGRect(x: end.x - 0.9, y: end.y - 0.9, width: 1.8, height: 1.8))
            }
        })
    }
}
