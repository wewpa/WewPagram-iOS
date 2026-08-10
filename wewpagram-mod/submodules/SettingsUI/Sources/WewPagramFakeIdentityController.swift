import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private func wewApplyStarsDelta(context: AccountContext, settings: WewPagramSettings) {
    let target = settings.fakeRatingEnabled ? settings.fakeRatingStars : 0
    let delta = target - settings.injectedFakeStars
    guard delta != 0, let starsContext = context.starsContext else { return }
    starsContext.add(balance: StarsAmount(value: Int64(delta), nanos: 0))
    settings.injectedFakeStars = target
}

private final class WewPagramFakeIdentityControllerArguments {
    let updateFakePhoneNumber: (String) -> Void
    let updateNewNftUsername: (String) -> Void
    let updateNewNftPrice: (String) -> Void
    let addNftEntry: () -> Void
    let removeNftEntry: (Int) -> Void
    let toggleFakeRating: (Bool) -> Void
    let updateFakeRatingLevel: (String) -> Void
    let updateFakeRatingStars: (String) -> Void

    init(
        updateFakePhoneNumber: @escaping (String) -> Void,
        updateNewNftUsername: @escaping (String) -> Void,
        updateNewNftPrice: @escaping (String) -> Void,
        addNftEntry: @escaping () -> Void,
        removeNftEntry: @escaping (Int) -> Void,
        toggleFakeRating: @escaping (Bool) -> Void,
        updateFakeRatingLevel: @escaping (String) -> Void,
        updateFakeRatingStars: @escaping (String) -> Void
    ) {
        self.updateFakePhoneNumber = updateFakePhoneNumber
        self.updateNewNftUsername = updateNewNftUsername
        self.updateNewNftPrice = updateNewNftPrice
        self.addNftEntry = addNftEntry
        self.removeNftEntry = removeNftEntry
        self.toggleFakeRating = toggleFakeRating
        self.updateFakeRatingLevel = updateFakeRatingLevel
        self.updateFakeRatingStars = updateFakeRatingStars
    }
}

private struct WewPagramFakeIdentityState: Equatable {
    var fakePhoneNumber: String
    var nftEntries: [WewPagramSettings.FakeNftEntry]
    var newNftUsername: String
    var newNftPrice: String
    var fakeRatingEnabled: Bool
    var fakeRatingLevel: String
    var fakeRatingStars: String
}

private enum WewPagramFakeIdentityEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case phoneNumber
        case identityFooter
        case nftHeader
        case nftEntry(Int)
        case nftAddUsername
        case nftAddPrice
        case nftAddButton
        case nftFooter
        case ratingHeader
        case ratingToggle
        case ratingLevel
        case ratingStars
        case ratingFooter
    }

    case phoneNumber(String)
    case identityFooter(String)
    case nftHeader(String)
    case nftEntry(index: Int, username: String, price: String)
    case nftAddUsername(String)
    case nftAddPrice(String)
    case nftAddButton
    case nftFooter(String)
    case ratingHeader(String)
    case ratingToggle(Bool)
    case ratingLevel(String)
    case ratingStars(String)
    case ratingFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .phoneNumber, .identityFooter:
            return 0
        case .nftHeader, .nftEntry, .nftAddUsername, .nftAddPrice, .nftAddButton, .nftFooter:
            return 1
        case .ratingHeader, .ratingToggle, .ratingLevel, .ratingStars, .ratingFooter:
            return 2
        }
    }

    var stableId: StableId {
        switch self {
        case .phoneNumber: return .phoneNumber
        case .identityFooter: return .identityFooter
        case .nftHeader: return .nftHeader
        case let .nftEntry(index, _, _): return .nftEntry(index)
        case .nftAddUsername: return .nftAddUsername
        case .nftAddPrice: return .nftAddPrice
        case .nftAddButton: return .nftAddButton
        case .nftFooter: return .nftFooter
        case .ratingHeader: return .ratingHeader
        case .ratingToggle: return .ratingToggle
        case .ratingLevel: return .ratingLevel
        case .ratingStars: return .ratingStars
        case .ratingFooter: return .ratingFooter
        }
    }

    private var sortIndex: Int {
        switch self {
        case .phoneNumber: return 0
        case .identityFooter: return 1
        case .nftHeader: return 2
        case let .nftEntry(index, _, _): return 3 + index
        case .nftAddUsername: return 1000
        case .nftAddPrice: return 1001
        case .nftAddButton: return 1002
        case .nftFooter: return 1003
        case .ratingHeader: return 1004
        case .ratingToggle: return 1005
        case .ratingLevel: return 1006
        case .ratingStars: return 1007
        case .ratingFooter: return 1008
        }
    }

    static func ==(lhs: WewPagramFakeIdentityEntry, rhs: WewPagramFakeIdentityEntry) -> Bool {
        switch lhs {
        case let .phoneNumber(v): if case .phoneNumber(v) = rhs { return true } else { return false }
        case let .identityFooter(v): if case .identityFooter(v) = rhs { return true } else { return false }
        case let .nftHeader(v): if case .nftHeader(v) = rhs { return true } else { return false }
        case let .nftEntry(i, u, p): if case .nftEntry(i, u, p) = rhs { return true } else { return false }
        case let .nftAddUsername(v): if case .nftAddUsername(v) = rhs { return true } else { return false }
        case let .nftAddPrice(v): if case .nftAddPrice(v) = rhs { return true } else { return false }
        case .nftAddButton: if case .nftAddButton = rhs { return true } else { return false }
        case let .nftFooter(v): if case .nftFooter(v) = rhs { return true } else { return false }
        case let .ratingHeader(v): if case .ratingHeader(v) = rhs { return true } else { return false }
        case let .ratingToggle(v): if case .ratingToggle(v) = rhs { return true } else { return false }
        case let .ratingLevel(v): if case .ratingLevel(v) = rhs { return true } else { return false }
        case let .ratingStars(v): if case .ratingStars(v) = rhs { return true } else { return false }
        case let .ratingFooter(v): if case .ratingFooter(v) = rhs { return true } else { return false }
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
        case let .identityFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .nftHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .nftEntry(index, username, price):
            let label = price.isEmpty ? "" : price
            return ItemListDisclosureItem(presentationData: presentationData, title: "@\(username)", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.removeNftEntry(index)
            })
        case let .nftAddUsername(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Юзернейм"), text: value, placeholder: "новый_nft_юз", type: .username, clearType: .always, sectionId: self.section, textUpdated: { arguments.updateNewNftUsername($0) }, action: {})
        case let .nftAddPrice(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Цена"), text: value, placeholder: "Например: 500 TON", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { arguments.updateNewNftPrice($0) }, action: {})
        case .nftAddButton:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить NFT-юзернейм", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addNftEntry()
            })
        case let .nftFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .ratingHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ratingToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Фейк-рейтинг", value: value, sectionId: self.section, style: .blocks, updated: { arguments.toggleFakeRating($0) })
        case let .ratingLevel(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Уровень"), text: value, placeholder: "1", type: .number, clearType: .always, sectionId: self.section, textUpdated: { arguments.updateFakeRatingLevel($0) }, action: {})
        case let .ratingStars(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Звёзды"), text: value, placeholder: "0", type: .number, clearType: .always, sectionId: self.section, textUpdated: { arguments.updateFakeRatingStars($0) }, action: {})
        case let .ratingFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func wewpagramFakeIdentityController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let initialState = WewPagramFakeIdentityState(
        fakePhoneNumber: settings.fakePhoneNumber ?? "",
        nftEntries: settings.fakeNftEntries,
        newNftUsername: "",
        newNftPrice: "",
        fakeRatingEnabled: settings.fakeRatingEnabled,
        fakeRatingLevel: String(settings.fakeRatingLevel),
        fakeRatingStars: String(settings.fakeRatingStars)
    )
    let statePromise = ValuePromise<WewPagramFakeIdentityState>(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WewPagramFakeIdentityState) -> WewPagramFakeIdentityState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var presentControllerImpl: ((ViewController) -> Void)?

    wewApplyStarsDelta(context: context, settings: settings)

    let arguments = WewPagramFakeIdentityControllerArguments(
        updateFakePhoneNumber: { value in
            settings.fakePhoneNumber = value.isEmpty ? nil : value
            updateState { var s = $0; s.fakePhoneNumber = value; return s }
        },
        updateNewNftUsername: { value in
            updateState { var s = $0; s.newNftUsername = value; return s }
        },
        updateNewNftPrice: { value in
            updateState { var s = $0; s.newNftPrice = value; return s }
        },
        addNftEntry: {
            let current = stateValue.with { $0 }
            let username = current.newNftUsername.trimmingCharacters(in: .whitespaces)
            guard !username.isEmpty else { return }
            settings.addFakeNftEntry(username: username, price: current.newNftPrice)
            updateState { var s = $0; s.nftEntries = settings.fakeNftEntries; s.newNftUsername = ""; s.newNftPrice = ""; return s }
        },
        removeNftEntry: { index in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: "Удалить этот NFT-юзернейм?", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                    settings.removeFakeNftEntry(at: index)
                    updateState { var s = $0; s.nftEntries = settings.fakeNftEntries; return s }
                })
            ])
            presentControllerImpl?(alert)
        },
        toggleFakeRating: { value in
            settings.fakeRatingEnabled = value
            wewApplyStarsDelta(context: context, settings: settings)
            updateState { var s = $0; s.fakeRatingEnabled = value; return s }
        },
        updateFakeRatingLevel: { value in
            settings.fakeRatingLevel = Int(value) ?? 1
            updateState { var s = $0; s.fakeRatingLevel = value; return s }
        },
        updateFakeRatingStars: { value in
            settings.fakeRatingStars = Int(value) ?? 0
            wewApplyStarsDelta(context: context, settings: settings)
            updateState { var s = $0; s.fakeRatingStars = value; return s }
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [WewPagramFakeIdentityEntry] = [
            .phoneNumber(state.fakePhoneNumber),
            .identityFooter("Номер меняет то, что видно только тебе в приложении. Собеседники видят настоящие данные — изменения никуда не отправляются."),
            .nftHeader("NFT-ЮЗЕРНЕЙМЫ")
        ]
        for (index, entry) in state.nftEntries.enumerated() {
            entries.append(.nftEntry(index: index, username: entry.username, price: entry.price))
        }
        entries.append(.nftAddUsername(state.newNftUsername))
        entries.append(.nftAddPrice(state.newNftPrice))
        entries.append(.nftAddButton)
        entries.append(.nftFooter("Добавляются к твоим настоящим доп. юзернеймам на экране \"My Profile\" (тап по записи — удалить). Обычный юзернейм не подменяется."))
        entries.append(.ratingHeader("РЕЙТИНГ ПРОФИЛЯ"))
        entries.append(.ratingToggle(state.fakeRatingEnabled))
        if state.fakeRatingEnabled {
            entries.append(.ratingLevel(state.fakeRatingLevel))
            entries.append(.ratingStars(state.fakeRatingStars))
        }
        entries.append(.ratingFooter("Подменяет бейдж рейтинга и баланс Stars в списке Settings. Тоже только локально."))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Профиль"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
