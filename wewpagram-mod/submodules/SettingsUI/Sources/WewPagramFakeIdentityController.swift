import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class WewPagramFakeIdentityControllerArguments {
    let updateFakePhoneNumber: (String) -> Void
    let updateFakeUsername: (String) -> Void
    let updateFakeNftUsername: (String) -> Void
    let updateFakeNftPrice: (String) -> Void

    init(
        updateFakePhoneNumber: @escaping (String) -> Void,
        updateFakeUsername: @escaping (String) -> Void,
        updateFakeNftUsername: @escaping (String) -> Void,
        updateFakeNftPrice: @escaping (String) -> Void
    ) {
        self.updateFakePhoneNumber = updateFakePhoneNumber
        self.updateFakeUsername = updateFakeUsername
        self.updateFakeNftUsername = updateFakeNftUsername
        self.updateFakeNftPrice = updateFakeNftPrice
    }
}

private struct WewPagramFakeIdentityState: Equatable {
    var fakePhoneNumber: String
    var fakeUsername: String
    var fakeNftUsername: String
    var fakeNftPrice: String
}

private enum WewPagramFakeIdentityEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case phoneNumber
        case username
        case nftUsername
        case nftPrice
        case footer
    }

    case phoneNumber(String)
    case username(String)
    case nftUsername(String)
    case nftPrice(String)
    case footer(String)

    var section: ItemListSectionId { return 0 }

    var stableId: StableId {
        switch self {
        case .phoneNumber: return .phoneNumber
        case .username: return .username
        case .nftUsername: return .nftUsername
        case .nftPrice: return .nftPrice
        case .footer: return .footer
        }
    }

    private var sortIndex: Int {
        switch self {
        case .phoneNumber: return 0
        case .username: return 1
        case .nftUsername: return 2
        case .nftPrice: return 3
        case .footer: return 4
        }
    }

    static func ==(lhs: WewPagramFakeIdentityEntry, rhs: WewPagramFakeIdentityEntry) -> Bool {
        switch lhs {
        case let .phoneNumber(v): if case .phoneNumber(v) = rhs { return true } else { return false }
        case let .username(v): if case .username(v) = rhs { return true } else { return false }
        case let .nftUsername(v): if case .nftUsername(v) = rhs { return true } else { return false }
        case let .nftPrice(v): if case .nftPrice(v) = rhs { return true } else { return false }
        case let .footer(v): if case .footer(v) = rhs { return true } else { return false }
        }
    }

    static func <(lhs: WewPagramFakeIdentityEntry, rhs: WewPagramFakeIdentityEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramFakeIdentityControllerArguments
        switch self {
        case let .phoneNumber(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Номер"), text: value, placeholder: "Настоящий номер", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { arguments.updateFakePhoneNumber($0) }, action: {})
        case let .username(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Юзернейм"), text: value, placeholder: "Настоящий юзернейм", type: .username, clearType: .always, sectionId: self.section, textUpdated: { arguments.updateFakeUsername($0) }, action: {})
        case let .nftUsername(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "NFT-юзернейм"), text: value, placeholder: "Не задан", type: .username, clearType: .always, sectionId: self.section, textUpdated: { arguments.updateFakeNftUsername($0) }, action: {})
        case let .nftPrice(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Цена NFT"), text: value, placeholder: "Например: 500 TON", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { arguments.updateFakeNftPrice($0) }, action: {})
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func wewpagramFakeIdentityController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let initialState = WewPagramFakeIdentityState(
        fakePhoneNumber: settings.fakePhoneNumber ?? "",
        fakeUsername: settings.fakeUsername ?? "",
        fakeNftUsername: settings.fakeNftUsername ?? "",
        fakeNftPrice: settings.fakeNftPrice ?? ""
    )
    let statePromise = ValuePromise<WewPagramFakeIdentityState>(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WewPagramFakeIdentityState) -> WewPagramFakeIdentityState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let arguments = WewPagramFakeIdentityControllerArguments(
        updateFakePhoneNumber: { value in
            settings.fakePhoneNumber = value.isEmpty ? nil : value
            updateState { var s = $0; s.fakePhoneNumber = value; return s }
        },
        updateFakeUsername: { value in
            settings.fakeUsername = value.isEmpty ? nil : value
            updateState { var s = $0; s.fakeUsername = value; return s }
        },
        updateFakeNftUsername: { value in
            settings.fakeNftUsername = value.isEmpty ? nil : value
            updateState { var s = $0; s.fakeNftUsername = value; return s }
        },
        updateFakeNftPrice: { value in
            settings.fakeNftPrice = value.isEmpty ? nil : value
            updateState { var s = $0; s.fakeNftPrice = value; return s }
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [WewPagramFakeIdentityEntry] = [
            .phoneNumber(state.fakePhoneNumber),
            .username(state.fakeUsername),
            .nftUsername(state.fakeNftUsername),
            .nftPrice(state.fakeNftPrice),
            .footer("Эти поля меняют только то, что ты видишь в своём профиле в приложении. Собеседники видят твои настоящие данные — изменения никуда не отправляются.")
        ]

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Профиль"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
