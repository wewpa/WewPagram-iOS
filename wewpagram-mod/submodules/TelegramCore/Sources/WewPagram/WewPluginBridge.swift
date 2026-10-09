import Foundation
import Postbox
import SwiftSignalKit

public struct WewContextItem {
    public let pluginId: String
    public let id: String
    public let title: String
    public let onlyEdited: Bool   // show only on messages that were edited locally
}

// Glue between plugins and the chat screen: menu items a plugin adds to the message
// context menu, a native text prompt and the local message edit. The screen side
// installs the handlers right before a plugin item is fired.
public final class WewPluginBridge {
    public static let shared = WewPluginBridge()

    private let lock = NSLock()
    private var items: [WewContextItem] = []

    public var promptHandler: ((String, String?, String, @escaping (String?) -> Void) -> Void)?
    public var editHandler: ((MessageId, String) -> Void)?
    public var restoreHandler: ((MessageId) -> Void)?

    private init() {}

    func addItem(_ item: WewContextItem) {
        self.lock.lock()
        self.items.removeAll(where: { $0.pluginId == item.pluginId && $0.id == item.id })
        if self.items.filter({ $0.pluginId == item.pluginId }).count < 4 {
            self.items.append(item)
        }
        self.lock.unlock()
    }

    func clearAll() {
        self.lock.lock()
        self.items = []
        self.lock.unlock()
    }

    public func contextItems() -> [WewContextItem] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.items
    }

    public static func messageKey(_ id: MessageId) -> String {
        return "\(id.peerId.toInt64())_\(id.namespace)_\(id.id)"
    }

    static func messageId(fromKey key: String) -> MessageId? {
        let parts = key.split(separator: "_").map(String.init)
        guard parts.count == 3, let peer = Int64(parts[0]), let namespace = Int32(parts[1]), let id = Int32(parts[2]) else {
            return nil
        }
        return MessageId(peerId: PeerId(peer), namespace: namespace, id: id)
    }

    public func fire(item: WewContextItem, id: MessageId, text: String, outgoing: Bool) {
        let payload: [String: Any] = [
            "key": WewPluginBridge.messageKey(id),
            "text": wewStripEditedMarker(text),
            "outgoing": outgoing,
            "edited": text.contains(wewEditedMarker)
        ]
        WewPluginManager.shared.dispatch(pluginId: item.pluginId, event: "contextmenu", args: [item.id, payload])
    }
}
