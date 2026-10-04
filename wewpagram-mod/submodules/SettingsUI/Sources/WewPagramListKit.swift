import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// MARK: - Shared list helpers (used by every WewPagram screen)

// One generic list entry that carries its own builder. `signature` describes
// everything that affects how the row looks, so the list only re-renders a
// row when its content really changed.
final class WewEntry: ItemListNodeEntry {
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

struct WewNoArguments {}

func wewListController(context: AccountContext, title: String, entries: Signal<[WewEntry], NoError>) -> ItemListController {
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

func wewHeader(_ order: Int, _ section: ItemListSectionId, _ text: String) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "h|" + text, build: { pd in
        return ItemListSectionHeaderItem(presentationData: pd, text: text, sectionId: section)
    })
}

func wewInput(_ order: Int, _ section: ItemListSectionId, title: String, text: String, placeholder: String, number: Bool = false, update: @escaping (String) -> Void) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "i|\(title)|\(text)|\(placeholder)", build: { pd in
        let type: ItemListSingleLineInputItemType = number ? .number : .regular(capitalization: false, autocorrection: false)
        return ItemListSingleLineInputItem(presentationData: pd, title: NSAttributedString(string: title), text: text, placeholder: placeholder, type: type, sectionId: section, textUpdated: { update($0) }, action: {})
    })
}

func wewSwitch(_ order: Int, _ section: ItemListSectionId, icon: UIImage?, title: String, subtitle: String? = nil, value: Bool, update: @escaping (Bool) -> Void) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "s|\(title)|\(subtitle ?? "")|\(value)", build: { pd in
        return ItemListSwitchItem(presentationData: pd, icon: icon, title: title, text: subtitle, value: value, maximumNumberOfLines: 3, sectionId: section, style: .blocks, updated: { update($0) })
    })
}

func wewAction(_ order: Int, _ section: ItemListSectionId, title: String, destructive: Bool = false, action: @escaping () -> Void) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "a|\(title)", build: { pd in
        return ItemListActionItem(presentationData: pd, title: title, kind: destructive ? .destructive : .generic, alignment: .natural, sectionId: section, style: .blocks, action: action)
    })
}

func wewRow(_ order: Int, _ section: ItemListSectionId, icon: UIImage?, title: String, label: String, action: (() -> Void)?) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "r|\(title)|\(label)|\(icon != nil)", build: { pd in
        return ItemListDisclosureItem(presentationData: pd, icon: icon, title: title, label: label, sectionId: section, style: .blocks, disclosureStyle: action == nil ? .none : .arrow, action: action)
    })
}

func wewConfirm(context: AccountContext, controller: ViewController?, text: String, confirmTitle: String, handler: @escaping () -> Void) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: text, actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .destructiveAction, title: confirmTitle, action: handler)
    ])
    controller?.present(alert, in: .window(.root))
}


// Fires on every change of any stored setting (UserDefaults), so menus can
// refresh their labels when the user comes back from a sub-screen.
func wewDefaultsChanged() -> Signal<Void, NoError> {
    return Signal { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            subscriber.putNext(Void())
        }
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

func wewText(_ order: Int, _ section: ItemListSectionId, text: String) -> WewEntry {
    return WewEntry(order: order, section: section, signature: "t|" + text, build: { pd in
        return ItemListTextItem(presentationData: pd, text: .plain(text), sectionId: section)
    })
}

func wewShowAlert(context: AccountContext, controller: ViewController?, text: String) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: text, actions: [
        TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
    ])
    controller?.present(alert, in: .window(.root))
}
