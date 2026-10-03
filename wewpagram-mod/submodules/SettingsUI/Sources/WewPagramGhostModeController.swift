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

private struct GhostState: Equatable {
    var ghostValues: [Bool]

    static func snapshot(from settings: WewPagramSettings) -> GhostState {
        return GhostState(ghostValues: GhostToggle.allCases.map { $0.read(from: settings) })
    }

    var allGhostOn: Bool { return !self.ghostValues.contains(false) }
}

private final class WewPagramGhostModeControllerArguments {
    let toggleGhost: (GhostToggle, Bool) -> Void
    let toggleAllGhost: (Bool) -> Void

    init(toggleGhost: @escaping (GhostToggle, Bool) -> Void, toggleAllGhost: @escaping (Bool) -> Void) {
        self.toggleGhost = toggleGhost
        self.toggleAllGhost = toggleAllGhost
    }
}

private enum WewPagramGhostModeEntry: ItemListNodeEntry {
    case master(value: Bool)
    case itemsHeader
    case ghostItem(index: Int, toggle: GhostToggle, value: Bool)

    var section: ItemListSectionId {
        switch self {
        case .master:
            return 0
        case .itemsHeader, .ghostItem:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .master: return 0
        case .itemsHeader: return 1
        case let .ghostItem(index, _, _): return 10 + index
        }
    }

    static func < (lhs: WewPagramGhostModeEntry, rhs: WewPagramGhostModeEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramGhostModeControllerArguments
        switch self {
        case let .master(value):
            return ItemListSwitchItem(presentationData: presentationData, title: "Режим призрака", value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.toggleAllGhost(newValue)
            })
        case .itemsHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СКРЫВАТЬ", sectionId: self.section)
        case let .ghostItem(_, toggle, value):
            return ItemListSwitchItem(presentationData: presentationData, title: toggle.title, value: value, sectionId: self.section, style: .blocks, updated: { newValue in
                arguments.toggleGhost(toggle, newValue)
            })
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
        }
    )

    let signal = combineLatest(queue: .mainQueue(),
        context.sharedContext.presentationData,
        statePromise.get()
    )
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [WewPagramGhostModeEntry] = [.master(value: state.allGhostOn), .itemsHeader]
        for (index, toggle) in GhostToggle.allCases.enumerated() {
            entries.append(.ghostItem(index: index, toggle: toggle, value: state.ghostValues[index]))
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
