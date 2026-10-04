import Foundation
import JavaScriptCore
import SwiftSignalKit

// MARK: - Model

public struct WewPluginManifest: Codable, Equatable {
    public var id: String
    public var name: String
    public var version: String
    public var author: String?
    public var description: String?
    public var icon: String?
    public var logo: String?
    public var entry: String?
    public var permissions: [String]?
}

public struct WewPluginInfo: Equatable {
    public var manifest: WewPluginManifest
    public var directory: String
    public var enabled: Bool

    public func filePath(_ relative: String?) -> String? {
        guard let relative = relative, !relative.isEmpty, !relative.contains("..") else {
            return nil
        }
        let path = (self.directory as NSString).appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: path) ? path : nil
    }

    public var iconPath: String? {
        return self.filePath(self.manifest.icon)
    }
}

public struct WewPluginControl: Equatable {
    public var type: String          // header | info | switch | input | button
    public var key: String
    public var title: String
    public var placeholder: String
    public var defaultValue: String
}

public struct WewPluginMenuItem: Equatable {
    public var pluginId: String
    public var itemId: String
    public var title: String
    public var iconPath: String?
    public var controls: [WewPluginControl]
}

public enum WewPluginError: Error, LocalizedError {
    case badArchive
    case noManifest
    case badManifest(String)
    case noFiles

    public var errorDescription: String? {
        switch self {
        case .badArchive:
            return "Не удалось прочитать архив. Нужен обычный .zip."
        case .noManifest:
            return "В архиве нет plugin.json."
        case let .badManifest(reason):
            return "plugin.json: \(reason)"
        case .noFiles:
            return "В архиве нет подходящих файлов."
        }
    }
}

// MARK: - Runtime

private final class WewPluginRuntime {
    let info: WewPluginInfo
    let context: JSContext
    var events = Set<String>()
    var menuItems: [WewPluginMenuItem] = []
    var logs: [String] = []

    init(info: WewPluginInfo, context: JSContext) {
        self.info = info
        self.context = context
    }
}

private final class WewResultBox {
    private let lock = NSLock()
    private var value: String

    init(_ value: String) {
        self.value = value
    }

    func set(_ newValue: String) {
        self.lock.lock()
        self.value = newValue
        self.lock.unlock()
    }

    func get() -> String {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
    }
}

public final class WewPluginManager {
    public static let shared = WewPluginManager()

    // Bumped whenever the plugin list, the enabled flags or the menu entries change.
    public let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    private var revisionCounter = 0

    private let queue = DispatchQueue(label: "WewPagram.plugins")
    private let stateLock = NSLock()
    private var runtimes: [String: WewPluginRuntime] = [:]
    private var outgoingHookPlugins: [String] = []
    private var started = false

    private let defaults = UserDefaults.standard
    private let enabledKey = "WewPagram.plugins.enabled"
    private let disabledKey = "WewPagram.plugins.disabled"

    private static let allowedExtensions: Set<String> = ["js", "json", "png", "jpg", "jpeg", "txt", "md"]
    private static let knownPermissions: Set<String> = ["profile", "ghost", "deleted", "http", "send", "theme"]

    private init() {}

    public var rootDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WewPagram", isDirectory: true).appendingPathComponent("plugins", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        return base
    }

    // MARK: Lifecycle

    public func startIfNeeded() {
        // Extensions (notifications, share...) have tight memory limits: no plugins there.
        if Bundle.main.bundlePath.hasSuffix(".appex") {
            return
        }
        DispatchQueue.main.async {
            WewZones.install()
        }
        self.stateLock.lock()
        let shouldStart = !self.started
        self.started = true
        self.stateLock.unlock()
        if shouldStart {
            self.reload()
        }
    }

    private func bump() {
        self.stateLock.lock()
        self.revisionCounter += 1
        let value = self.revisionCounter
        self.stateLock.unlock()
        self.revision.set(value)
    }

    // MARK: Listing

    private var disabledIds: Set<String> {
        return Set(self.defaults.stringArray(forKey: self.disabledKey) ?? [])
    }

    public func installedPlugins() -> [WewPluginInfo] {
        var result: [WewPluginInfo] = []
        let disabled = self.disabledIds
        let items = (try? FileManager.default.contentsOfDirectory(atPath: self.rootDirectory.path)) ?? []
        for item in items.sorted() {
            let directory = self.rootDirectory.appendingPathComponent(item, isDirectory: true)
            let manifestURL = directory.appendingPathComponent("plugin.json")
            guard let data = try? Data(contentsOf: manifestURL), let manifest = try? JSONDecoder().decode(WewPluginManifest.self, from: data) else {
                continue
            }
            result.append(WewPluginInfo(manifest: manifest, directory: directory.path, enabled: !disabled.contains(manifest.id)))
        }
        return result
    }

    public func plugin(id: String) -> WewPluginInfo? {
        return self.installedPlugins().first(where: { $0.manifest.id == id })
    }

    public func menuItems() -> [WewPluginMenuItem] {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        return self.runtimes.values.sorted(by: { $0.info.manifest.name < $1.info.manifest.name }).flatMap { $0.menuItems }
    }

    // The first enabled plugin that ships a logo replaces the logo in the menu header.
    public func logoPath() -> String? {
        for plugin in self.installedPlugins() where plugin.enabled {
            if let path = plugin.filePath(plugin.manifest.logo) {
                return path
            }
        }
        return nil
    }

    public func logs(pluginId: String) -> [String] {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        return self.runtimes[pluginId]?.logs ?? []
    }

    // MARK: Install / remove

    @discardableResult
    public func install(zipData: Data) throws -> WewPluginInfo {
        let archive: WewZipArchive
        do {
            archive = try WewZipArchive(data: zipData)
        } catch {
            throw WewPluginError.badArchive
        }

        // Only real files, no macOS metadata.
        let files = archive.entries.filter { entry in
            if entry.isDirectory { return false }
            if entry.name.hasPrefix("__MACOSX/") || entry.name.contains("/.") || entry.name.hasPrefix(".") { return false }
            return true
        }

        // plugin.json either in the archive root or inside a single top-level folder.
        var prefix = ""
        if !files.contains(where: { $0.name == "plugin.json" }) {
            guard let manifestEntry = files.first(where: { $0.name.hasSuffix("/plugin.json") && $0.name.split(separator: "/").count == 2 }) else {
                throw WewPluginError.noManifest
            }
            prefix = String(manifestEntry.name.dropLast("plugin.json".count))
        }

        guard let manifestEntry = files.first(where: { $0.name == prefix + "plugin.json" }), let manifestData = try? archive.read(manifestEntry) else {
            throw WewPluginError.noManifest
        }
        let manifest: WewPluginManifest
        do {
            manifest = try JSONDecoder().decode(WewPluginManifest.self, from: manifestData)
        } catch {
            throw WewPluginError.badManifest("неверный формат (нужны id, name, version)")
        }
        guard manifest.id.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil, !manifest.id.hasPrefix(".") else {
            throw WewPluginError.badManifest("id может содержать только латиницу, цифры, точку, дефис и подчёркивание")
        }
        guard !manifest.name.isEmpty, !manifest.version.isEmpty else {
            throw WewPluginError.badManifest("пустые name или version")
        }

        // Extract into a staging folder first, then swap it in.
        let staging = self.rootDirectory.appendingPathComponent(".staging-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true, attributes: nil)
        var written = 0
        for entry in files {
            guard entry.name.hasPrefix(prefix) else { continue }
            let relative = String(entry.name.dropFirst(prefix.count))
            if relative.isEmpty || relative.hasPrefix("/") || relative.split(separator: "/").contains("..") {
                continue
            }
            let fileExtension = (relative as NSString).pathExtension.lowercased()
            guard WewPluginManager.allowedExtensions.contains(fileExtension) else { continue }
            guard let data = try? archive.read(entry) else { continue }

            let destination = staging.appendingPathComponent(relative)
            try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
            if (try? data.write(to: destination, options: .atomic)) != nil {
                written += 1
            }
        }
        guard written > 0 else {
            try? FileManager.default.removeItem(at: staging)
            throw WewPluginError.noFiles
        }

        let target = self.rootDirectory.appendingPathComponent(manifest.id, isDirectory: true)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: staging, to: target)

        var disabled = self.disabledIds
        disabled.remove(manifest.id)
        self.defaults.set(Array(disabled), forKey: self.disabledKey)

        self.reload()
        return WewPluginInfo(manifest: manifest, directory: target.path, enabled: true)
    }

    public func remove(id: String) {
        guard id.range(of: "^[A-Za-z0-9._-]{1,64}$", options: .regularExpression) != nil else { return }
        try? FileManager.default.removeItem(at: self.rootDirectory.appendingPathComponent(id, isDirectory: true))
        self.reload()
    }

    public func setEnabled(id: String, enabled: Bool) {
        var disabled = self.disabledIds
        if enabled {
            disabled.remove(id)
        } else {
            disabled.insert(id)
        }
        self.defaults.set(Array(disabled), forKey: self.disabledKey)
        self.reload()
    }

    // MARK: Plugin storage

    private func storageKey(_ pluginId: String, _ key: String) -> String {
        return "WewPlugin.\(pluginId).\(key)"
    }

    public func storageGet(pluginId: String, key: String) -> String? {
        return self.defaults.string(forKey: self.storageKey(pluginId, key))
    }

    public func storageSet(pluginId: String, key: String, value: String?) {
        if let value = value {
            self.defaults.set(value, forKey: self.storageKey(pluginId, key))
        } else {
            self.defaults.removeObject(forKey: self.storageKey(pluginId, key))
        }
    }

    // Values edited on plugin pages are stored exactly like wew.storage values (JSON).
    private func decodeStored(_ raw: String?) -> Any? {
        guard let raw = raw, let data = ("[" + raw + "]").data(using: .utf8), let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            return nil
        }
        return array.first
    }

    public func storedString(pluginId: String, key: String, fallback: String) -> String {
        let value = self.decodeStored(self.storageGet(pluginId: pluginId, key: key))
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return fallback
    }

    public func storedBool(pluginId: String, key: String, fallback: Bool) -> Bool {
        let value = self.decodeStored(self.storageGet(pluginId: pluginId, key: key))
        if let flag = value as? Bool {
            return flag
        }
        return fallback
    }

    public func storeString(pluginId: String, key: String, value: String) {
        self.storageSet(pluginId: pluginId, key: key, value: WewPluginManager.jsString(value))
    }

    public func storeBool(pluginId: String, key: String, value: Bool) {
        self.storageSet(pluginId: pluginId, key: key, value: value ? "true" : "false")
    }

    // MARK: Reload

    public func reload() {
        self.queue.async {
            var newRuntimes: [String: WewPluginRuntime] = [:]
            for plugin in self.installedPlugins() where plugin.enabled {
                if let runtime = self.makeRuntime(for: plugin) {
                    newRuntimes[plugin.manifest.id] = runtime
                }
            }

            self.stateLock.lock()
            self.runtimes = newRuntimes
            self.outgoingHookPlugins = newRuntimes.values.filter { $0.events.contains("message.send") }.map { $0.info.manifest.id }.sorted()
            self.stateLock.unlock()

            // `start` handlers run after everything is registered.
            for runtime in newRuntimes.values.sorted(by: { $0.info.manifest.id < $1.info.manifest.id }) {
                self.callEmit(runtime, event: "start", args: [])
            }
            self.bump()
        }
    }

    private func appendLog(_ runtime: WewPluginRuntime, _ message: String) {
        self.stateLock.lock()
        runtime.logs.append(message)
        if runtime.logs.count > 200 {
            runtime.logs.removeFirst(runtime.logs.count - 200)
        }
        self.stateLock.unlock()
    }

    private func makeRuntime(for plugin: WewPluginInfo) -> WewPluginRuntime? {
        guard let context = JSContext() else {
            return nil
        }
        let runtime = WewPluginRuntime(info: plugin, context: context)
        let permissions = Set(plugin.manifest.permissions ?? [])
        let pluginId = plugin.manifest.id

        context.exceptionHandler = { [weak self, weak runtime] _, exception in
            guard let self = self, let runtime = runtime else { return }
            self.appendLog(runtime, "Ошибка: \(exception?.toString() ?? "?")")
        }

        let allow: (String) -> Bool = { [weak self, weak runtime] permission in
            if permissions.contains(permission) {
                return true
            }
            if let self = self, let runtime = runtime {
                self.appendLog(runtime, "Нет разрешения «\(permission)» в plugin.json")
            }
            return false
        }

        let log: @convention(block) (String) -> Void = { [weak self, weak runtime] message in
            guard let self = self, let runtime = runtime else { return }
            self.appendLog(runtime, message)
        }
        let storageGet: @convention(block) (String) -> String? = { [weak self] key in
            return self?.storageGet(pluginId: pluginId, key: key)
        }
        let storageSet: @convention(block) (String, String) -> Void = { [weak self] key, value in
            self?.storageSet(pluginId: pluginId, key: key, value: value)
        }
        let storageRemove: @convention(block) (String) -> Void = { [weak self] key in
            self?.storageSet(pluginId: pluginId, key: key, value: nil)
        }
        let assetPath: @convention(block) (String) -> String? = { name in
            return plugin.filePath(name)
        }
        let assetList: @convention(block) () -> [String] = {
            var result: [String] = []
            if let enumerator = FileManager.default.enumerator(atPath: plugin.directory) {
                for case let path as String in enumerator {
                    let ext = (path as NSString).pathExtension.lowercased()
                    if ext == "png" || ext == "jpg" || ext == "jpeg" {
                        result.append(path)
                    }
                }
            }
            return result.sorted()
        }
        let registered: @convention(block) (String) -> Void = { [weak runtime] event in
            _ = runtime?.events.insert(event)
        }
        let ghostSet: @convention(block) (Bool) -> Void = { value in
            if allow("ghost") {
                WewPagramSettings.shared.isGhostModeEnabled = value
            }
        }
        let ghostGet: @convention(block) () -> Bool = {
            return WewPagramSettings.shared.isGhostModeEnabled
        }
        let deletedSet: @convention(block) (Bool) -> Void = { value in
            if allow("deleted") {
                WewPagramSettings.shared.deletedMessagesEnabled = value
            }
        }
        let profileSet: @convention(block) (String) -> Void = { json in
            guard allow("profile"), let data = json.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return
            }
            let settings = WewPagramSettings.shared
            if let phone = object["phone"] as? String {
                settings.fakePhoneNumber = phone.isEmpty ? nil : phone
            }
            if let value = object["ratingEnabled"] as? Bool {
                settings.fakeRatingEnabled = value
            }
            if let value = object["ratingLevel"] as? Int {
                settings.fakeRatingLevel = value
            }
            if let value = object["ratingPoints"] as? Int {
                settings.fakeRatingStars = value
            }
            settings.notifyProfileChanged()
        }
        let profileGet: @convention(block) () -> String = {
            let settings = WewPagramSettings.shared
            let object: [String: Any] = [
                "phone": settings.fakePhoneNumber ?? "",
                "ratingEnabled": settings.fakeRatingEnabled,
                "ratingLevel": settings.fakeRatingLevel,
                "ratingPoints": settings.fakeRatingStars
            ]
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        let alert: @convention(block) (String) -> Void = { text in
            WewPluginPresenter.shared.alert(title: plugin.manifest.name, text: text)
        }
        let toast: @convention(block) (String) -> Void = { text in
            WewPluginPresenter.shared.toast(text)
        }
        let menuAdd: @convention(block) (String) -> Void = { [weak runtime] json in
            guard let runtime = runtime, let data = json.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return
            }
            let itemId = object["id"] as? String ?? UUID().uuidString
            let title = object["title"] as? String ?? plugin.manifest.name
            var iconPath: String?
            if let icon = object["icon"] as? String {
                iconPath = plugin.filePath(icon)
            }
            var controls: [WewPluginControl] = []
            for raw in (object["page"] as? [[String: Any]] ?? []) {
                guard let type = raw["type"] as? String, ["header", "info", "switch", "input", "button"].contains(type) else { continue }
                var defaultValue = ""
                if let flag = raw["default"] as? Bool {
                    defaultValue = flag ? "true" : "false"
                } else if let text = raw["default"] as? String {
                    defaultValue = text
                } else if let number = raw["default"] as? NSNumber {
                    defaultValue = number.stringValue
                }
                controls.append(WewPluginControl(
                    type: type,
                    key: (raw["key"] as? String) ?? (raw["id"] as? String) ?? "",
                    title: (raw["title"] as? String) ?? (raw["text"] as? String) ?? "",
                    placeholder: (raw["placeholder"] as? String) ?? "",
                    defaultValue: defaultValue
                ))
            }
            runtime.menuItems.removeAll(where: { $0.itemId == itemId })
            runtime.menuItems.append(WewPluginMenuItem(pluginId: pluginId, itemId: itemId, title: title, iconPath: iconPath, controls: controls))
        }
        let themeGet: @convention(block) () -> String = {
            let theme = WewPagramSettings.shared.menuTheme
            var object: [String: Any] = ["sakura": theme.sakuraOn]
            if let value = theme.dark { object["dark"] = value }
            if let value = theme.accent { object["accent"] = value }
            if let value = theme.background { object["background"] = value }
            if let value = theme.card { object["card"] = value }
            if let value = theme.text { object["text"] = value }
            if let value = theme.fontSize { object["fontSize"] = value }
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        let themeSet: @convention(block) (String) -> Void = { json in
            guard allow("theme"), let data = json.data(using: .utf8), let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                return
            }
            // .some(nil) means "explicit null": reset that value.
            func string(_ key: String) -> String?? {
                guard let raw = object[key] else { return nil }
                if raw is NSNull { return .some(nil) }
                return .some(raw as? String)
            }
            var theme = WewPagramSettings.shared.menuTheme
            if let raw = object["dark"] {
                theme.dark = raw as? Bool
            }
            if let value = string("accent") { theme.accent = value }
            if let value = string("card") { theme.card = value }
            if let value = string("text") { theme.text = value }
            if let value = string("fontSize") {
                if let name = value, ["small", "regular", "medium", "large", "xlarge"].contains(name) {
                    theme.fontSize = name
                } else if value == nil {
                    theme.fontSize = nil
                }
            }
            if let raw = object["sakura"] {
                theme.sakura = raw as? Bool
            }
            if let value = string("background") {
                if let name = value, !name.isEmpty {
                    if name.hasPrefix("#") {
                        theme.background = name
                        theme.backgroundImage = nil
                    } else if plugin.filePath(name) != nil {
                        // a picture from this plugin's archive (png / jpg)
                        theme.backgroundImage = pluginId + "|" + name
                        theme.background = nil
                    }
                } else {
                    theme.background = nil
                    theme.backgroundImage = nil
                }
            }
            WewPagramSettings.shared.menuTheme = theme
        }
        let themeReset: @convention(block) () -> Void = {
            if allow("theme") {
                WewPagramSettings.shared.menuTheme = WewPagramSettings.WewMenuTheme()
            }
        }
        let httpGet: @convention(block) (String, Int) -> Void = { [weak self, weak runtime] urlString, callbackId in
            guard allow("http"), let url = URL(string: urlString), url.scheme == "https" else {
                self?.queue.async {
                    if let runtime = runtime {
                        runtime.context.objectForKeyedSubscript("__httpResult")?.call(withArguments: [callbackId, 0, "https only"])
                    }
                }
                return
            }
            var request = URLRequest(url: url, timeoutInterval: 15.0)
            request.httpMethod = "GET"
            URLSession.shared.dataTask(with: request) { data, response, _ in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = String(data: (data ?? Data()).prefix(1_000_000), encoding: .utf8) ?? ""
                self?.queue.async {
                    if let runtime = runtime {
                        runtime.context.objectForKeyedSubscript("__httpResult")?.call(withArguments: [callbackId, status, body])
                    }
                }
            }.resume()
        }

        context.setObject(log, forKeyedSubscript: "__log" as NSString)
        context.setObject(storageGet, forKeyedSubscript: "__storageGet" as NSString)
        context.setObject(storageSet, forKeyedSubscript: "__storageSet" as NSString)
        context.setObject(storageRemove, forKeyedSubscript: "__storageRemove" as NSString)
        context.setObject(assetPath, forKeyedSubscript: "__assetPath" as NSString)
        context.setObject(assetList, forKeyedSubscript: "__assetList" as NSString)
        context.setObject(registered, forKeyedSubscript: "__registered" as NSString)
        context.setObject(ghostSet, forKeyedSubscript: "__ghostSet" as NSString)
        context.setObject(ghostGet, forKeyedSubscript: "__ghostGet" as NSString)
        context.setObject(deletedSet, forKeyedSubscript: "__deletedSet" as NSString)
        context.setObject(profileSet, forKeyedSubscript: "__profileSet" as NSString)
        context.setObject(profileGet, forKeyedSubscript: "__profileGet" as NSString)
        context.setObject(alert, forKeyedSubscript: "__alert" as NSString)
        context.setObject(toast, forKeyedSubscript: "__toast" as NSString)
        context.setObject(menuAdd, forKeyedSubscript: "__menuAdd" as NSString)
        context.setObject(httpGet, forKeyedSubscript: "__httpGet" as NSString)
        context.setObject(themeGet, forKeyedSubscript: "__themeGet" as NSString)
        context.setObject(themeSet, forKeyedSubscript: "__themeSet" as NSString)
        context.setObject(themeReset, forKeyedSubscript: "__themeReset" as NSString)

        context.evaluateScript("var __plugin = {id: \(WewPluginManager.jsString(pluginId)), name: \(WewPluginManager.jsString(plugin.manifest.name)), version: \(WewPluginManager.jsString(plugin.manifest.version))};")
        context.evaluateScript(WewPluginManager.prelude)

        let entry = plugin.manifest.entry ?? "main.js"
        if let path = plugin.filePath(entry), let source = try? String(contentsOfFile: path, encoding: .utf8) {
            context.evaluateScript(source, withSourceURL: URL(fileURLWithPath: path))
        } else {
            self.appendLog(runtime, "Не найден файл \(entry)")
        }
        return runtime
    }

    private static func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]), let text = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // ["..."] -> "..."
        return String(text.dropFirst().dropLast())
    }

    // MARK: Events

    @discardableResult
    private func callEmit(_ runtime: WewPluginRuntime, event: String, args: [Any]) -> String? {
        let argsJson = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        guard let emit = runtime.context.objectForKeyedSubscript("__emit"), let result = emit.call(withArguments: [event, argsJson]) else {
            return nil
        }
        return result.isString ? result.toString() : nil
    }

    // Sends an event to every running plugin (for example "menu.open").
    public func dispatchAll(event: String, args: [Any]) {
        self.queue.async {
            self.stateLock.lock()
            let all = self.runtimes.values.sorted(by: { $0.info.manifest.id < $1.info.manifest.id })
            self.stateLock.unlock()
            for runtime in all {
                self.callEmit(runtime, event: event, args: args)
            }
        }
    }

    // Used by plugin pages: a switch/input changed or a button was pressed.
    public func dispatch(pluginId: String, event: String, args: [Any]) {
        self.queue.async {
            self.stateLock.lock()
            let runtime = self.runtimes[pluginId]
            self.stateLock.unlock()
            if let runtime = runtime {
                self.callEmit(runtime, event: event, args: args)
            }
        }
    }

    // MARK: Outgoing message hook

    public var hasOutgoingHooks: Bool {
        self.stateLock.lock()
        defer { self.stateLock.unlock() }
        return !self.outgoingHookPlugins.isEmpty
    }

    // Runs `message.send` handlers of every plugin that declared the "send"
    // permission. Bounded to half a second so a broken plugin can never block
    // sending; on timeout the original text goes out untouched.
    public func transformOutgoingText(_ text: String) -> String {
        self.stateLock.lock()
        let ids = self.outgoingHookPlugins
        self.stateLock.unlock()
        guard !ids.isEmpty else {
            return text
        }

        let box = WewResultBox(text)
        let semaphore = DispatchSemaphore(value: 0)
        self.queue.async {
            var current = text
            for id in ids {
                self.stateLock.lock()
                let runtime = self.runtimes[id]
                self.stateLock.unlock()
                guard let runtime = runtime, (runtime.info.manifest.permissions ?? []).contains("send") else { continue }
                if let result = self.callEmit(runtime, event: "message.send", args: [current]), !result.isEmpty {
                    current = result
                }
            }
            box.set(current)
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + 0.5) == .timedOut {
            return text
        }
        return box.get()
    }

    // MARK: JS prelude

    private static let prelude = """
    var __handlers = {};
    var __httpCallbacks = {};
    var __httpSeq = 0;
    function __json(v) { try { return JSON.stringify(v); } catch (e) { return "null"; } }
    function __parse(s) { if (s === null || s === undefined) { return null; } try { return JSON.parse(s); } catch (e) { return null; } }
    function __emit(ev, argsJson) {
      var args = __parse(argsJson) || [];
      var list = __handlers[ev] || [];
      var result = null;
      for (var i = 0; i < list.length; i++) {
        try {
          var r = list[i].apply(null, args);
          if (ev === 'message.send' && typeof r === 'string') { args[0] = r; result = r; }
        } catch (e) { __log('Ошибка в обработчике ' + ev + ': ' + e); }
      }
      return result;
    }
    function __httpResult(id, status, body) {
      var cb = __httpCallbacks[id]; delete __httpCallbacks[id];
      if (cb) { try { cb(status, body); } catch (e) { __log('Ошибка http-обработчика: ' + e); } }
    }
    var wew = {
      version: '1.0',
      plugin: __plugin,
      log: function () { var a = []; for (var i = 0; i < arguments.length; i++) { a.push(String(arguments[i])); } __log(a.join(' ')); },
      on: function (ev, fn) { if (typeof fn !== 'function') { return; } (__handlers[ev] = __handlers[ev] || []).push(fn); __registered(ev); },
      alert: function (text) { __alert(String(text)); },
      toast: function (text) { __toast(String(text)); },
      storage: {
        get: function (k, d) { var v = __storageGet(String(k)); if (v === null || v === undefined) { return d === undefined ? null : d; } var p = __parse(v); return p === null ? d : p; },
        set: function (k, v) { __storageSet(String(k), __json(v)); },
        remove: function (k) { __storageRemove(String(k)); }
      },
      assets: {
        path: function (name) { return __assetPath(String(name)); },
        list: function () { return __assetList(); }
      },
      ghost: { get: function () { return __ghostGet(); }, set: function (v) { __ghostSet(!!v); } },
      deleted: { setEnabled: function (v) { __deletedSet(!!v); } },
      profile: { get: function () { return __parse(__profileGet()) || {}; }, set: function (o) { __profileSet(__json(o)); } },
      menu: { add: function (item) { __menuAdd(__json(item)); } },
      theme: {
        get: function () { return __parse(__themeGet()) || {}; },
        set: function (o) { __themeSet(__json(o)); },
        reset: function () { __themeReset(); }
      },
      http: { get: function (url, cb) { var id = ++__httpSeq; __httpCallbacks[id] = cb; __httpGet(String(url), id); } }
    };
    """
}
