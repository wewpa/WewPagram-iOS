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

private func wewCloudPing(url: String, key: String, completion: @escaping (String) -> Void) {
    let base = wewNormalizedServerURL(url)
    guard let endpoint = URL(string: base + "/api/ping"), endpoint.scheme == "https" else {
        completion("Укажите адрес сервера вида https://panel.example.com")
        return
    }
    var request = URLRequest(url: endpoint, timeoutInterval: 10.0)
    request.setValue(key, forHTTPHeaderField: "X-Api-Key")
    URLSession.shared.dataTask(with: request) { _, response, error in
        let text: String
        if let error = error {
            text = "Нет соединения: \(error.localizedDescription)"
        } else if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200:
                text = "Соединение установлено ✅"
            case 401:
                text = "Сервер отвечает, но ключ неверный"
            default:
                text = "Ошибка сервера (\(http.statusCode))"
            }
        } else {
            text = "Неизвестный ответ сервера"
        }
        Queue.mainQueue().async {
            completion(text)
        }
    }.resume()
}

private struct WewPagramCloudState: Equatable {
    var url: String
    var key: String
}

private final class WewPagramCloudControllerArguments {
    let updateURL: (String) -> Void
    let updateKey: (String) -> Void
    let check: () -> Void
    let openPanel: () -> Void

    init(updateURL: @escaping (String) -> Void, updateKey: @escaping (String) -> Void, check: @escaping () -> Void, openPanel: @escaping () -> Void) {
        self.updateURL = updateURL
        self.updateKey = updateKey
        self.check = check
        self.openPanel = openPanel
    }
}

private enum WewPagramCloudEntry: ItemListNodeEntry {
    enum StableId: Hashable {
        case header, url, key, footer, check, panel
    }

    case header
    case url(String)
    case key(String)
    case footer
    case check
    case panel

    var section: ItemListSectionId {
        switch self {
        case .header, .url, .key, .footer:
            return 0
        case .check, .panel:
            return 1
        }
    }

    var stableId: StableId {
        switch self {
        case .header: return .header
        case .url: return .url
        case .key: return .key
        case .footer: return .footer
        case .check: return .check
        case .panel: return .panel
        }
    }

    private var sortIndex: Int {
        switch self {
        case .header: return 0
        case .url: return 1
        case .key: return 2
        case .footer: return 3
        case .check: return 4
        case .panel: return 5
        }
    }

    static func < (lhs: WewPagramCloudEntry, rhs: WewPagramCloudEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! WewPagramCloudControllerArguments
        switch self {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: "СЕРВЕР", sectionId: self.section)
        case let .url(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Адрес"), text: value, placeholder: "https://panel.example.com", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { arguments.updateURL($0) }, action: {})
        case let .key(value):
            return ItemListSingleLineInputItem(presentationData: presentationData, title: NSAttributedString(string: "Ключ"), text: value, placeholder: "wew_…", type: .regular(capitalization: false, autocorrection: false), sectionId: self.section, textUpdated: { arguments.updateKey($0) }, action: {})
        case .footer:
            return ItemListTextItem(presentationData: presentationData, text: .plain("Юзербот на вашем сервере продолжает сохранять сообщения, пока Telegram свёрнут или выключен. Ключ создаётся в панели: «Ключи»."), sectionId: self.section)
        case .check:
            return ItemListActionItem(presentationData: presentationData, title: "Проверить соединение", kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                arguments.check()
            })
        case .panel:
            return ItemListDisclosureItem(presentationData: presentationData, title: "Открыть панель", label: "", sectionId: self.section, style: .blocks, action: {
                arguments.openPanel()
            })
        }
    }
}

public func wewpagramCloudController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let initialState = WewPagramCloudState(url: settings.cloudServerURL, key: settings.cloudApiKey)
    let statePromise = ValuePromise<WewPagramCloudState>(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WewPagramCloudState) -> WewPagramCloudState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var presentControllerImpl: ((ViewController) -> Void)?

    let showMessage: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alert = textAlertController(context: context, updatedPresentationData: nil, title: nil, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})
        ])
        presentControllerImpl?(alert)
    }

    let arguments = WewPagramCloudControllerArguments(
        updateURL: { value in
            settings.cloudServerURL = wewNormalizedServerURL(value)
            updateState { var s = $0; s.url = value; return s }
        },
        updateKey: { value in
            settings.cloudApiKey = value.trimmingCharacters(in: .whitespacesAndNewlines)
            updateState { var s = $0; s.key = value; return s }
        },
        check: {
            let current = stateValue.with { $0 }
            wewCloudPing(url: current.url, key: current.key.trimmingCharacters(in: .whitespacesAndNewlines), completion: showMessage)
        },
        openPanel: {
            let url = wewNormalizedServerURL(stateValue.with { $0 }.url)
            guard url.hasPrefix("https://") else {
                showMessage("Сначала укажите адрес сервера (https://…)")
                return
            }
            context.sharedContext.applicationBindings.openUrl(url)
        }
    )

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [WewPagramCloudEntry] = [.header, .url(state.url), .key(state.key), .footer, .check, .panel]

        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text("Облако"),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}
