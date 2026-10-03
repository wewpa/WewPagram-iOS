import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

public func wewpagramHubController(context: AccountContext) -> ViewController {
    let manager = WewPluginManager.shared
    manager.startIfNeeded()

    var controllerRef: ViewController?
    let push: (ViewController) -> Void = { c in
        (controllerRef as? ItemListController)?.push(c)
    }

    let changes = Signal<Void, NoError>.single(Void()) |> then(wewDefaultsChanged())

    let entries = combineLatest(queue: .mainQueue(), manager.revision.get(), changes)
    |> map { _, _ -> [WewEntry] in
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
        let userbotLabel = settings.userbotEnabled ? "Вкл" : "Выкл"

        let plugins = manager.installedPlugins()
        let logoPath = manager.logoPath()

        var result: [WewEntry] = [
            WewEntry(order: 0, section: 0, signature: "header|" + (logoPath ?? ""), build: { pd in
                return WewPagramHeaderItem(presentationData: pd, icon: wewLogoImage(side: 84.0, overridePath: logoPath), name: "WewPagram", version: wewVersionString, sectionId: 0)
            }),
            wewRow(10, 1, icon: wewGhostIcon(), title: "Режим призрака", label: ghostLabel, action: { push(wewpagramGhostModeController(context: context)) }),
            wewRow(11, 1, icon: PresentationResourcesSettings.deleteChats, title: "Удалённые сообщения", label: deletedLabel, action: { push(wewpagramDeletedMessagesController(context: context)) }),
            wewRow(20, 2, icon: PresentationResourcesSettings.myProfile, title: "Профиль", label: "", action: { push(wewpagramFakeIdentityController(context: context)) }),
            wewRow(30, 3, icon: PresentationResourcesSettings.bot, title: "Юзербот", label: userbotLabel, action: { push(wewpagramUserbotController(context: context)) }),
            wewRow(40, 4, icon: PresentationResourcesSettings.appearance, title: "Плагины", label: plugins.isEmpty ? "" : "\(plugins.count)", action: { push(wewpagramPluginsController(context: context)) })
        ]

        // Pages that enabled plugins added through wew.menu.add
        for (index, item) in manager.menuItems().enumerated() {
            let icon = item.iconPath.flatMap { wewPluginTile(path: $0) } ?? PresentationResourcesSettings.appearance
            result.append(wewRow(100 + index, 4, icon: icon, title: item.title, label: "", action: {
                push(wewpagramPluginPageController(context: context, pluginId: item.pluginId, itemId: item.itemId))
            }))
        }
        return result
    }

    let controller = wewListController(context: context, title: "WewPagram", entries: entries)
    controllerRef = controller
    return controller
}
