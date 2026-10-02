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

// Encodes a chosen real gift and stores it in WewPagramSettings. We
// deliberately do NOT touch the real synced ProfileGiftsContext/Postbox
// state — any real network sync would just wipe it out again. Instead this
// gets merged into the displayed grid at render time (GiftsListView.swift).
private func wewSaveFakeGift(_ pick: StarGift, completion: @escaping (Bool) -> Void) {
    let fakeEntry = ProfileGiftsContext.State.StarGift(
        gift: pick,
        reference: nil,
        fromPeer: nil,
        date: Int32(Date().timeIntervalSince1970),
        text: nil,
        entities: nil,
        nameHidden: false,
        savedToProfile: true,
        pinnedToTop: true,
        convertStars: nil,
        canUpgrade: false,
        canExportDate: nil,
        upgradeStars: nil,
        transferStars: nil,
        canTransferDate: nil,
        canResaleDate: nil,
        collectionIds: nil,
        prepaidUpgradeHash: nil,
        upgradeSeparate: false,
        dropOriginalDetailsStars: nil,
        number: nil,
        isRefunded: false,
        canCraftAt: nil
    )
    guard let encoded = try? JSONEncoder().encode(fakeEntry) else {
        completion(false)
        return
    }
    WewPagramSettings.shared.addFakeGiftData(encoded)
    completion(true)
}

private struct WewFakeGiftRow: Equatable {
    var id: Int64
    var title: String
    var label: String
}

private func wewFakeGiftRows() -> [WewFakeGiftRow] {
    let decoder = JSONDecoder()
    var rows: [WewFakeGiftRow] = []
    for (index, record) in WewPagramSettings.shared.fakeGiftRecords.enumerated() {
        var title = "Подарок #\(index + 1)"
        var label = ""
        if let gift = try? decoder.decode(ProfileGiftsContext.State.StarGift.self, from: record.data) {
            switch gift.gift {
            case let .generic(generic):
                if let t = generic.title, !t.isEmpty {
                    title = t
                }
                label = "\(generic.price) ★"
            case let .unique(unique):
                title = "\(unique.title) #\(unique.number)"
            }
        }
        var flags: [String] = []
        if record.pinned { flags.append("закреплён") }
        if record.hidden { flags.append("скрыт") }
        if !flags.isEmpty {
            label = label.isEmpty ? flags.joined(separator: ", ") : label + " · " + flags.joined(separator: ", ")
        }
        rows.append(WewFakeGiftRow(id: record.id, title: title, label: label))
    }
    return rows
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
    let addGift: () -> Void
    let removeGift: (Int64) -> Void
    let removeAllGifts: () -> Void

    init(
        updateFakePhoneNumber: @escaping (String) -> Void,
        updateNewNftUsername: @escaping (String) -> Void,
        updateNewNftPrice: @escaping (String) -> Void,
        addNftEntry: @escaping () -> Void,
        removeNftEntry: @escaping (Int) -> Void,
        toggleFakeRating: @escaping (Bool) -> Void,
        updateFakeRatingLevel: @escaping (String) -> Void,
        updateFakeRatingStars: @escaping (String) -> Void,
        addGift: @escaping () -> Void,
        removeGift: @escaping (Int64) -> Void,
        removeAllGifts: @escaping () -> Void
    ) {
        self.updateFakePhoneNumber = updateFakePhoneNumber
        self.updateNewNftUsername = updateNewNftUsername
        self.updateNewNftPrice = updateNewNftPrice
        self.addNftEntry = addNftEntry
        self.removeNftEntry = removeNftEntry
        self.toggleFakeRating = toggleFakeRating
        self.updateFakeRatingLevel = updateFakeRatingLevel
        self.updateFakeRatingStars = updateFakeRatingStars
        self.addGift = addGift
        self.removeGift = removeGift
        self.removeAllGifts = removeAllGifts
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
    var fakeGifts: [WewFakeGiftRow]
}

private enum WewPagramFakeIdentityEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case phoneNumber
        case nftHeader
        case nftEntry(Int)
        case nftAddUsername
        case nftAddPrice
        case nftAddButton
        case ratingHeader
        case ratingToggle
        case ratingLevel
        case ratingStars
        case giftsHeader
        case giftsAddButton
        case giftEntry(Int64)
        case giftsDeleteAll
    }

    case phoneNumber(String)
    case nftHeader(String)
    case nftEntry(index: Int, username: String, price: String)
    case nftAddUsername(String)
    case nftAddPrice(String)
    case nftAddButton
    case ratingHeader(String)
    case ratingToggle(Bool)
    case ratingLevel(String)
    case ratingStars(String)
    case giftsHeader(String)
    case giftsAddButton
    case giftEntry(index: Int, id: Int64, title: String, label: String)
    case giftsDeleteAll

    var section: ItemListSectionId {
        switch self {
        case .phoneNumber:
            return 0
        case .nftHeader, .nftEntry, .nftAddUsername, .nftAddPrice, .nftAddButton:
            return 1
        case .ratingHeader, .ratingToggle, .ratingLevel, .ratingStars:
            return 2
        case .giftsHeader, .giftsAddButton, .giftEntry, .giftsDeleteAll:
            return 3
        }
    }

    var stableId: StableId {
        switch self {
        case .phoneNumber: return .phoneNumber
        case .nftHeader: return .nftHeader
        case let .nftEntry(index, _, _): return .nftEntry(index)
        case .nftAddUsername: return .nftAddUsername
        case .nftAddPrice: return .nftAddPrice
        case .nftAddButton: return .nftAddButton
        case .ratingHeader: return .ratingHeader
        case .ratingToggle: return .ratingToggle
        case .ratingLevel: return .ratingLevel
        case .ratingStars: return .ratingStars
        case .giftsHeader: return .giftsHeader
        case .giftsAddButton: return .giftsAddButton
        case let .giftEntry(_, id, _, _): return .giftEntry(id)
        case .giftsDeleteAll: return .giftsDeleteAll
        }
    }

    private var sortIndex: Int {
        switch self {
        case .phoneNumber: return 0
        case .nftHeader: return 1
        case let .nftEntry(index, _, _): return 2 + index
        case .nftAddUsername: return 1000
        case .nftAddPrice: return 1001
        case .nftAddButton: return 1002
        case .ratingHeader: return 1003
        case .ratingToggle: return 1004
        case .ratingLevel: return 1005
        case .ratingStars: return 1006
        case .giftsHeader: return 1007
        case .giftsAddButton: return 1008
        case let .giftEntry(index, _, _, _): return 1100 + index
        case .giftsDeleteAll: return 100000
        }
    }

    static func ==(lhs: WewPagramFakeIdentityEntry, rhs: WewPagramFakeIdentityEntry) -> Bool {
        switch lhs {
        case let .phoneNumber(v): if case .phoneNumber(v) = rhs { return true } else { return false }
        case let .nftHeader(v): if case .nftHeader(v) = rhs { return true } else { return false }
        case let .nftEntry(i, u, p): if case .nftEntry(i, u, p) = rhs { return true } else { return false }
        case let .nftAddUsername(v): if case .nftAddUsername(v) = rhs { return true } else { return false }
        case let .nftAddPrice(v): if case .nftAddPrice(v) = rhs { return true } else { return false }
        case .nftAddButton: if case .nftAddButton = rhs { return true } else { return false }
        case let .ratingHeader(v): if case .ratingHeader(v) = rhs { return true } else { return false }
        case let .ratingToggle(v): if case .ratingToggle(v) = rhs { return true } else { return false }
        case let .ratingLevel(v): if case .ratingLevel(v) = rhs { return true } else { return false }
        case let .ratingStars(v): if case .ratingStars(v) = rhs { return true } else { return false }
        case let .giftsHeader(v): if case .giftsHeader(v) = rhs { return true } else { return false }
        case .giftsAddButton: if case .giftsAddButton = rhs { return true } else { return false }
        case let .giftEntry(i, id, t, l): if case .giftEntry(i, id, t, l) = rhs { return true } else { return false }
        case .giftsDeleteAll: if case .giftsDeleteAll = rhs { return true } else { return false }
        }
    }

    static func <(lhs: WewPagramFakeIdentityEntry, rhs: WewPagramFakeIdentityEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramFakeIdentityControllerArguments
        switch self {
        case let .phoneNumber(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Номер"), text: value, placeholder: "", sectionId: self.section, style: .blocks, updated: { arguments.updateFakePhoneNumber($0) })
        case let .nftHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .nftEntry(index, username, price):
            let label = price.isEmpty ? "" : price
            return ItemListDisclosureItem(presentationData: presentationData, title: "@\(username)", label: label, sectionId: self.section, style: .blocks, action: {
                arguments.removeNftEntry(index)
            })
        case let .nftAddUsername(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "NFT юз"), text: value, placeholder: "", sectionId: self.section, style: .blocks, updated: { arguments.updateNewNftUsername($0) })
        case let .nftAddPrice(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Цена"), text: value, placeholder: "", sectionId: self.section, style: .blocks, updated: { arguments.updateNewNftPrice($0) })
        case .nftAddButton:
            return ItemListActionItem(presentationData: presentationData, title: "Добавить NFT юз", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addNftEntry()
            })
        case let .ratingHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .ratingToggle(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Рейтинг", value: value, sectionId: self.section, style: .blocks, updated: { arguments.toggleFakeRating($0) })
        case let .ratingLevel(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Уровень"), text: value, placeholder: "1", sectionId: self.section, style: .blocks, updated: { arguments.updateFakeRatingLevel($0) })
        case let .ratingStars(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Баланс"), text: value, placeholder: "0", sectionId: self.section, style: .blocks, updated: { arguments.updateFakeRatingStars($0) })
        case let .giftsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .giftsAddButton:
            return ItemListActionItem(presentationData: presentationData, title: "Выбрать подарок", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.addGift()
            })
        case let .giftEntry(_, id, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, title: title, label: label, sectionId: self.section, style: .blocks, action: {
                arguments.removeGift(id)
            })
        case .giftsDeleteAll:
            return ItemListActionItem(presentationData: presentationData, title: "Удалить все подарки", kind: .destructive, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.removeAllGifts()
            })
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
        fakeRatingStars: String(settings.fakeRatingStars),
        fakeGifts: wewFakeGiftRows()
    )
    let statePromise = ValuePromise<WewPagramFakeIdentityState>(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WewPagramFakeIdentityState) -> WewPagramFakeIdentityState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var presentControllerImpl: ((ViewController) -> Void)?
    var pushControllerImpl: ((ViewController) -> Void)?

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
            let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: "Удалить этот NFT юз?", actions: [
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
        },
        addGift: {
            let picker = wewpagramGiftPickerController(context: context) { pickedGift in
                wewSaveFakeGift(pickedGift) { success in
                    guard success else { return }
                    updateState { var s = $0; s.fakeGifts = wewFakeGiftRows(); return s }
                }
            }
            pushControllerImpl?(picker)
        },
        removeGift: { id in
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: "Удалить этот подарок из профиля?", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: "Удалить", action: {
                    settings.removeFakeGift(id: id)
                    updateState { var s = $0; s.fakeGifts = wewFakeGiftRows(); return s }
                })
            ])
            presentControllerImpl?(alert)
        },
        removeAllGifts: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: "Удалить все добавленные подарки?", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: "Удалить все", action: {
                    settings.removeAllFakeGifts()
                    updateState { var s = $0; s.fakeGifts = wewFakeGiftRows(); return s }
                })
            ])
            presentControllerImpl?(alert)
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [WewPagramFakeIdentityEntry] = [
            .phoneNumber(state.fakePhoneNumber),
            .nftHeader("NFT ЮЗЕРНЕЙМЫ")
        ]
        for (index, entry) in state.nftEntries.enumerated() {
            entries.append(.nftEntry(index: index, username: entry.username, price: entry.price))
        }
        entries.append(.nftAddUsername(state.newNftUsername))
        entries.append(.nftAddPrice(state.newNftPrice))
        entries.append(.nftAddButton)
        entries.append(.ratingHeader("РЕЙТИНГ"))
        entries.append(.ratingToggle(state.fakeRatingEnabled))
        if state.fakeRatingEnabled {
            entries.append(.ratingLevel(state.fakeRatingLevel))
            entries.append(.ratingStars(state.fakeRatingStars))
        }
        entries.append(.giftsHeader("ПОДАРКИ"))
        entries.append(.giftsAddButton)
        for (index, row) in state.fakeGifts.enumerated() {
            entries.append(.giftEntry(index: index, id: row.id, title: row.title, label: row.label))
        }
        if !state.fakeGifts.isEmpty {
            entries.append(.giftsDeleteAll)
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Профиль"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    return controller
}
