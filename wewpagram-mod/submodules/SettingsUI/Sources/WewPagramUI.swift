import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI

let wewVersionString = "1.0.0"

// MARK: - Icons

// Draws a 30pt settings tile (gradient + Telegram's own gloss) and lets the
// caller put an extra white glyph on top of it.
private func wewIconBase(colors: [UIColor]) -> UIImage? {
    return renderSettingsIcon(name: "", backgroundColors: colors)
}

// Coloured settings icon that uses one of Telegram's own glyphs.
func wewGlyphIcon(name: String, colors: [UIColor]) -> UIImage? {
    return renderSettingsIcon(name: name, backgroundColors: colors)
}

// AyuGram-style ghost drawn on the same kind of tile.
func wewGhostIcon() -> UIImage? {
    let size = CGSize(width: 30.0, height: 30.0)
    let base = wewIconBase(colors: [UIColor(rgb: 0xB07BFF), UIColor(rgb: 0x6E4BE8)])
    return generateImage(size, rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        if let base = base {
            UIGraphicsPushContext(context)
            base.draw(in: CGRect(origin: .zero, size: size))
            UIGraphicsPopContext()
        }

        let w = size.width
        let h = size.height
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: x * w, y: y * h)
        }

        let ghost = UIBezierPath()
        ghost.move(to: p(0.2, 0.78))
        ghost.addLine(to: p(0.2, 0.46))
        ghost.addArc(withCenter: p(0.5, 0.46), radius: 0.30 * w, startAngle: .pi, endAngle: 2.0 * .pi, clockwise: true)
        ghost.addLine(to: p(0.8, 0.78))
        ghost.addQuadCurve(to: p(0.6, 0.78), controlPoint: p(0.7, 0.96))
        ghost.addQuadCurve(to: p(0.4, 0.78), controlPoint: p(0.5, 0.96))
        ghost.addQuadCurve(to: p(0.2, 0.78), controlPoint: p(0.3, 0.96))
        ghost.close()

        context.setFillColor(UIColor.white.cgColor)
        context.addPath(ghost.cgPath)
        context.fillPath()

        context.setFillColor(UIColor(rgb: 0x7C57EE).cgColor)
        let eyeRadius = 0.055 * w
        for x in [CGFloat(0.4), CGFloat(0.6)] {
            let center = p(x, 0.47)
            context.fillEllipse(in: CGRect(x: center.x - eyeRadius, y: center.y - eyeRadius, width: eyeRadius * 2.0, height: eyeRadius * 2.0))
        }
    })
}

// The mod's logo: its avatar clipped to a rounded square. A plugin may supply
// its own logo image (png/jpg), which is used instead when given.
func wewLogoImage(side: CGFloat, overridePath: String? = nil) -> UIImage? {
    var source: UIImage?
    if let path = overridePath, let custom = UIImage(contentsOfFile: path) {
        source = custom
    } else {
        source = wewAvatarImage()
    }
    guard let image = source else {
        return nil
    }
    return generateImage(CGSize(width: side, height: side), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        let rect = CGRect(origin: .zero, size: size)
        context.setFillColor(UIColor.white.cgColor)
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.225).cgPath)
        context.fillPath()

        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: size.width * 0.225).cgPath)
        context.clip()
        UIGraphicsPushContext(context)
        // aspect-fill
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: (size.width - drawSize.width) / 2.0, y: (size.height - drawSize.height) / 2.0, width: drawSize.width, height: drawSize.height))
        UIGraphicsPopContext()
        context.restoreGState()

        context.setStrokeColor(UIColor(white: 0.5, alpha: 0.35).cgColor)
        context.setLineWidth(1.0)
        context.addPath(UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: size.width * 0.225).cgPath)
        context.strokePath()
    })
}

// Small coloured tile with a plugin's own icon (png/jpg), aspect-fill.
func wewPluginTile(path: String) -> UIImage? {
    guard let image = UIImage(contentsOfFile: path) else {
        return nil
    }
    let size = CGSize(width: 30.0, height: 30.0)
    return generateImage(size, rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        let rect = CGRect(origin: .zero, size: size)
        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 7.0).cgPath)
        context.clip()
        UIGraphicsPushContext(context)
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: (size.width - drawSize.width) / 2.0, y: (size.height - drawSize.height) / 2.0, width: drawSize.width, height: drawSize.height))
        UIGraphicsPopContext()
        context.restoreGState()
    })
}

// Small rounded square with a gift's sticker inside (used in lists).
func wewGiftTile(_ image: UIImage) -> UIImage? {
    let size = CGSize(width: 30.0, height: 30.0)
    return generateImage(size, rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        let rect = CGRect(origin: .zero, size: size)
        context.saveGState()
        context.addPath(UIBezierPath(roundedRect: rect, cornerRadius: 7.0).cgPath)
        context.clip()
        context.setFillColor(UIColor(rgb: 0x8E8E93, alpha: 0.16).cgColor)
        context.fill(rect)
        context.restoreGState()

        UIGraphicsPushContext(context)
        image.draw(in: rect.insetBy(dx: 3.0, dy: 3.0))
        UIGraphicsPopContext()
    })
}

// MARK: - Header item (logo + "WewPagram 1.0.0")

final class WewPagramHeaderItem: ListViewItem, ItemListItem {
    let sectionId: ItemListSectionId
    let selectable: Bool = false

    let presentationData: ItemListPresentationData
    let icon: UIImage?
    let name: String
    let version: String

    init(presentationData: ItemListPresentationData, icon: UIImage?, name: String, version: String, sectionId: ItemListSectionId) {
        self.presentationData = presentationData
        self.icon = icon
        self.name = name
        self.version = version
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = WewPagramHeaderItemNode()
            let (layout, apply) = node.asyncLayout()(self, params)

            node.contentSize = layout.contentSize
            node.insets = layout.insets

            Queue.mainQueue().async {
                completion(node, {
                    return (nil, { _ in apply() })
                })
            }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        Queue.mainQueue().async {
            if let nodeValue = node() as? WewPagramHeaderItemNode {
                let makeLayout = nodeValue.asyncLayout()

                async {
                    let (layout, apply) = makeLayout(self, params)
                    Queue.mainQueue().async {
                        completion(layout, { _ in
                            apply()
                        })
                    }
                }
            }
        }
    }
}

final class WewPagramHeaderItemNode: ListViewItemNode {
    private let iconNode: ASImageNode
    private let titleNode: ASTextNode

    override var canBeSelected: Bool {
        return false
    }

    init() {
        self.iconNode = ASImageNode()
        self.iconNode.displaysAsynchronously = false
        self.iconNode.displayWithoutProcessing = true
        self.iconNode.isUserInteractionEnabled = false

        self.titleNode = ASTextNode()
        self.titleNode.isUserInteractionEnabled = false

        super.init(layerBacked: false)

        self.addSubnode(self.iconNode)
        self.addSubnode(self.titleNode)
    }

    func asyncLayout() -> (WewPagramHeaderItem, ListViewItemLayoutParams) -> (ListViewItemNodeLayout, () -> Void) {
        return { [weak self] item, params in
            let contentSize = CGSize(width: params.width, height: 156.0)
            let layout = ListViewItemNodeLayout(contentSize: contentSize, insets: UIEdgeInsets())

            return (layout, {
                guard let self else {
                    return
                }

                let iconSide: CGFloat = 84.0
                self.iconNode.image = item.icon
                if self.iconNode.layer.animation(forKey: "wew.float") == nil {
                    let float = CABasicAnimation(keyPath: "transform.translation.y")
                    float.fromValue = -2.5
                    float.toValue = 2.5
                    float.duration = 3.0
                    float.autoreverses = true
                    float.repeatCount = .infinity
                    float.timingFunction = CAMediaTimingFunction(name: .easeInEaseInOut)
                    self.iconNode.layer.add(float, forKey: "wew.float")
                }
                self.iconNode.frame = CGRect(origin: CGPoint(x: floor((params.width - iconSide) / 2.0), y: 24.0), size: CGSize(width: iconSide, height: iconSide))

                let text = NSMutableAttributedString(string: item.name, attributes: [
                    .font: UIFont.systemFont(ofSize: 22.0, weight: .bold),
                    .foregroundColor: item.presentationData.theme.list.itemPrimaryTextColor
                ])
                text.append(NSAttributedString(string: "  " + item.version, attributes: [
                    .font: UIFont.systemFont(ofSize: 15.0, weight: .regular),
                    .foregroundColor: item.presentationData.theme.list.itemSecondaryTextColor
                ]))
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .center
                text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))

                self.titleNode.attributedText = text
                self.titleNode.frame = CGRect(x: 0.0, y: 118.0, width: params.width, height: 28.0)
            })
        }
    }
}
