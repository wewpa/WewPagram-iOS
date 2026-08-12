import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class WewPagramGiftPickerEntry: ItemListNodeEntry {
    let index: Int
    let title: String
    let priceText: String
    let action: () -> Void

    init(index: Int, title: String, priceText: String, action: @escaping () -> Void) {
        self.index = index
        self.title = title
        self.priceText = priceText
        self.action = action
    }

    var section: ItemListSectionId { return 0 }
    var stableId: Int { return self.index }

    static func ==(lhs: WewPagramGiftPickerEntry, rhs: WewPagramGiftPickerEntry) -> Bool {
        return lhs.index == rhs.index && lhs.title == rhs.title && lhs.priceText == rhs.priceText
    }

    static func <(lhs: WewPagramGiftPickerEntry, rhs: WewPagramGiftPickerEntry) -> Bool {
        return lhs.index < rhs.index
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        return ItemListDisclosureItem(presentationData: presentationData, title: self.title, label: self.priceText, sectionId: self.section, style: .blocks, action: { [action = self.action] in
            action()
        })
    }
}

// Pushes a simple list of real gifts from the catalog; tapping one calls
// onPicked with the chosen gift so the caller can store it as a fake entry.
public func wewpagramGiftPickerController(context: AccountContext, onPicked: @escaping (StarGift) -> Void) -> ViewController {
    // Keeps the latest emitted catalog snapshot around so tap handlers (built
    // fresh on every signal emission) can safely index into a stable array.
    let latestGifts = Atomic<[StarGift]>(value: [])
    var dismissImpl: (() -> Void)?

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        context.engine.payments.cachedStarGifts() |> map { $0 ?? [] }
    )
    |> map { presentationData, gifts -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let _ = latestGifts.swap(gifts)

        var entries: [WewPagramGiftPickerEntry] = []
        for (index, gift) in gifts.enumerated() {
            var title = "Подарок #\(index + 1)"
            var priceText = ""
            if case let .generic(g) = gift {
                if let t = g.title, !t.isEmpty { title = t }
                priceText = "\(g.price) ★"
            } else if case .unique = gift {
                title = "Уникальный подарок #\(index + 1)"
            }
            entries.append(WewPagramGiftPickerEntry(index: index, title: title, priceText: priceText, action: {
                let current = latestGifts.with { $0 }
                guard current.indices.contains(index) else { return }
                let picked = current[index]
                dismissImpl?()
                wewFindUpgradedVariant(context: context, of: picked) { resolved in
                    onPicked(resolved)
                }
            }))
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Выбери подарок"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: entries.isEmpty ? ItemListTextEmptyStateItem(text: "Загружаю каталог подарков…") : nil)

        return (controllerState, (listState, ArgumentsPlaceholder()))
    }

    let controller = ItemListController(context: context, state: signal)
    dismissImpl = { [weak controller] in
        controller?.dismiss()
    }
    return controller
}

// ItemListController requires a non-nil "arguments" payload even when the
// entries close over their own actions directly (as above) and don't need it.
private struct ArgumentsPlaceholder {}

// Real gift IDs only make sense for .generic entries (catalog items) —
// unique gifts are already someone's specific instance. When the picked
// gift is generic, check if it has any active resale listings (real,
// already-upgraded/NFT instances of the same gift type) and use one of
// those instead — a nicer-looking "upgraded" result when available.
// Falls back to the plain picked gift if there's nothing on resale, or if
// the pick was already unique.
private func wewFindUpgradedVariant(context: AccountContext, of picked: StarGift, completion: @escaping (StarGift) -> Void) {
    guard case let .generic(g) = picked else {
        completion(picked)
        return
    }
    let resaleContext = ResaleGiftsContext(account: context.account, giftId: g.id, forCrafting: false)
    var didComplete = false
    let finish: (StarGift) -> Void = { result in
        if !didComplete {
            didComplete = true
            completion(result)
        }
    }
    let disposable = MetaDisposable()
    disposable.set((resaleContext.state
    |> filter { $0.dataState != .loading }
    |> take(1)
    |> deliverOnMainQueue).start(next: { state in
        if let upgraded = state.gifts.randomElement() {
            finish(upgraded)
        } else {
            finish(picked)
        }
    }))
    // Safety net: if the resale signal never fires a non-loading state for
    // some reason, don't leave the user stuck — fall back after a short wait.
    Queue.mainQueue().after(4.0) {
        finish(picked)
        disposable.dispose()
        withExtendedLifetime(resaleContext) {}
    }
}
