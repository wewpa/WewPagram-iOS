import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// The app and the userbot are tied together by the Telegram account id: the
// app registers its account with the server, the userbot reports the same id.
// The only control the user gets is the on/off switch.

private func wewUserbotRequest(path: String, method: String, key: String?, body: [String: Any]?, completion: @escaping (Int, [String: Any]?) -> Void) {
    guard let url = URL(string: WewPagramSettings.serverURL + path) else {
        completion(0, nil)
        return
    }
    var request = URLRequest(url: url, timeoutInterval: 12.0)
    request.httpMethod = method
    if let key = key {
        request.setValue(key, forHTTPHeaderField: "X-Api-Key")
    }
    if let body = body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    URLSession.shared.dataTask(with: request) { data, response, _ in
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        DispatchQueue.main.async {
            completion(code, json)
        }
    }.resume()
}

private enum WewUserbotResult {
    case ok(enabled: Bool, text: String)
    case failure(String)
}

private func wewDescribe(_ json: [String: Any]) -> WewUserbotResult {
    let enabled = json["enabled"] as? Bool ?? true
    let online = json["online"] as? Bool ?? false
    let text: String
    if !online {
        text = enabled ? "Юзербот вашего аккаунта не запущен" : "Выключен"
    } else {
        text = enabled ? "Работает" : "Выключен"
    }
    return .ok(enabled: enabled, text: text)
}

private func wewEnsureRegistered(accountId: Int64, completion: @escaping (WewUserbotResult?) -> Void) {
    let settings = WewPagramSettings.shared
    if !settings.userbotAppKey.isEmpty {
        completion(nil)
        return
    }
    wewUserbotRequest(path: "/api/app/register", method: "POST", key: nil, body: ["account_id": accountId, "secret": WewPagramSettings.enrollSecret]) { code, json in
        if code == 200, let key = json?["key"] as? String {
            settings.userbotAppKey = key
            completion(nil)
        } else if code == 0 {
            completion(.failure("Нет соединения с сервером"))
        } else if code == 403 {
            completion(.failure("Сервер не принял приложение (проверьте ENROLL_SECRET)"))
        } else {
            completion(.failure("Ошибка сервера (\(code))"))
        }
    }
}

private func wewFetchStatus(accountId: Int64, allowRetry: Bool, completion: @escaping (WewUserbotResult) -> Void) {
    wewEnsureRegistered(accountId: accountId, completion: { failure in
        if let failure = failure {
            completion(failure)
            return
        }
        let settings = WewPagramSettings.shared
        wewUserbotRequest(path: "/api/app/status", method: "GET", key: settings.userbotAppKey, body: nil) { code, json in
            if code == 200, let json = json {
                completion(wewDescribe(json))
            } else if code == 401, allowRetry {
                // The key was rotated or removed on the server: register again.
                settings.userbotAppKey = ""
                wewFetchStatus(accountId: accountId, allowRetry: false, completion: completion)
            } else if code == 0 {
                completion(.failure("Нет соединения с сервером"))
            } else {
                completion(.failure("Ошибка сервера (\(code))"))
            }
        }
    })
}

private func wewSetUserbotEnabled(accountId: Int64, value: Bool, completion: @escaping (WewUserbotResult) -> Void) {
    wewEnsureRegistered(accountId: accountId, completion: { failure in
        if let failure = failure {
            completion(failure)
            return
        }
        let settings = WewPagramSettings.shared
        wewUserbotRequest(path: "/api/app/enabled", method: "POST", key: settings.userbotAppKey, body: ["enabled": value]) { code, _ in
            if code == 200 {
                settings.userbotEnabled = value
                wewFetchStatus(accountId: accountId, allowRetry: true, completion: completion)
            } else if code == 401 {
                settings.userbotAppKey = ""
                completion(.failure("Ключ устарел, повторите"))
            } else if code == 0 {
                completion(.failure("Нет соединения с сервером"))
            } else {
                completion(.failure("Ошибка сервера (\(code))"))
            }
        }
    })
}

private struct WewUserbotState: Equatable {
    var enabled: Bool
    var text: String
}

public func wewpagramUserbotController(context: AccountContext) -> ViewController {
    let accountId = context.account.peerId.id._internalGetInt64Value()
    let initial = WewUserbotState(enabled: WewPagramSettings.shared.userbotEnabled, text: "Проверяю…")
    let state = ValuePromise<WewUserbotState>(initial, ignoreRepeated: true)
    let stateValue = Atomic(value: initial)
    let update: ((WewUserbotState) -> WewUserbotState) -> Void = { f in
        state.set(stateValue.modify(f))
    }

    let apply: (WewUserbotResult) -> Void = { result in
        switch result {
        case let .ok(enabled, text):
            WewPagramSettings.shared.userbotEnabled = enabled
            update { _ in WewUserbotState(enabled: enabled, text: text) }
        case let .failure(text):
            update { var s = $0; s.text = text; return s }
        }
    }

    let entries = state.get() |> map { s -> [WewEntry] in
        return [
            wewSwitch(0, 0, icon: PresentationResourcesSettings.bot, title: "Юзербот", subtitle: s.text, value: s.enabled, update: { value in
                update { _ in WewUserbotState(enabled: value, text: "Применяю…") }
                wewSetUserbotEnabled(accountId: accountId, value: value, completion: apply)
            })
        ]
    }

    wewFetchStatus(accountId: accountId, allowRetry: true, completion: apply)
    return wewListController(context: context, title: "Юзербот", entries: entries)
}
