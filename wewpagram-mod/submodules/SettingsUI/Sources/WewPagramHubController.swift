import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private let wewVersion = "1.0"

private final class WewPagramHubControllerArguments {
    let openGhostMode: () -> Void
    let openDeletedMessages: () -> Void
    let openFakeIdentity: () -> Void
    let openCloud: () -> Void

    init(openGhostMode: @escaping () -> Void, openDeletedMessages: @escaping () -> Void, openFakeIdentity: @escaping () -> Void, openCloud: @escaping () -> Void) {
        self.openGhostMode = openGhostMode
        self.openDeletedMessages = openDeletedMessages
        self.openFakeIdentity = openFakeIdentity
        self.openCloud = openCloud
    }
}

private enum WewPagramHubEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case privacyHeader, ghostMode, deletedMessages
        case customizeHeader, fakeIdentity
        case integrationHeader, cloud
        case about
    }

    case privacyHeader
    case ghostMode(String)
    case deletedMessages(String)
    case customizeHeader
    case fakeIdentity
    case integrationHeader
    case cloud(String)
    case about

    var section: ItemListSectionId {
        switch self {
        case .privacyHeader, .ghostMode, .deletedMessages:
            return 0
        case .customizeHeader, .fakeIdentity:
            return 1
        case .integrationHeader, .cloud, .about:
            return 2
        }
    }

    var stableId: StableId {
        switch self {
        case .privacyHeader: return .privacyHeader
        case .ghostMode: return .ghostMode
        case .deletedMessages: return .deletedMessages
        case .customizeHeader: return .customizeHeader
        case .fakeIdentity: return .fakeIdentity
        case .integrationHeader: return .integrationHeader
        case .cloud: return .cloud
        case .about: return .about
        }
    }

    private var sortIndex: Int {
        switch self {
        case .privacyHeader: return 0
        case .ghostMode: return 1
        case .deletedMessages: return 2
        case .customizeHeader: return 3
        case .fakeIdentity: return 4
        case .integrationHeader: return 5
        case .cloud: return 6
        case .about: return 7
        }
    }

    static func < (lhs: WewPagramHubEntry, rhs: WewPagramHubEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramHubControllerArguments
        switch self {
        case .privacyHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ПРИВАТНОСТЬ", sectionId: self.section)
        case let .ghostMode(label):
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.security, title: "Режим призрака", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openGhostMode()
            })
        case let .deletedMessages(label):
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.deleteChats, title: "Удалённые сообщения", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openDeletedMessages()
            })
        case .customizeHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "КАСТОМИЗАЦИЯ", sectionId: self.section)
        case .fakeIdentity:
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.myProfile, title: "Профиль", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFakeIdentity()
            })
        case .integrationHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ИНТЕГРАЦИЯ", sectionId: self.section)
        case let .cloud(label):
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.bot, title: "Облако и юзербот", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.openCloud()
            })
        case .about:
            return ItemListTextItem(presentationData: presentationData, text: .plain("WewPagram \(wewVersion)\nВсё, что вы настроили здесь, хранится только на вашем устройстве."), sectionId: self.section)
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
        openCloud: {
            pushControllerImpl?(wewpagramCloudController(context: context))
        }
    )

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = WewPagramSettings.shared
        let ghostLabel = settings.isGhostModeEnabled ? "Вкл" : "Выкл"
        let archiveCount = settings.deletedMessages().count
        let deletedLabel = archiveCount == 0 ? "" : "\(archiveCount)"
        let cloudLabel = settings.isCloudConfigured ? "Подключено" : "Выкл"

        let entries: [WewPagramHubEntry] = [
            .privacyHeader, .ghostMode(ghostLabel), .deletedMessages(deletedLabel),
            .customizeHeader, .fakeIdentity,
            .integrationHeader, .cloud(cloudLabel), .about
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
