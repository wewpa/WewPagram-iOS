import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import AccountContext

// MARK: - File picker

private final class WewZipPickerDelegate: NSObject, UIDocumentPickerDelegate {
    private let completion: (URL?) -> Void

    init(completion: @escaping (URL?) -> Void) {
        self.completion = completion
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        self.completion(urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        self.completion(nil)
    }
}

private var wewActivePicker: WewZipPickerDelegate?

private func wewPickZip(from controller: ViewController?, completion: @escaping (Data?) -> Void) {
    let picker = UIDocumentPickerViewController(documentTypes: ["public.zip-archive", "com.pkware.zip-archive"], in: .import)
    let delegate = WewZipPickerDelegate(completion: { url in
        wewActivePicker = nil
        guard let url = url else {
            completion(nil)
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        let data = try? Data(contentsOf: url)
        if accessing {
            url.stopAccessingSecurityScopedResource()
        }
        completion(data)
    })
    wewActivePicker = delegate
    picker.delegate = delegate
    controller?.present(picker, animated: true, completion: nil)
}

private func wewPluginIcon(_ plugin: WewPluginInfo) -> UIImage? {
    if let path = plugin.iconPath, let tile = wewPluginTile(path: path) {
        return tile
    }
    return PresentationResourcesSettings.appearance
}

// MARK: - Plugin list

public func wewpagramPluginsController(context: AccountContext) -> ViewController {
    let manager = WewPluginManager.shared
    manager.startIfNeeded()

    let controllerRef: ViewController?

    let entries = manager.revision.get() |> deliverOnMainQueue |> map { _ -> [WewEntry] in
        let plugins = manager.installedPlugins()
        var result: [WewEntry] = [
            wewAction(0, 0, title: "Установить плагин (.zip)", action: {
                wewPickZip(from: controllerRef, completion: { data in
                    guard let data = data else { return }
                    do {
                        let info = try manager.install(zipData: data)
                        wewShowAlert(context: context, controller: controllerRef, text: "Плагин «\(info.manifest.name)» \(info.manifest.version) установлен и уже работает.")
                    } catch {
                        let reason = (error as? LocalizedError)?.errorDescription ?? "Не удалось установить плагин."
                        wewShowAlert(context: context, controller: controllerRef, text: reason)
                    }
                })
            })
        ]
        if !plugins.isEmpty {
            result.append(wewHeader(10, 1, "УСТАНОВЛЕННЫЕ · \(plugins.count)"))
            for (index, plugin) in plugins.enumerated() {
                let label = plugin.enabled ? "v" + plugin.manifest.version : "выкл"
                result.append(wewRow(100 + index, 1, icon: wewPluginIcon(plugin), title: plugin.manifest.name, label: label, action: {
                    (controllerRef as? ItemListController)?.push(wewPluginDetailController(context: context, pluginId: plugin.manifest.id))
                }))
            }
        }
        return result
    }

    let controller = wewListController(context: context, title: "Плагины", entries: entries)
    return controller
}

// MARK: - Plugin details

private func wewPluginDetailController(context: AccountContext, pluginId: String) -> ViewController {
    let manager = WewPluginManager.shared
    let controllerRef: ViewController?

    let entries = manager.revision.get() |> deliverOnMainQueue |> map { _ -> [WewEntry] in
        guard let plugin = manager.plugin(id: pluginId) else {
            return []
        }
        var result: [WewEntry] = [
            wewSwitch(0, 0, icon: wewPluginIcon(plugin), title: plugin.manifest.name, value: plugin.enabled, update: { value in
                manager.setEnabled(id: pluginId, enabled: value)
            })
        ]

        var order = 10
        result.append(wewRow(order, 1, icon: nil, title: "Версия", label: plugin.manifest.version, action: nil))
        order += 1
        if let author = plugin.manifest.author, !author.isEmpty {
            result.append(wewRow(order, 1, icon: nil, title: "Автор", label: author, action: nil))
            order += 1
        }
        let permissions = (plugin.manifest.permissions ?? []).joined(separator: ", ")
        if !permissions.isEmpty {
            result.append(wewRow(order, 1, icon: nil, title: "Разрешения", label: permissions, action: nil))
            order += 1
        }
        if let description = plugin.manifest.description, !description.isEmpty {
            result.append(wewText(order, 1, text: description))
            order += 1
        }

        let logs = manager.logs(pluginId: pluginId).suffix(8)
        if !logs.isEmpty {
            result.append(wewHeader(100, 2, "ЖУРНАЛ"))
            result.append(wewText(101, 2, text: logs.joined(separator: "\n")))
        }

        result.append(wewAction(1000, 3, title: "Удалить плагин", destructive: true, action: {
            wewConfirm(context: context, controller: controllerRef, text: "Удалить плагин «\(plugin.manifest.name)» вместе с его файлами и изображениями?", action: {
                manager.remove(id: pluginId)
                controllerRef?.navigationController?.popViewController(animated: true)
            })
        }))
        return result
    }

    let controller = wewListController(context: context, title: "Плагин", entries: entries)
    return controller
}

// MARK: - Plugin page (declared by the plugin through wew.menu.add)

public func wewpagramPluginPageController(context: AccountContext, pluginId: String, itemId: String) -> ViewController {
    let manager = WewPluginManager.shared
    let tick = ValuePromise<Int>(0, ignoreRepeated: false)
    var counter = 0
    let refresh: () -> Void = {
        counter += 1
        tick.set(counter)
    }

    let title = manager.menuItems().first(where: { $0.pluginId == pluginId && $0.itemId == itemId })?.title ?? "Плагин"

    let entries = combineLatest(queue: .mainQueue(), tick.get(), manager.revision.get()) |> map { _, _ -> [WewEntry] in
        guard let item = manager.menuItems().first(where: { $0.pluginId == pluginId && $0.itemId == itemId }) else {
            return []
        }
        var result: [WewEntry] = []
        for (index, control) in item.controls.enumerated() {
            switch control.type {
            case "header":
                result.append(wewHeader(index, 0, control.title.uppercased()))
            case "info":
                result.append(wewText(index, 0, text: control.title))
            case "switch":
                let value = manager.storedBool(pluginId: pluginId, key: control.key, fallback: control.defaultValue == "true")
                result.append(wewSwitch(index, 0, icon: nil, title: control.title, value: value, update: { newValue in
                    manager.storeBool(pluginId: pluginId, key: control.key, value: newValue)
                    manager.dispatch(pluginId: pluginId, event: "setting", args: [control.key, newValue])
                    refresh()
                }))
            case "input":
                let value = manager.storedString(pluginId: pluginId, key: control.key, fallback: control.defaultValue)
                result.append(wewInput(index, 0, title: control.title, text: value, placeholder: control.placeholder, update: { text in
                    manager.storeString(pluginId: pluginId, key: control.key, value: text)
                    manager.dispatch(pluginId: pluginId, event: "setting", args: [control.key, text])
                    refresh()
                }))
            case "button":
                result.append(wewAction(index, 0, title: control.title, action: {
                    manager.dispatch(pluginId: pluginId, event: "button", args: [control.key])
                }))
            default:
                break
            }
        }
        return result
    }

    let controller = wewListController(context: context, title: title, entries: entries)
    return controller
}
