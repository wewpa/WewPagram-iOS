import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

private func wewNormalizedServerURL(_ raw: String) -> String {
    var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    while value.hasSuffix("/") {
        value.removeLast()
    }
    return value
}

private struct WewUserbotStatus: Equatable {
    var title: String
    var saved: String
}

// Asks the server what the userbot is doing (no UI of its own - just a status row).
private func wewFetchUserbotStatus(url: String, key: String, completion: @escaping (WewUserbotStatus) -> Void) {
    let base = wewNormalizedServerURL(url)
    guard !base.isEmpty, !key.isEmpty else {
        completion(WewUserbotStatus(title: "Не настроен", saved: ""))
        return
    }
    guard let endpoint = URL(string: base + "/api/status"), endpoint.scheme == "https" else {
        completion(WewUserbotStatus(title: "Нужен адрес https://…", saved: ""))
        return
    }
    var request = URLRequest(url: endpoint, timeoutInterval: 10.0)
    request.setValue(key, forHTTPHeaderField: "X-Api-Key")
    URLSession.shared.dataTask(with: request) { data, response, error in
        var result = WewUserbotStatus(title: "Нет соединения", saved: "")
        if error == nil, let http = response as? HTTPURLResponse {
            if http.statusCode == 401 {
                result.title = "Неверный ключ"
            } else if http.statusCode == 200, let data = data, let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                let online = json["online"] as? Bool ?? false
                let lastSeen = json["last_seen"] as? Double
                if online {
                    result.title = "Онлайн"
                } else if let lastSeen = lastSeen {
                    let minutes = max(1, Int((Date().timeIntervalSince1970 - lastSeen) / 60.0))
                    if minutes < 60 {
                        result.title = "Не в сети · \(minutes) мин"
                    } else if minutes < 60 * 24 {
                        result.title = "Не в сети · \(minutes / 60) ч"
                    } else {
                        result.title = "Не в сети · \(minutes / (60 * 24)) дн"
                    }
                } else {
                    result.title = "Юзербот не запущен"
                }
                let messages = json["messages"] as? Int ?? 0
                let deleted = json["deleted"] as? Int ?? 0
                result.saved = "\(messages) / \(deleted)"
            } else {
                result.title = "Ошибка сервера (\(http.statusCode))"
            }
        }
        DispatchQueue.main.async {
            completion(result)
        }
    }.resume()
}

private struct WewUserbotState: Equatable {
    var url: String
    var key: String
    var status: WewUserbotStatus
}

private final class WewUserbotArguments {
    let updateURL: (String) -> Void
    let updateKey: (String) -> Void
    let openPanel: () -> Void

    init(updateURL: @escaping (String) -> Void, updateKey: @escaping (String) -> Void, openPanel: @escaping () -> Void) {
        self.updateURL = updateURL
        self.updateKey = updateKey
        self.openPanel = openPanel
    }
}

private enum WewUserbotEntry: ItemListNodeEntry {
    case urlHeader
    case url(String)
    case key(String)
    case status(String)
    case saved(String)
    case panel

    var section: ItemListSectionId {
        switch self {
        case .urlHeader, .url, .key:
            return 0
        case .status, .saved, .panel:
            return 1
        }
    }

    var stableId: Int {
        switch self {
        case .urlHeader: return 0
        case .url: return 1
        case .key: return 2
        case .status: return 10
        case .saved: return 11
        case .panel: return 12
        }
    }

    static func < (lhs: WewUserbotEntry, rhs: WewUserbotEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewUserbotArguments
        switch self {
        case .urlHeader:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СЕРВЕР", sectionId: self.section)
        case let .url(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Адрес"), text: value, placeholder: "https://wewpa.ru", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { arguments.updateURL($0) }, action: {})
        case let .key(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Ключ"), text: value, placeholder: "wew_…", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { arguments.updateKey($0) }, action: {})
        case let .status(value):
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.bot, title: "Статус", label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .saved(value):
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.deleteChats, title: "Сохранено / удалено", label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case .panel:
            return ItemListDisclosureItem(presentationData: presentationData, icon: PresentationResourcesSettings.appearance, title: "Открыть панель", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openPanel()
            })
        }
    }
}

public func wewpagramUserbotController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let initialState = WewUserbotState(url: settings.cloudServerURL, key: settings.cloudApiKey, status: WewUserbotStatus(title: "…", saved: ""))
    let statePromise = ValuePromise<WewUserbotState>(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WewUserbotState) -> WewUserbotState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var fetchToken = 0
    let refreshStatus: () -> Void = {
        fetchToken += 1
        let token = fetchToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            guard token == fetchToken else { return }
            let current = stateValue.with { $0 }
            wewFetchUserbotStatus(url: current.url, key: current.key.trimmingCharacters(in: .whitespacesAndNewlines), completion: { status in
                guard token == fetchToken else { return }
                updateState { var s = $0; s.status = status; return s }
            })
        }
    }

    let arguments = WewUserbotArguments(
        updateURL: { value in
            settings.cloudServerURL = wewNormalizedServerURL(value)
            updateState { var s = $0; s.url = value; return s }
            refreshStatus()
        },
        updateKey: { value in
            settings.cloudApiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
            updateState { var s = $0; s.key = value; return s }
            refreshStatus()
        },
        openPanel: {
            let url = wewNormalizedServerURL(stateValue.with { $0 }.url)
            guard url.hasPrefix("https://") else { return }
            context.sharedContext.applicationBindings.openUrl(url)
        }
    )

    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [WewUserbotEntry] = [.urlHeader, .url(state.url), .key(state.key), .status(state.status.title)]
        if !state.status.saved.isEmpty {
            entries.append(.saved(state.status.saved))
        }
        if state.url.hasPrefix("https://") {
            entries.append(.panel)
        }

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Юзербот"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }

    refreshStatus()
    return ItemListController(context: context, state: signal)
}
