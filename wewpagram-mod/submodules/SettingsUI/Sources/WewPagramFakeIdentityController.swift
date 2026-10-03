import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext
import ReactionImageComponent

// MARK: - Shared helpers

// One generic list entry that carries its own builder. `signature` describes
// everything that affects how the row looks, so the list only re-renders a
// row when its content really changed.
private final class WewEntry: ItemListNodeEntry {
    let order: Int
    let sectionValue: ItemListSectionId
    let signature: String
    let build: (ItemListPresentationData) -> ListViewItem

    init(order: Int, section: ItemListSectionId, signature: String, build: @escaping (ItemListPresentationData) -> ListViewItem) {
        self.order = order
        self.sectionValue = section
        self.signature = signature
        self.build = build
    }

    var section: ItemListSectionId { return self.sectionValue }
    var stableId: Int { return self.order }

    static func == (lhs: WewEntry, rhs: WewEntry) -> Bool {
        return lhs.order == rhs.order && lhs.sectionValue == rhs.sectionValue && lhs.signature == rhs.signature
    }

    static func < (lhs: WewEntry, rhs: WewEntry) -> Bool {
        return lhs.order < rhs.order
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        return self.build(presentationData)
    }
}

private struct WewNoArguments {}

private func wewListController(context: AccountContext, title: String, entries: Signal<[WewEntry], NoError>) -> ItemListController {
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, entries)
    |> map { presentationData, entries -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(title),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, WewNoArguments()))
    }
    return ItemListController(context: context, state: signal)
}

private func wewHeader(_ order: Int, _ section: ItemListSectionId, _ text: String) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "h|" + text, build: { pd in
        return ItemListSectionHeaderItem(presentationData: pd, text: text, sectionId: section)
    })
}

private func wewInput(_ order: Int, _ section: ItemListSectionId, title: String, text: String, placeholder: String, number: Bool = false, update: @escaping (String) -> Void) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "i|\(title)|\(text)|\(placeholder)", build: { pd in
        let type: ItemListSingleLineInputItemType = number ? .number : .regular(capitalization: false, autocorrection: false)
        return ItemListSingleLineInputItem(presentationData: pd, title: NSAttributedString(string: title), text: text, placeholder: placeholder, type: type, sectionId: section, textUpdated: { update($0) }, action: {})
    })
}

private func wewSwitch(_ order: Int, _ section: ItemListSectionId, icon: UIImage?, title: String, value: Bool, update: @escaping (Bool) -> Void) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "s|\(title)|\(value)", build: { pd in
        return ItemListSwitchItem(presentationData: pd, icon: icon, title: title, value: value, sectionId: section, style: .blocks, updated: { update($0) })
    })
}

private func wewAction(_ order: Int, _ section: ItemListSectionId, title: String, destructive: Bool = false, action: @escaping () -> Void) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "a|\(title)", build: { pd in
        return ItemListActionItem(presentationData: pd, title: title, kind: destructive ? .destructive : .generic, alignment: .natural, sectionId: section, style: .blocks, action: action)
    })
}

private func wewRow(_ order: Int, _ section: ItemListSectionId, icon: UIImage?, title: String, label: String, action: (() -> Void)?) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "r|\(title)|\(label)|\(icon != nil)", build: { pd in
        return ItemListDisclosureItem(presentationData: pd, icon: icon, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: action == nil ? .none : .arrow, action: action)
    })
}

private func wewConfirm(context: AccountContext, controller: ViewController?, text: String, confirmTitle: String, handler: @escaping () -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: text, actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .destructiveAction, title: confirmTitle, action: handler)
    ])
    controller?.present(alert, in: .window(.root))
}

// Balance is applied on top of the real Stars balance as a delta, so toggling
// or editing the fake amount never compounds.
private func wewApplyStarsDelta(context: AccountContext, settings: WewPagramSettings) {
    let target = settings.fakeBalanceEnabled ? settings.fakeBalanceStars : 0
    let delta = target - settings.injectedFakeStars
    guard delta != 0, let starsContext = context.starsContext else { return }
    starsContext.add(balance: StarsAmount(value: Int64(delta), nanos: 0))
    settings.injectedFakeStars = target
}

private func wewNumberText(_ value: Int) -> String {
    return value == 0 ? "" : String(value)
}

// MARK: - Gift storage helper

// Encodes a chosen real gift and stores it locally. We deliberately do NOT
// touch the real synced ProfileGiftsContext/Postbox state - any real network
// sync would just wipe it out. It is merged into the displayed grid at render
// time (GiftsListView.swift).
private func wewSaveFakeGift(_ pick: StarGift) -> Bool {
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
        return false
    }
    WewPagramSettings.shared.addFakeGiftData(encoded)
    return true
}

private struct WewFakeGiftRow: Equatable {
    var id: Int64
    var title: String
    var label: String
}

private func wewFakeGiftRows() -> (rows: [WewFakeGiftRow], files: [Int64: TelegramMediaFile]) {
    let decoder = JSONDecoder()
    var rows: [WewFakeGiftRow] = []
    var files: [Int64: TelegramMediaFile] = [:]
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
                files[record.id] = generic.file
            case let .unique(unique):
                title = "\(unique.title) #\(unique.number)"
                for attribute in unique.attributes {
                    if case let .model(_, file, _, _) = attribute {
                        files[record.id] = file
                        break
                    }
                }
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
    return (rows, files)
}

// MARK: - Phone number

private func wewPhoneController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let state = ValuePromise<String>(settings.fakePhoneNumber ?? "", ignoreRepeated: true)

    let entries = state.get() |> map { value -> [WewEntry] in
        return [
            wewHeader(0, 0, "НОМЕР В ПРОФИЛЕ"),
            wewInput(1, 0, title: "Номер", text: value, placeholder: "+7 900 000-00-00", update: { text in
                let trimmed = text.trimmingCharacters(in: .whitespaces)
                settings.fakePhoneNumber = trimmed.isEmpty ? nil : trimmed
                settings.notifyProfileChanged()
                state.set(text)
            })
        ]
    }
    return wewListController(context: context, title: "Номер телефона", entries: entries)
}

// MARK: - NFT usernames

private struct WewNftState: Equatable {
    var entries: [WewPagramSettings.FakeNftEntry]
    var newUsername: String
    var newPrice: String
}

private func wewNftController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let initial = WewNftState(entries: settings.fakeNftEntries, newUsername: "", newPrice: "")
    let state = ValuePromise<WewNftState>(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let update: ((WewNftState) -> WewNftState) -> Void = { f in
        state.set(stateValue.modify(f))
    }

    var controllerRef: ViewController?

    let entries = state.get() |> map { s -> [WewEntry] in
        var result: [WewEntry] = [wewHeader(0, 0, "ВАШИ NFT-ЮЗЕРНЕЙМЫ")]
        for (index, entry) in s.entries.enumerated() {
            result.append(wewRow(10 + index, 0, icon: PresentationResourcesSettings.ton, title: "@" + entry.username, label: entry.price, action: {
                wewConfirm(context: context, controller: controllerRef, text: "Удалить @\(entry.username)?", confirmTitle: "Удалить", handler: {
                    settings.removeFakeNftEntry(at: index)
                    settings.notifyProfileChanged()
                    update { var n = $0; n.entries = settings.fakeNftEntries; return n }
                })
            }))
        }
        result.append(wewHeader(1000, 1, "ДОБАВИТЬ"))
        result.append(wewInput(1001, 1, title: "Юзернейм", text: s.newUsername, placeholder: "username", update: { text in
            update { var n = $0; n.newUsername = text; return n }
        }))
        result.append(wewInput(1002, 1, title: "Цена", text: s.newPrice, placeholder: "например, 120 TON", update: { text in
            update { var n = $0; n.newPrice = text; return n }
        }))
        result.append(wewAction(1003, 1, title: "Добавить", action: {
            let current = stateValue.with { $0 }
            let username = current.newUsername.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "@", with: "")
            guard !username.isEmpty else { return }
            settings.addFakeNftEntry(username: username, price: current.newPrice)
            settings.notifyProfileChanged()
            update { var n = $0; n.entries = settings.fakeNftEntries; n.newUsername = ""; n.newPrice = ""; return n }
        }))
        return result
    }
    let controller = wewListController(context: context, title: "NFT-юзернеймы", entries: entries)
    controllerRef = controller
    return controller
}

// MARK: - Rating

private struct WewRatingState: Equatable {
    var enabled: Bool
    var level: String
    var points: String
}

private func wewRatingController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let initial = WewRatingState(enabled: settings.fakeRatingEnabled, level: String(settings.fakeRatingLevel), points: wewNumberText(settings.fakeRatingStars))
    let state = ValuePromise<WewRatingState>(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let update: ((WewRatingState) -> WewRatingState) -> Void = { f in
        state.set(stateValue.modify(f))
    }

    let entries = state.get() |> map { s -> [WewEntry] in
        var result: [WewEntry] = [
            wewSwitch(0, 0, icon: PresentationResourcesSettings.stats, title: "Показывать рейтинг", value: s.enabled, update: { value in
                settings.fakeRatingEnabled = value
                settings.notifyProfileChanged()
                update { var n = $0; n.enabled = value; return n }
            })
        ]
        if s.enabled {
            result.append(wewHeader(10, 1, "ПАРАМЕТРЫ РЕЙТИНГА"))
            result.append(wewInput(11, 1, title: "Уровень", text: s.level, placeholder: "1", number: true, update: { text in
                settings.fakeRatingLevel = Int(text) ?? 1
                settings.notifyProfileChanged()
                update { var n = $0; n.level = text; return n }
            }))
            result.append(wewInput(12, 1, title: "Очки", text: s.points, placeholder: "0", number: true, update: { text in
                settings.fakeRatingStars = Int(text) ?? 0
                settings.notifyProfileChanged()
                update { var n = $0; n.points = text; return n }
            }))
        }
        return result
    }
    return wewListController(context: context, title: "Рейтинг", entries: entries)
}

// MARK: - Balance (Stars)

private struct WewBalanceState: Equatable {
    var enabled: Bool
    var stars: String
}

private func wewBalanceController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let initial = WewBalanceState(enabled: settings.fakeBalanceEnabled, stars: wewNumberText(settings.fakeBalanceStars))
    let state = ValuePromise<WewBalanceState>(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let update: ((WewBalanceState) -> WewBalanceState) -> Void = { f in
        state.set(stateValue.modify(f))
    }

    let entries = state.get() |> map { s -> [WewEntry] in
        var result: [WewEntry] = [
            wewSwitch(0, 0, icon: PresentationResourcesSettings.stars, title: "Свой баланс", value: s.enabled, update: { value in
                settings.fakeBalanceEnabled = value
                wewApplyStarsDelta(context: context, settings: settings)
                settings.notifyProfileChanged()
                update { var n = $0; n.enabled = value; return n }
            })
        ]
        if s.enabled {
            result.append(wewHeader(10, 1, "БАЛАНС ЗВЁЗД"))
            result.append(wewInput(11, 1, title: "Звёзды", text: s.stars, placeholder: "0", number: true, update: { text in
                settings.fakeBalanceStars = Int(text) ?? 0
                wewApplyStarsDelta(context: context, settings: settings)
                settings.notifyProfileChanged()
                update { var n = $0; n.stars = text; return n }
            }))
        }
        return result
    }
    return wewListController(context: context, title: "Баланс", entries: entries)
}

// MARK: - Gifts

private struct WewGiftsState: Equatable {
    var rows: [WewFakeGiftRow]
    var icons: [Int64: UIImage]
}

private func wewGiftsController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let initialData = wewFakeGiftRows()
    let initial = WewGiftsState(rows: initialData.rows, icons: [:])
    let state = ValuePromise<WewGiftsState>(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let update: ((WewGiftsState) -> WewGiftsState) -> Void = { f in
        state.set(stateValue.modify(f))
    }

    var controllerRef: ViewController?
    var requestedIcons = Set<Int64>()
    let disposables = DisposableSet()

    // Renders the first frame of each gift's animation into a small square tile.
    let loadIcons: ([Int64: TelegramMediaFile]) -> Void = { files in
        for (id, file) in files where !requestedIcons.contains(id) {
            requestedIcons.insert(id)
            let disposable = (reactionStaticImage(context: context, animation: file, pixelSize: CGSize(width: 96.0, height: 96.0), queue: sharedReactionStaticImage)
            |> deliverOnMainQueue).start(next: { data in
                guard data.isComplete, let raw = try? Data(contentsOf: URL(fileURLWithPath: data.path)), let image = UIImage(data: raw), let tile = wewGiftTile(image) else {
                    return
                }
                update { var n = $0; n.icons[id] = tile; return n }
            })
            disposables.add(disposable)
        }
    }

    let refresh: () -> Void = {
        let data = wewFakeGiftRows()
        update { var n = $0; n.rows = data.rows; return n }
        loadIcons(data.files)
        settings.notifyProfileChanged()
    }

    let entries = state.get() |> map { s -> [WewEntry] in
        var result: [WewEntry] = [
            wewAction(0, 0, title: "Добавить подарок", action: {
                let picker = wewpagramGiftPickerController(context: context) { picked in
                    if wewSaveFakeGift(picked) {
                        refresh()
                    }
                }
                (controllerRef as? ItemListController)?.push(picker)
            })
        ]
        if !s.rows.isEmpty {
            result.append(wewHeader(10, 1, "ДОБАВЛЕННЫЕ · \(s.rows.count)"))
            for (index, row) in s.rows.enumerated() {
                let icon = s.icons[row.id]
                result.append(wewRow(100 + index, 1, icon: icon, title: row.title, label: row.label, action: {
                    wewConfirm(context: context, controller: controllerRef, text: "Удалить «\(row.title)» из профиля?", confirmTitle: "Удалить", handler: {
                        settings.removeFakeGift(id: row.id)
                        refresh()
                    })
                }))
            }
            result.append(wewAction(100000, 2, title: "Удалить все подарки", destructive: true, action: {
                wewConfirm(context: context, controller: controllerRef, text: "Удалить все добавленные подарки?", confirmTitle: "Удалить все", handler: {
                    settings.removeAllFakeGifts()
                    refresh()
                })
            }))
        }
        return result
    }

    let controller = wewListController(context: context, title: "Подарки", entries: entries)
    controllerRef = controller
    loadIcons(initialData.files)
    return controller
}

// MARK: - Profile menu

public func wewpagramFakeIdentityController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    var controllerRef: ViewController?

    let push: (ViewController) -> Void = { c in
        (controllerRef as? ItemListController)?.push(c)
    }

    let entries = combineLatest(queue: .mainQueue(), settings.profileRevision.get(), settings.fakeGiftsRevision.get())
    |> map { _, _ -> [WewEntry] in
        let phone = settings.fakePhoneNumber ?? ""
        let nftCount = settings.fakeNftEntries.count
        let ratingLabel = settings.fakeRatingEnabled ? "Ур. \(settings.fakeRatingLevel)" : "Выкл"
        let balanceLabel = settings.fakeBalanceEnabled ? "\(settings.fakeBalanceStars) ★" : "Выкл"
        let giftCount = settings.fakeGiftRecords.count

        return [
            wewRow(0, 0, icon: PresentationResourcesSettings.changePhoneNumber, title: "Номер телефона", label: phone, action: { push(wewPhoneController(context: context)) }),
            wewRow(1, 0, icon: PresentationResourcesSettings.ton, title: "NFT-юзернеймы", label: nftCount == 0 ? "" : "\(nftCount)", action: { push(wewNftController(context: context)) }),
            wewRow(10, 1, icon: PresentationResourcesSettings.stats, title: "Рейтинг", label: ratingLabel, action: { push(wewRatingController(context: context)) }),
            wewRow(11, 1, icon: PresentationResourcesSettings.stars, title: "Баланс", label: balanceLabel, action: { push(wewBalanceController(context: context)) }),
            wewRow(20, 2, icon: PresentationResourcesSettings.premiumGift, title: "Подарки", label: giftCount == 0 ? "" : "\(giftCount)", action: { push(wewGiftsController(context: context)) })
        ]
    }

    let controller = wewListController(context: context, title: "Профиль", entries: entries)
    controllerRef = controller
    return controller
}
