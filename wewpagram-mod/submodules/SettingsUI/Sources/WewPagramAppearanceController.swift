import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// MARK: - Appearance (also what plugins change through wew.theme)

public func wewpagramAppearanceController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let changes = Signal<Void, NoError>.single(Void()) |> then(wewDefaultsChanged())

    let entries = combineLatest(queue: .mainQueue(), changes, settings.themeRevision.get())
    |> map { _, _ -> [WewEntry] in
        let menu = settings.menuTheme
        let data = context.sharedContext.currentPresentationData.with { $0 }
        let isDark = wewMenuIsDark(data)

        func update(_ change: @escaping (inout WewPagramSettings.WewMenuTheme) -> Void) {
            var value = settings.menuTheme
            change(&value)
            settings.menuTheme = value
        }

        var result: [WewEntry] = [
            wewSwitch(0, 0, icon: nil, title: "Сакура", value: menu.sakuraOn, update: { value in
                update { $0.sakura = value }
            }),
            wewSwitch(1, 0, icon: nil, title: "Тёмная тема", value: isDark, update: { value in
                update { $0.dark = value }
            }),
            wewSwitch(2, 0, icon: nil, title: "ID в профилях", value: settings.showProfileId, update: { value in
                settings.showProfileId = value
            }),

            wewHeader(10, 1, "ЦВЕТА"),
            wewInput(11, 1, title: "Акцент", text: menu.accent ?? "", placeholder: "#3A9BF0", update: { text in
                update { $0.accent = text.isEmpty ? nil : text }
            }),
            wewInput(12, 1, title: "Фон", text: menu.background ?? "", placeholder: "#101820", update: { text in
                update { $0.background = text.isEmpty ? nil : text }
            }),
            wewInput(13, 1, title: "Карточки", text: menu.card ?? "", placeholder: "#1B2733", update: { text in
                update { $0.card = text.isEmpty ? nil : text }
            }),
            wewInput(14, 1, title: "Текст", text: menu.text ?? "", placeholder: "#FFFFFF", update: { text in
                update { $0.text = text.isEmpty ? nil : text }
            }),

            wewHeader(20, 2, "РАЗМЕР ТЕКСТА")
        ]

        let sizes: [(String, String)] = [("small", "Мелкий"), ("regular", "Обычный"), ("medium", "Средний"), ("large", "Крупный"), ("xlarge", "Очень крупный")]
        for (index, size) in sizes.enumerated() {
            let selected = (menu.fontSize ?? "regular") == size.0
            result.append(wewRow(21 + index, 2, icon: nil, title: size.1, label: selected ? "✓" : "", action: {
                update { $0.fontSize = size.0 }
            }))
        }

        if menu.backgroundImage != nil {
            result.append(wewHeader(30, 3, "ФОН"))
            result.append(wewRow(31, 3, icon: nil, title: "Картинка из плагина", label: "убрать", action: {
                update { $0.backgroundImage = nil }
            }))
        }

        result.append(wewAction(100, 4, title: "Сбросить оформление", destructive: true, action: {
            settings.menuTheme = WewPagramSettings.WewMenuTheme()
        }))
        return result
    }
    return wewListController(context: context, title: "Внешний вид", entries: entries)
}

// MARK: - Local Premium

public func wewpagramPremiumController(context: AccountContext) -> ViewController {
    let settings = WewPagramSettings.shared
    let accountId = context.account.peerId.id._internalGetInt64Value()
    let changes = Signal<Void, NoError>.single(Void()) |> then(wewDefaultsChanged())

    let entries = changes |> map { _ -> [WewEntry] in
        return [
            wewSwitch(0, 0, icon: PresentationResourcesSettings.premium, title: "Premium", subtitle: "Только на этом устройстве", value: settings.localPremiumEnabled, update: { value in
                settings.rememberSelfUser(accountId)
                settings.localPremiumEnabled = value
                WewPluginPresenter.shared.toast("Перезапустите приложение, чтобы Premium применился везде")
            }),
            wewText(1, 1, text: "Открывает интерфейс Premium: значок у имени, эмодзи-статус, цвета профиля и имени, платные реакции и эмодзи, увеличенные лимиты папок, закрепов и аккаунтов. То, что решает сервер (загрузка до 4 ГБ, голос в текст, быстрая загрузка), не включится.")
        ]
    }
    return wewListController(context: context, title: "Premium", entries: entries)
}
