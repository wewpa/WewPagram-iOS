import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

public func wewpagramHubController(context: AccountContext) -> ViewController {
    let manager = WewPluginManager.shared
    manager.startIfNeeded()
    WewPagramSettings.shared.rememberSelfUser(context.account.peerId.id._internalGetInt64Value())

    var controllerRef: ViewController?
    let push: (ViewController) -> Void = { c in
        (controllerRef as? ItemListController)?.push(c)
    }

    let changes = Signal<Void, NoError>.single(Void()) |> then(wewDefaultsChanged())

    let entries = combineLatest(queue: .mainQueue(), manager.revision.get(), changes, WewPagramSettings.shared.themeRevision.get())
    |> map { _, _, _ -> [WewEntry] in
        let settings = WewPagramSettings.shared

        let ghostCount = settings.ghostEnabledCount
        let ghostLabel: String
        if ghostCount == 0 {
            ghostLabel = "Выкл"
        } else if ghostCount == WewPagramSettings.ghostTotalCount {
            ghostLabel = "Вкл"
        } else {
            ghostLabel = "\(ghostCount)/\(WewPagramSettings.ghostTotalCount)"
        }
        let deletedLabel = settings.deletedMessagesEnabled ? "Вкл" : "Выкл"

        let plugins = manager.installedPlugins()
        let logoPath = manager.logoPath()

        var result: [WewEntry] = [
            WewEntry(order: 0, section: 0, signature: "header|" + (logoPath ?? ""), build: { pd in
                return WewPagramHeaderItem(presentationData: pd, icon: wewLogoImage(side: 84.0, overridePath: logoPath), name: "WewPagram", version: wewVersionString, sectionId: 0)
            }),
            wewRow(10, 1, icon: wewGlyph(.ghost), title: "Режим призрака", label: ghostLabel, action: { push(wewpagramGhostModeController(context: context)) }),
            wewRow(11, 1, icon: wewGlyph(.trash), title: "Удалённые сообщения", label: deletedLabel, action: { push(wewpagramDeletedMessagesController(context: context)) }),
            wewRow(20, 2, icon: wewGlyph(.person), title: "Профиль", label: "", action: { push(wewpagramFakeIdentityController(context: context)) }),
            wewRow(21, 2, icon: wewGlyph(.star), title: "Premium", label: settings.localPremiumEnabled ? "Вкл" : "Выкл", action: { push(wewpagramPremiumController(context: context)) }),
            wewRow(22, 2, icon: wewGlyph(.drop), title: "Внешний вид", label: "", action: { push(wewpagramAppearanceController(context: context)) }),
            wewRow(23, 2, icon: wewGlyph(.globe), title: "Переводчик (Google)", label: settings.googleTranslateEnabled ? "Вкл" : "Выкл", action: { settings.googleTranslateEnabled = !settings.googleTranslateEnabled }),
            wewRow(40, 4, icon: wewGlyph(.cube), title: "Плагины", label: plugins.isEmpty ? "" : "\(plugins.count)", action: { push(wewpagramPluginsController(context: context)) })
        ]

        // Pages that enabled plugins added through wew.menu.add
        for (index, item) in manager.menuItems().enumerated() {
            let icon = item.iconPath.flatMap { wewPluginTile(path: $0) } ?? wewGlyph(.cube)
            result.append(wewRow(100 + index, 4, icon: icon, title: item.title, label: "", action: {
                push(wewpagramPluginPageController(context: context, pluginId: item.pluginId, itemId: item.itemId))
            }))
        }
        return result
    }

    // Moon / sun at the top: light <-> dark menu with a soft cross-fade.
    let toggleTheme: () -> Void = {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let isDark = wewMenuIsDark(data)
        if let view = controllerRef?.view, let snapshot = view.snapshotView(afterScreenUpdates: false) {
            view.addSubview(snapshot)
            UIView.animate(withDuration: 0.5, delay: 0.05, options: [.curveEaseInOut], animations: {
                snapshot.alpha = 0.0
            }, completion: { _ in
                snapshot.removeFromSuperview()
            })
        }
        var menu = WewPagramSettings.shared.menuTheme
        menu.dark = !isDark
        WewPagramSettings.shared.menuTheme = menu
    }

    let controller = wewListController(context: context, title: "WewPagram", entries: entries, rightButton: { data in
        let isDark = data.theme.overallDarkAppearance
        let node = ASImageNode()
        node.displaysAsynchronously = false
        node.image = wewMoonGlyph(filled: isDark)
        node.frame = CGRect(x: 0.0, y: 0.0, width: 30.0, height: 30.0)
        node.style.preferredSize = CGSize(width: 30.0, height: 30.0)
        return ItemListNavigationButton(content: .node(node), style: .regular, enabled: true, action: toggleTheme)
    })
    controllerRef = controller

    // Plugins are told that the WewPagram menu was opened.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        manager.dispatchAll(event: "menu.open", args: [])
    }
    return controller
}
