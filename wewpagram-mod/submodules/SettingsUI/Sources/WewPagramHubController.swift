import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private final class WewPagramHubControllerArguments {
    let openGhostMode: () -> Void
    let openFakeIdentity: () -> Void
    let openDeletedMessages: () -> Void
    let exportSettings: () -> Void
    let importSettings: () -> Void
    let resetSettings: () -> Void

    init(
        openGhostMode: @escaping () -> Void,
        openFakeIdentity: @escaping () -> Void,
        openDeletedMessages: @escaping () -> Void,
        exportSettings: @escaping () -> Void,
        importSettings: @escaping () -> Void,
        resetSettings: @escaping () -> Void
    ) {
        self.openGhostMode = openGhostMode
        self.openFakeIdentity = openFakeIdentity
        self.openDeletedMessages = openDeletedMessages
        self.exportSettings = exportSettings
        self.importSettings = importSettings
        self.resetSettings = resetSettings
    }
}

private enum WewPagramHubSection: Int32 {
    case tools = 0
    case backup = 1
    case backupFooter = 2
    case reset = 3
    case resetFooter = 4
}

private enum WewPagramHubEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case ghostMode
        case fakeIdentity
        case deletedMessages
        case backupHeader
        case exportSettings
        case importSettings
        case backupFooter
        case resetHeader
        case resetSettings
        case resetFooter
    }

    case ghostMode
    case fakeIdentity
    case deletedMessages
    case backupHeader(String)
    case exportSettings
    case importSettings
    case backupFooter(String)
    case resetHeader(String)
    case resetSettings
    case resetFooter(String)

    var section: ItemListSectionId {
        switch self {
        case .ghostMode, .fakeIdentity, .deletedMessages:                return WewPagramHubSection.tools.rawValue
        case .backupHeader, .exportSettings, .importSettings:            return WewPagramHubSection.backup.rawValue
        case .backupFooter:                                              return WewPagramHubSection.backupFooter.rawValue
        case .resetHeader, .resetSettings:                               return WewPagramHubSection.reset.rawValue
        case .resetFooter:                                               return WewPagramHubSection.resetFooter.rawValue
        }
    }

    var stableId: StableId {
        switch self {
        case .ghostMode:        return .ghostMode
        case .fakeIdentity:     return .fakeIdentity
        case .deletedMessages:  return .deletedMessages
        case .backupHeader:     return .backupHeader
        case .exportSettings:   return .exportSettings
        case .importSettings:   return .importSettings
        case .backupFooter:     return .backupFooter
        case .resetHeader:      return .resetHeader
        case .resetSettings:    return .resetSettings
        case .resetFooter:      return .resetFooter
        }
    }

    private var sortIndex: Int {
        switch self {
        case .ghostMode:        return 0
        case .fakeIdentity:     return 1
        case .deletedMessages:  return 2
        case .backupHeader:     return 100
        case .exportSettings:   return 101
        case .importSettings:   return 102
        case .backupFooter:     return 103
        case .resetHeader:      return 200
        case .resetSettings:    return 201
        case .resetFooter:      return 202
        }
    }

    static func == (lhs: WewPagramHubEntry, rhs: WewPagramHubEntry) -> Bool {
        switch (lhs, rhs) {
        case (.ghostMode, .ghostMode),
             (.fakeIdentity, .fakeIdentity),
             (.deletedMessages, .deletedMessages),
             (.exportSettings, .exportSettings),
             (.importSettings, .importSettings),
             (.resetSettings, .resetSettings):
            return true
        case let (.backupHeader(a), .backupHeader(b)):     return a == b
        case let (.backupFooter(a), .backupFooter(b)):     return a == b
        case let (.resetHeader(a), .resetHeader(b)):       return a == b
        case let (.resetFooter(a), .resetFooter(b)):       return a == b
        default:
            return false
        }
    }

    static func < (lhs: WewPagramHubEntry, rhs: WewPagramHubEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramHubControllerArguments
        switch self {
        case .ghostMode:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Режим призрака", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openGhostMode()
            })
        case .fakeIdentity:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Профиль", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openFakeIdentity()
            })
        case .deletedMessages:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Удалённые сообщения", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openDeletedMessages()
            })
        case let .backupHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .exportSettings:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Скопировать настройки", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.exportSettings()
            })
        case .importSettings:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Вставить настройки", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.importSettings()
            })
        case let .backupFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .resetHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case .resetSettings:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Сбросить все настройки", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.resetSettings()
            })
        case let .resetFooter(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

// MARK: - Snapshot helpers

// Buffer-of-truth format for export/import: a compact JSON envelope with a
// version tag so future format changes can be detected explicitly instead
// of being smuggled in as extra keys.
private let snapshotEnvelopeVersion = 1
private let snapshotEnvelopeVersionKey = "version"
private let snapshotEnvelopeDataKey = "data"

private func encodeSnapshot(_ snapshot: [String: Any]) -> String? {
    let envelope: [String: Any] = [
        snapshotEnvelopeVersionKey: snapshotEnvelopeVersion,
        snapshotEnvelopeDataKey: snapshot,
    ]
    guard JSONSerialization.isValidJSONObject(envelope) else { return nil }
    do {
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

private func decodeSnapshot(_ text: String) -> [String: Any]? {
    guard let data = text.data(using: .utf8) else { return nil }
    guard let raw = try? JSONSerialization.jsonObject(with: data, options: []) else { return nil }
    // Accept both the versioned envelope and a bare dictionary — importing
    // a snapshot copied out of an earlier build should still work.
    if let envelope = raw as? [String: Any], let inner = envelope[snapshotEnvelopeDataKey] as? [String: Any] {
        return inner
    }
    if let bare = raw as? [String: Any] {
        return bare
    }
    return nil
}

public func wewpagramHubController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentAlertImpl: ((ViewController) -> Void)?

    let arguments = WewPagramHubControllerArguments(
        openGhostMode: {
            pushControllerImpl?(wewpagramGhostModeController(context: context))
        },
        openFakeIdentity: {
            pushControllerImpl?(wewpagramFakeIdentityController(context: context))
        },
        openDeletedMessages: {
            pushControllerImpl?(wewpagramDeletedMessagesController(context: context))
        },
        exportSettings: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let snapshot = WewPagramSettings.shared.exportSnapshot()
            let title: String
            let text: String
            if let encoded = encodeSnapshot(snapshot) {
                UIPasteboard.general.string = encoded
                title = "Настройки скопированы"
                text = "JSON с текущими настройками WewPagram отправлен в буфер обмена. Вставьте его куда угодно, чтобы сохранить резервную копию."
            } else {
                title = "Ошибка"
                text = "Не удалось сериализовать настройки. Попробуйте ещё раз."
            }
            let alert = textAlertController(
                context: context,
                updatedPresentationData: nil,
                title: title,
                text: text,
                actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
            )
            presentAlertImpl?(alert)
        },
        importSettings: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let clipboard = UIPasteboard.general.string ?? ""
            let trimmed = clipboard.trimmingCharacters(in: .whitespacesAndNewlines)

            let showAlert: (String, String) -> Void = { title, text in
                let alert = textAlertController(
                    context: context,
                    updatedPresentationData: nil,
                    title: title,
                    text: text,
                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                )
                presentAlertImpl?(alert)
            }

            guard !trimmed.isEmpty else {
                showAlert("Буфер пуст", "Скопируйте JSON с настройками WewPagram и повторите попытку.")
                return
            }
            guard let snapshot = decodeSnapshot(trimmed) else {
                showAlert("Неверный формат", "Не удалось прочитать содержимое буфера как настройки WewPagram. Убедитесь, что скопирован полный JSON.")
                return
            }

            let alert = textAlertController(
                context: context,
                updatedPresentationData: nil,
                title: "Импорт настроек",
                text: "Текущие настройки WewPagram будут заменены содержимым буфера обмена. Продолжить?",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .defaultAction, title: "Импортировать", action: {
                        let applied = WewPagramSettings.shared.importSnapshot(snapshot)
                        let title = applied ? "Готово" : "Ничего не применено"
                        let text = applied
                            ? "Настройки WewPagram обновлены из буфера обмена."
                            : "В снимке не оказалось ни одного знакомого ключа. Настройки не изменены."
                        showAlert(title, text)
                    })
                ]
            )
            presentAlertImpl?(alert)
        },
        resetSettings: {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let alert = textAlertController(
                context: context,
                updatedPresentationData: nil,
                title: "Сбросить настройки?",
                text: "Все переключатели «Режима призрака» будут выключены, поля фейкового профиля очищены. Действие нельзя отменить.",
                actions: [
                    TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                    TextAlertAction(type: .destructiveAction, title: "Сбросить", action: {
                        WewPagramSettings.shared.resetAll()
                        let done = textAlertController(
                            context: context,
                            updatedPresentationData: nil,
                            title: "Готово",
                            text: "Все настройки WewPagram сброшены.",
                            actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                        )
                        presentAlertImpl?(done)
                    })
                ]
            )
            presentAlertImpl?(alert)
        }
    )

    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [WewPagramHubEntry] = [
            .ghostMode,
            .fakeIdentity,
            .deletedMessages,
            .backupHeader("РЕЗЕРВНАЯ КОПИЯ"),
            .exportSettings,
            .importSettings,
            .backupFooter("Скопируйте JSON текущих настроек в буфер обмена или восстановите его на другом устройстве."),
            .resetHeader("СБРОС"),
            .resetSettings,
            .resetFooter("Возвращает все настройки WewPagram к значениям по умолчанию.")
        ]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("WewPagram"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        controller?.push(c)
    }
    presentAlertImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root))
    }
    return controller
}
