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
    let updateFakeNftUsername: (String) -> Void
    let updateFakeNftPrice: (String) -> Void
    let toggleFakeRating: (Bool) -> Void
    let updateFakeRatingLevel: (String) -> Void
    let updateFakeRatingStars: (String) -> Void

    init(
        updateFakePhoneNumber: @escaping (String) -> Void,
        updateFakeNftUsername: @escaping (String) -> Void,
        updateFakeNftPrice: @escaping (String) -> Void,
        toggleFakeRating: @escaping (Bool) -> Void,
        updateFakeRatingLevel: @escaping (String) -> Void,
        updateFakeRatingStars: @escaping (String) -> Void
    ) {
        self.updateFakePhoneNumber = updateFakePhoneNumber
        self.updateFakeNftUsername = updateFakeNftUsername
        self.updateFakeNftPrice = updateFakeNftPrice
        self.toggleFakeRating = toggleFakeRating
        self.updateFakeRatingLevel = updateFakeRatingLevel
        self.updateFakeRatingStars = updateFakeRatingStars
    }
}

private struct WewPagramFakeIdentityState: Equatable {
    var fakePhoneNumber: String
    var fakeUsername: String
    var fakeNftUsername: String
    var fakeNftPrice: String
    var fakeRatingEnabled: Bool
    var fakeRatingLevel: String
    var fakeRatingStars: String
}

private enum WewPagramFakeIdentityEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case phoneNumber
        case nftUsername
        case nftPrice
        case identityFooter
        case ratingHeader
        case ratingToggle
        case ratingLevel
        case ratingStars
        case ratingFooter
    }

    case phoneNumber(String)
    case nftUsername(String)
    case nftPrice(String)
    case identityFooter(String)
    case ratingHeader(String)
    case ratingToggle(Bool)
    case ratingLevel(String)
    case ratingStars(String)
    case ratingFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .phoneNumber, .nftUsername, .nftPrice, .identityFooter:
            return 0
        case .ratingHeader, .ratingToggle, .ratingLevel, .ratingStars, .ratingFooter:
            return 1
        }
    }

    var stableId: StableId {
        switch self {
        case .phoneNumber: return .phoneNumber
        case .nftUsername: return .nftUsername
        case .nftPrice: return .nftPrice
        case .identityFooter: return .identityFooter
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
        case .nftUsername: return 1
        case .nftPrice: return 2
        case .identityFooter: return 3
        case .ratingHeader: return 4
        case .ratingToggle: return 5
        case .ratingLevel: return 6
        case .ratingStars: return 7
        case .ratingFooter: return 8
        }
    }

    static func ==(lhs: WewPagramFakeIdentityEntry, rhs: WewPagramFakeIdentityEntry) -> Bool {
        switch lhs {
        case let .phoneNumber(v): if case .phoneNumber(v) = rhs { return true } else { return false }
        case let .nftUsername(v): if case .nftUsername(v) = rhs { return true } else { return false }
        case let .nftPrice(v): if case .nftPrice(v) = rhs { return true } else { return false }
        case let .identityFooter(v): if case .identityFooter(v) = rhs { return true } else { return false }
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
        case let .nftUsername(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "NFT-юзернейм"), text: value, placeholder: "Не задан", type: .username, clearType: .always, sectionId: self.section, textUpdated: { arguments.updateFakeNftUsername($0) }, action: {})
        case let .nftPrice(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Цена NFT"), text: value, placeholder: "Например: 500 TON", type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { arguments.updateFakeNftPrice($0) }, action: {})
        case let .identityFooter(text):
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
        fakeUsername: settings.fakeUsername ?? "",
        fakeNftUsername: settings.fakeNftUsername ?? "",
        fakeNftPrice: settings.fakeNftPrice ?? "",
        fakeRatingEnabled: settings.fakeRatingEnabled,
        fakeRatingLevel: String(settings.fakeRatingLevel),
        fakeRatingStars: String(settings.fakeRatingStars)
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
        updateFakeNftUsername: { value in
            settings.fakeNftUsername = value.isEmpty ? nil : value
            updateState { var s = $0; s.fakeNftUsername = value; return s }
        },
        updateFakeNftPrice: { value in
            settings.fakeNftPrice = value.isEmpty ? nil : value
            updateState { var s = $0; s.fakeNftPrice = value; return s }
        },
        toggleFakeRating: { value in
            settings.fakeRatingEnabled = value
            updateState { var s = $0; s.fakeRatingEnabled = value; return s }
        },
        updateFakeRatingLevel: { value in
            settings.fakeRatingLevel = Int(value) ?? 1
            updateState { var s = $0; s.fakeRatingLevel = value; return s }
        },
        updateFakeRatingStars: { value in
            settings.fakeRatingStars = Int(value) ?? 0
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
            .nftUsername(state.fakeNftUsername),
            .nftPrice(state.fakeNftPrice),
            .identityFooter("Эти поля меняют только то, что ты видишь в своём профиле в приложении. Собеседники видят твои настоящие данные — изменения никуда не отправляются."),
            .ratingHeader("РЕЙТИНГ ПРОФИЛЯ"),
            .ratingToggle(state.fakeRatingEnabled)
        ]
        if state.fakeRatingEnabled {
            entries.append(.ratingLevel(state.fakeRatingLevel))
            entries.append(.ratingStars(state.fakeRatingStars))
        }
        entries.append(.ratingFooter("Подменяет бейдж рейтинга (уровень и число звёзд) рядом с именем в Settings. Тоже только локально."))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Профиль"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
