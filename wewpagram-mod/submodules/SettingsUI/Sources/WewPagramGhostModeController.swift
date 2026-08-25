import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// Privacy activity toggle with clean naming (no dashes, no descriptions)
private enum GhostToggle: Int, CaseIterable {
    case onlineStatus
    case typing
    case recordingVideo
    case uploadingVideo
    case voiceRecording
    case voiceUploading
    case uploadingPhoto
    case readReceipts

    var title: String {
        switch self {
        case .onlineStatus:    return "Онлайн"
        case .typing:          return "Набор текста"
        case .recordingVideo:  return "Запись видео"
        case .uploadingVideo:  return "Загрузка видео"
        case .voiceRecording:  return "Запись голоса"
        case .voiceUploading:  return "Загрузка голоса"
        case .uploadingPhoto:  return "Загрузка фото"
        case .readReceipts:    return "Отчёты о прочтении"
        }
    }

    func read(from settings: WewPagramSettings) -> Bool {
        switch self {
        case .onlineStatus:    return settings.disableOnlineStatus
        case .typing:          return settings.disableTyping
        case .recordingVideo:  return settings.disableRecordingVideo
        case .uploadingVideo:  return settings.disableUploadingVideo
        case .voiceRecording:  return settings.disableVoiceRecording
        case .voiceUploading:  return settings.disableVoiceUploading
        case .uploadingPhoto:  return settings.disableUploadingPhoto
        case .readReceipts:    return settings.disableReadReceipts
        }
    }

    func write(_ value: Bool, to settings: WewPagramSettings) {
        switch self {
        case .onlineStatus:    settings.disableOnlineStatus = value
        case .typing:          settings.disableTyping = value
        case .recordingVideo:  settings.disableRecordingVideo = value
        case .uploadingVideo:  settings.disableUploadingVideo = value
        case .voiceRecording:  settings.disableVoiceRecording = value
        case .voiceUploading:  settings.disableVoiceUploading = value
        case .uploadingPhoto:  settings.disableUploadingPhoto = value
        case .readReceipts:    settings.disableReadReceipts = value
        }
    }
}

// Deleted messages archiving toggles
private enum DeletedMessagesToggle: Int, CaseIterable {
    case saveText
    case saveMedia
    case saveAudio
    case saveVoiceNotes

    var title: String {
        switch self {
        case .saveText:       return "Сообщения"
        case .saveMedia:      return "Медиа"
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

private struct GhostState: Equatable {
    var ghostValues: [Bool]
    var deletedMessagesEnabled: Bool
    var deletedMessagesValues: [Bool]

    static func snapshot(from settings: WewPagramSettings) -> GhostState {
        return GhostState(
            ghostValues: GhostToggle.allCases.map { $0.read(from: settings) },
            deletedMessagesEnabled: settings.deletedMessagesEnabled,
            deletedMessagesValues: DeletedMessagesToggle.allCases.map { $0.read(from: settings) }
        )
    }

    var allGhostOn: Bool { return !self.ghostValues.contains(false) }
}

private final class WewPagramGhostModeControllerArguments {
    let toggleGhost: (GhostToggle, Bool) -> Void
    let toggleAllGhost: (Bool) -> Void
    let toggleDeletedMessages: (Bool) -> Void
    let toggleDeletedMessageType: (DeletedMessagesToggle, Bool) -> Void

    init(
        toggleGhost: @escaping (GhostToggle, Bool) -> Void,
        toggleAllGhost: @escaping (Bool) -> Void,
        toggleDeletedMessages: @escaping (Bool) -> Void,
        toggleDeletedMessageType: @escaping (DeletedMessagesToggle, Bool) -> Void
    ) {
        self.toggleGhost = toggleGhost
        self.toggleAllGhost = toggleAllGhost
        self.toggleDeletedMessages = toggleDeletedMessages
        self.toggleDeletedMessageType = toggleDeletedMessageType
    }
}

private enum WewPagramGhostModeEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case masterHeader
        case master
        case ghostSectionHeader
        case ghostItem(Int)
        case deletedMessagesHeader
        case deletedMessagesToggle
        case deletedMessageItem(Int)
    }

    case masterHeader(String)
    case master(value: Bool)
    case ghostSectionHeader(String)
    case ghostItem(index: Int, toggle: GhostToggle, value: Bool)
    case deletedMessagesHeader(String)
    case deletedMessagesToggle(value: Bool)
    case deletedMessageItem(index: Int, toggle: DeletedMessagesToggle, value: Bool)

    var section: ItemListSectionId {
        switch self {
        case .masterHeader, .master:
            return 0
        case .ghostSectionHeader, .ghostItem:
            return 1
        case .deletedMessagesHeader, .deletedMessagesToggle, .deletedMessageItem:
            return 2
        }
    }

    var stableId: StableId {
        switch self {
        case .masterHeader:                          return .masterHeader
        case .master:                                return .master
        case .ghostSectionHeader:                    return .ghostSectionHeader
        case let .ghostItem(index, _, _):            return .ghostItem(index)
        case .deletedMessagesHeader:                 return .deletedMessagesHeader
        case .deletedMessagesToggle:                 return .deletedMessagesToggle
        case let .deletedMessageItem(index, _, _):   return .deletedMessageItem(index)
        }
    }

    private var sortIndex: Int {
        switch self {
        case .masterHeader:                          return 0
        case .master:                                return 1
        case .ghostSectionHeader:                    return 2
        case let .ghostItem(index, _, _):            return 100 + index
        case .deletedMessagesHeader:                 return 200
        case .deletedMessagesToggle:                 return 201
        case let .deletedMessageItem(index, _, _):   return 202 + index
        }
    }

    static func == (lhs: WewPagramGhostModeEntry, rhs: WewPagramGhostModeEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.masterHeader(a), .masterHeader(b)):                  return a == b
        case let (.master(a), .master(b)):                              return a == b
        case let (.ghostSectionHeader(a), .ghostSectionHeader(b)):      return a == b
        case let (.ghostItem(i1, t1, v1), .ghostItem(i2, t2, v2)):      return i1 == i2 && t1 == t2 && v1 == v2
        case let (.deletedMessagesHeader(a), .deletedMessagesHeader(b)):return a == b
        case let (.deletedMessagesToggle(a), .deletedMessagesToggle(b)):return a == b
        case let (.deletedMessageItem(i1, t1, v1), .deletedMessageItem(i2, t2, v2)): return i1 == i2 && t1 == t2 && v1 == v2
        default:                                                        return false
        }
    }

    static func < (lhs: WewPagramGhostModeEntry, rhs: WewPagramGhostModeEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramGhostModeControllerArguments
        switch self {
        case let .masterHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .master(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "Режим призрака",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in arguments.toggleAllGhost(newValue) }
            )

        case let .ghostSectionHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .ghostItem(_, toggle, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: toggle.title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in arguments.toggleGhost(toggle, newValue) }
            )

        case let .deletedMessagesHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .deletedMessagesToggle(value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: "Сохранять удалённые",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in arguments.toggleDeletedMessages(newValue) }
            )

        case let .deletedMessageItem(_, toggle, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: toggle.title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in arguments.toggleDeletedMessageType(toggle, newValue) }
            )
        }
    }
}

public func wewpagramGhostModeController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let statePromise = ValuePromise<GhostState>(GhostState.snapshot(from: settings), ignoreRepeated: true)

    let arguments = WewPagramGhostModeControllerArguments(
        toggleGhost: { toggle, value in
            toggle.write(value, to: settings)
            statePromise.set(GhostState.snapshot(from: settings))
        },
        toggleAllGhost: { value in
            settings.isGhostModeEnabled = value
            statePromise.set(GhostState.snapshot(from: settings))
        },
        toggleDeletedMessages: { value in
            settings.deletedMessagesEnabled = value
            statePromise.set(GhostState.snapshot(from: settings))
        },
        toggleDeletedMessageType: { toggle, value in
            toggle.write(value, to: settings)
            statePromise.set(GhostState.snapshot(from: settings))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [WewPagramGhostModeEntry] = []

        // Master toggle section
        entries.append(.masterHeader("ГЛАВНЫЙ ПЕРЕКЛЮЧАТЕЛЬ"))
        entries.append(.master(value: state.allGhostOn))

        // Ghost mode toggles (privacy hiding)
        entries.append(.ghostSectionHeader("СКРЫВАТЬ"))
        for (index, toggle) in GhostToggle.allCases.enumerated() {
            entries.append(.ghostItem(index: index, toggle: toggle, value: state.ghostValues[index]))
        }

        // Deleted messages archiving section
        entries.append(.deletedMessagesHeader("УДАЛЁННЫЕ СООБЩЕНИЯ"))
        entries.append(.deletedMessagesToggle(value: state.deletedMessagesEnabled))
        if state.deletedMessagesEnabled {
            for (index, toggle) in DeletedMessagesToggle.allCases.enumerated() {
                entries.append(.deletedMessageItem(index: index, toggle: toggle, value: state.deletedMessagesValues[index]))
            }
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Режим призрака"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    return ItemListController(context: context, state: signal)
}
