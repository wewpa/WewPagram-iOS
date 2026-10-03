import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class WewPagramHubControllerArguments {
    let openGhostMode: () -> Void
    let openDeletedMessages: () -> Void
    let openFakeIdentity: () -> Void
    let openUserbot: () -> Void

    init(openGhostMode: @escaping () -> Void, openDeletedMessages: @escaping () -> Void, openFakeIdentity: @escaping () -> Void, openUserbot: @escaping () -> Void) {
        self.openGhostMode = openGhostMode
        self.openDeletedMessages = openDeletedMessages
        self.openFakeIdentity = openFakeIdentity
        self.openUserbot = openUserbot
    }
}

private enum WewPagramHubEntry: ItemListNodeEntry {
    case header
    case ghostMode(String)
    case deletedMessages(String)
    case fakeIdentity
    case userbot(String)

    var section: ItemListSectionId {
        switch self {
        case .header:
            return 0
        case .ghostMode, .deletedMessages:
            return 1
        case .fakeIdentity:
            return 2
        case .userbot:
            return 3
        }
    }

    var stableId: Int {
        switch self {
        case .header: return 0
        case .ghostMode: return 1
        case .deletedMessages: return 2
        case .fakeIdentity: return 3
        case .userbot: return 4
        }
    }

    static func < (lhs: WewPagramHubEntry, rhs: WewPagramHubEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramHubControllerArguments
        switch self {
        case .header:
            return WewPagramHeaderItem(presentationData: presentationData, icon: wewLogoImage(side: 84.0), name: "WewPagram", version: wewVersionString, sectionId: self.section)
        case let .ghostMode(label):
            return ItemListDisclosureItem(presentationData: presentationData, icon: wewGhostIcon(), title: "Режим призрака", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openGhostMode()
            })
        case let .deletedMessages(label):
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.deleteChats, title: "Удалённые сообщения", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openDeletedMessages()
            })
        case .fakeIdentity:
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.myProfile, title: "Профиль", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFakeIdentity()
            })
        case let .userbot(label):
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.bot, title: "Юзербот", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openUserbot()
            })
        }
    }
}

public func wewpagramHubController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = WewPagramHubControllerArguments(
        openGhostMode: {
            pushControllerImpl?(wewpagramGhostModeController(context: context))
        },
        openDeletedMessages: {
            pushControllerImpl?(wewpagramDeletedMessagesController(context: context))
        },
        openFakeIdentity: {
            pushControllerImpl?(wewpagramFakeIdentityController(context: context))
        },
        openUserbot: {
            pushControllerImpl?(wewpagramUserbotController(context: context))
        }
    )

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
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
        let userbotLabel = settings.isCloudConfigured ? "Настроен" : ""

        let entries: [WewPagramHubEntry] = [
            .header,
            .ghostMode(ghostLabel),
            .deletedMessages(deletedLabel),
            .fakeIdentity,
            .userbot(userbotLabel)
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("WewPagram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
