import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// One row per privacy activity. Each row is an independent toggle backed by
// a dedicated key in `WewPagramSettings`, so the user can hide only what they
// want to hide.
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
        case .onlineStatus:    return "Онлайн-статус"
        case .typing:          return "Индикатор набора"
        case .recordingVideo:  return "Запись видеосообщения"
        case .uploadingVideo:  return "Отправка видео"
        case .voiceRecording:  return "Запись голосового"
        case .voiceUploading:  return "Отправка голосового"
        case .uploadingPhoto:  return "Отправка фото"
        case .readReceipts:    return "Отчёты о прочтении"
        }
    }

    var subtitle: String {
        switch self {
        case .onlineStatus:
            return "Всегда показывать себя офлайн — другие не увидят, что вы в сети."
        case .typing:
            return "Скрывать «печатает…» в чатах, где вы набираете сообщение."
        case .recordingVideo:
            return "Скрывать статус «записывает видеосообщение» при записи кружочка."
        case .uploadingVideo:
            return "Скрывать статус «отправляет видео», пока идёт загрузка."
        case .voiceRecording:
            return "Скрывать «записывает голосовое сообщение» во время записи."
        case .voiceUploading:
            return "Скрывать «отправляет голосовое», пока идёт загрузка."
        case .uploadingPhoto:
            return "Скрывать «отправляет фото», пока идёт загрузка изображения."
        case .readReceipts:
            return "Не отправлять серверу отметку о прочтении — синие галочки для собеседника не появятся."
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

private struct GhostState: Equatable {
    var values: [Bool]

    static func snapshot(from settings: WewPagramSettings) -> GhostState {
        return GhostState(values: GhostToggle.allCases.map { $0.read(from: settings) })
    }

    var allOn: Bool { return !self.values.contains(false) }
}

private final class WewPagramGhostModeControllerArguments {
    let toggle: (GhostToggle, Bool) -> Void
    let toggleAll: (Bool) -> Void

    init(toggle: @escaping (GhostToggle, Bool) -> Void, toggleAll: @escaping (Bool) -> Void) {
        self.toggle = toggle
        self.toggleAll = toggleAll
    }
}

private enum WewPagramGhostModeEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case masterHeader
        case master
        case sectionHeader
        case item(Int)
        case footer
    }

    case masterHeader(String)
    case master(value: Bool)
    case sectionHeader(String)
    case item(index: Int, toggle: GhostToggle, value: Bool)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .masterHeader, .master:
            return 0
        case .sectionHeader, .item, .footer:
            return 1
        }
    }

    var stableId: StableId {
        switch self {
        case .masterHeader:                return .masterHeader
        case .master:                      return .master
        case .sectionHeader:               return .sectionHeader
        case let .item(index, _, _):       return .item(index)
        case .footer:                      return .footer
        }
    }

    private var sortIndex: Int {
        switch self {
        case .masterHeader:                return 0
        case .master:                      return 1
        case .sectionHeader:               return 3
        case let .item(index, _, _):       return 100 + index
        case .footer:                      return 10_000
        }
    }

    static func == (lhs: WewPagramGhostModeEntry, rhs: WewPagramGhostModeEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.masterHeader(a), .masterHeader(b)):     return a == b
        case let (.master(a), .master(b)):                 return a == b
        case let (.sectionHeader(a), .sectionHeader(b)):   return a == b
        case let (.item(i1, t1, v1), .item(i2, t2, v2)):   return i1 == i2 && t1 == t2 && v1 == v2
        case let (.footer(a), .footer(b)):                 return a == b
        default:                                           return false
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
                text: "Включает или выключает все переключатели ниже.",
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in arguments.toggleAll(newValue) }
            )

        case let .sectionHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .item(_, toggle, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                title: toggle.title,
                text: toggle.subtitle,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { newValue in arguments.toggle(toggle, newValue) }
            )

        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func wewpagramGhostModeController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let statePromise = ValuePromise<GhostState>(GhostState.snapshot(from: settings), ignoreRepeated: true)

    let arguments = WewPagramGhostModeControllerArguments(
        toggle: { toggle, value in
            toggle.write(value, to: settings)
            statePromise.set(GhostState.snapshot(from: settings))
        },
        toggleAll: { value in
            settings.isGhostModeEnabled = value
            statePromise.set(GhostState.snapshot(from: settings))
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [WewPagramGhostModeEntry] = []

        entries.append(.masterHeader("ГЛАВНЫЙ ПЕРЕКЛЮЧАТЕЛЬ"))
        entries.append(.master(value: state.allOn))

        entries.append(.sectionHeader("СКРЫВАТЬ ОТ ДРУГИХ"))
        for (index, toggle) in GhostToggle.allCases.enumerated() {
            entries.append(.item(index: index, toggle: toggle, value: state.values[index]))
        }
        entries.append(.footer("Настройки применяются локально. Отключённые события просто не отправляются на сервер — их не видит ни один собеседник."))

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
