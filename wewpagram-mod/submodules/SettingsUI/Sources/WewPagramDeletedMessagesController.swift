import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private struct WewDeletedMessageEntry: ItemListNodeEntry {
    let index: Int
    let record: WewPagramSettings.DeletedMessageRecord

    var section: ItemListSectionId { return 0 }
    var stableId: Int { return self.index }

    static func ==(lhs: WewDeletedMessageEntry, rhs: WewDeletedMessageEntry) -> Bool {
        return lhs.index == rhs.index && lhs.record.text == rhs.record.text && lhs.record.deletedAt == rhs.record.deletedAt
    }

    static func <(lhs: WewDeletedMessageEntry, rhs: WewDeletedMessageEntry) -> Bool {
        // Newest deletion first.
        return lhs.record.deletedAt > rhs.record.deletedAt
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let deletedDate = Date(timeIntervalSince1970: TimeInterval(self.record.deletedAt))
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM HH:mm"
        let dateText = formatter.string(from: deletedDate)
        let authorText = self.record.authorName ?? "Неизвестно"
        let title = "\(authorText) — удалено \(dateText)"
        return ItemListTextWithLabelItem(presentationData: presentationData, label: title, text: self.record.text, style: .blocks, textColor: .primary, enabledEntityTypes: [], multiline: true, sectionId: self.section, action: nil)
    }
}

public func wewpagramDeletedMessagesController(context: AccountContext, filterPeerId: EnginePeer.Id? = nil) -> ViewController {
    let updatePromise = ValuePromise<Int>(0, ignoreRepeated: false)
    var presentControllerImpl: ((ViewController) -> Void)?

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        updatePromise.get()
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var records = WewPagramSettings.shared.deletedMessages()
        if let filterPeerId {
            records = records.filter { $0.peerId == filterPeerId.toInt64() }
        }
        var entries: [WewDeletedMessageEntry] = []
        for (index, record) in records.enumerated() {
            entries.append(WewDeletedMessageEntry(index: index, record: record))
        }

        let rightButton = ItemListNavigationButton(content: .text("Очистить"), style: .regular, enabled: !entries.isEmpty, action: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: "Очистить весь архив удалённых сообщений?", actions: [
                TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: "Очистить", action: {
                    WewPagramSettings.shared.clearDeletedMessages()
                    updatePromise.set(0)
                })
            ])
            presentControllerImpl?(alert)
        })

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Удалённые сообщения"), leftNavigationButton: nil, rightNavigationButton: rightButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, emptyStateItem: entries.isEmpty ? ItemListTextEmptyStateItem(text: "Пока ничего не удаляли (или ты ещё не открывал ни один чат после установки).") : nil)

        return (controllerState, (listState, EmptyItemListArguments()))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}

private struct EmptyItemListArguments {}
