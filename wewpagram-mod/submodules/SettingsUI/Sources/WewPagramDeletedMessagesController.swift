import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// What gets kept when the other side deletes a message.
private enum DeletedMessagesToggle: Int, CaseIterable {
    case saveText
    case saveMedia
    case saveAudio
    case saveVoiceNotes

    var title: String {
        switch self {
        case .saveText:       return "Сообщения"
        case .saveMedia:      return "Фото, видео и файлы"
        case .saveAudio:      return "Аудио"
        case .saveVoiceNotes: return "Голосовые"
        }
    }

    func read(from settings: WewPagramSettings) -> Bool {
        switch self {
        case .saveText:       return settings.deletedMessagesSaveText
        case .saveMedia:      return settings.deletedMessagesSaveMedia
        case .saveAudio:      return settings.deletedMessagesSaveAudio
        case .saveVoiceNotes: return settings.deletedMessagesSaveVoiceNotes
        }
    }

    func write(_ value: Bool, to settings: WewPagramSettings) {
        switch self {
        case .saveText:       settings.deletedMessagesSaveText = value
        case .saveMedia:      settings.deletedMessagesSaveMedia = value
        case .saveAudio:      settings.deletedMessagesSaveAudio = value
        case .saveVoiceNotes: settings.deletedMessagesSaveVoiceNotes = value
        }
    }
}

private struct DeletedMessagesState: Equatable {
    var enabled: Bool
    var values: [Bool]

    static func snapshot(from settings: WewPagramSettings) -> DeletedMessagesState {
        return DeletedMessagesState(
            enabled: settings.deletedMessagesEnabled,
            values: DeletedMessagesToggle.allCases.map { $0.read(from: settings) }
        )
    }
}

private final class DeletedMessagesArguments {
    let toggleEnabled: (Bool) -> Void
    let toggleType: (DeletedMessagesToggle, Bool) -> Void

    init(toggleEnabled: @escaping (Bool) -> Void, toggleType: @escaping (DeletedMessagesToggle, Bool) -> Void) {
        self.toggleEnabled = toggleEnabled
        self.toggleType = toggleType
    }
}

private enum DeletedMessagesEntry: ItemListNodeEntry {
    case master(Bool)
    case typesHeader
    case type(index: Int, toggle: DeletedMessagesToggle, value: Bool)

    var section: ItemListSectionId {
        switch self {
        case .master:
            return 0
        case .typesHeader, .type:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .master: return 0
        case .typesHeader: return 1
        case let .type(index, _, _): return 10 + index
        }
    }

    static func < (lhs: DeletedMessagesEntry, rhs: DeletedMessagesEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DeletedMessagesArguments
        switch self {
        case let .master(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Сохранять удалённые", value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.toggleEnabled(newValue)
            })
        case .typesHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "ЧТО СОХРАНЯТЬ", sectionId: self.section)
        case let .type(_, toggle, value):
            return ItemListSwitchItem(presentationData: presentationData, title: toggle.title, value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.toggleType(toggle, newValue)
            })
        }
    }
}

public func wewpagramDeletedMessagesController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let statePromise = ValuePromise<DeletedMessagesState>(DeletedMessagesState.snapshot(from: settings), ignoreRepeated: true)

    let arguments = DeletedMessagesArguments(
        toggleEnabled: { value in
            settings.deletedMessagesEnabled = value
            statePromise.set(DeletedMessagesState.snapshot(from: settings))
        },
        toggleType: { toggle, value in
            toggle.write(value, to: settings)
            statePromise.set(DeletedMessagesState.snapshot(from: settings))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [DeletedMessagesEntry] = [.master(state.enabled)]
        if state.enabled {
            entries.append(.typesHeader)
            for (index, toggle) in DeletedMessagesToggle.allCases.enumerated() {
                entries.append(.type(index: index, toggle: toggle, value: state.values[index]))
            }
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Удалённые сообщения"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
