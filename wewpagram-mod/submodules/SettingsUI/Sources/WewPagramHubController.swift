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
    let openFakeIdentity: () -> Void

    init(openGhostMode: @escaping () -> Void, openFakeIdentity: @escaping () -> Void) {
        self.openGhostMode = openGhostMode
        self.openFakeIdentity = openFakeIdentity
    }
}

private enum WewPagramHubEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case ghostMode
        case fakeIdentity
    }

    case ghostMode
    case fakeIdentity

    var section: ItemListSectionId {
        return 0
    }

    var stableId: StableId {
        switch self {
        case .ghostMode:    return .ghostMode
        case .fakeIdentity: return .fakeIdentity
        }
    }

    static func == (lhs: WewPagramHubEntry, rhs: WewPagramHubEntry) -> Bool {
        switch (lhs, rhs) {
        case (.ghostMode, .ghostMode), (.fakeIdentity, .fakeIdentity):
            return true
        default:
            return false
        }
    }

    static func < (lhs: WewPagramHubEntry, rhs: WewPagramHubEntry) -> Bool {
        switch (lhs, rhs) {
        case (.ghostMode, .fakeIdentity):
            return true
        default:
            return false
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramHubControllerArguments
        switch self {
        case .ghostMode:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Режим призрака", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openGhostMode()
            })
        case .fakeIdentity:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Профиль", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFakeIdentity()
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
        openFakeIdentity: {
            pushControllerImpl?(wewpagramFakeIdentityController(context: context))
        }
    )

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [WewPagramHubEntry] = [.ghostMode, .fakeIdentity]

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
