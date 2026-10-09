import Foundation
import Postbox
import SwiftSignalKit

// Local message edit. The text is changed only in this device's database, nothing is sent
// to Telegram and the other side never sees it. The mark below is appended to the text
// of every locally edited message and cannot be switched off.
public let wewEditedMarker = "✎ Отредактировано в WewPagram"

public func wewStripEditedMarker(_ text: String) -> String {
    var result = text
    while let range = result.range(of: wewEditedMarker, options: .backwards), result[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result = String(result[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return result
}

// The original text of every locally edited message is kept by the app itself, so that
// "restore" always brings back the real text and can never be used to write text without the mark.
private let wewOriginalsKey = "WewPagram.localEditOriginals"
private let wewOriginalsLock = NSLock()

private func wewOriginal(for key: String) -> String? {
    wewOriginalsLock.lock()
    defer { wewOriginalsLock.unlock() }
    return (UserDefaults.standard.dictionary(forKey: wewOriginalsKey) as? [String: String])?[key]
}

private func wewSetOriginal(_ value: String?, for key: String) {
    wewOriginalsLock.lock()
    defer { wewOriginalsLock.unlock() }
    var dictionary = (UserDefaults.standard.dictionary(forKey: wewOriginalsKey) as? [String: String]) ?? [:]
    dictionary[key] = value
    if dictionary.count > 1000, let first = dictionary.keys.first {
        dictionary.removeValue(forKey: first)
    }
    UserDefaults.standard.set(dictionary, forKey: wewOriginalsKey)
}

public func wewLocalEditMessage(account: Account, id: MessageId, text: String) -> Signal<Void, NoError> {
    let base = wewStripEditedMarker(text.trimmingCharacters(in: .whitespacesAndNewlines))
    return account.postbox.transaction { transaction -> Void in
        transaction.updateMessage(id, update: { currentMessage in
            let storageKey = "\(id.peerId.toInt64())_\(id.namespace)_\(id.id)"
            if !currentMessage.text.contains(wewEditedMarker) {
                wewSetOriginal(currentMessage.text, for: storageKey)
            }
            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            let prefix = base + "\n\n"
            let newText = prefix + wewEditedMarker
            var attributes = currentMessage.attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            let start = prefix.utf16.count
            let end = newText.utf16.count
            attributes.append(TextEntitiesMessageAttribute(entities: [MessageTextEntity(range: start ..< end, type: .Italic)]))
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: newText, attributes: attributes, media: currentMessage.media))
        })
    }
}

// Brings back the text the message had before the first local edit.
public func wewLocalRestoreMessage(account: Account, id: MessageId) -> Signal<Void, NoError> {
    let storageKey = "\(id.peerId.toInt64())_\(id.namespace)_\(id.id)"
    return account.postbox.transaction { transaction -> Void in
        guard let original = wewOriginal(for: storageKey) else {
            return
        }
        transaction.updateMessage(id, update: { currentMessage in
            if !currentMessage.text.contains(wewEditedMarker) {
                return .skip
            }
            let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
            let attributes = currentMessage.attributes.filter { !($0 is TextEntitiesMessageAttribute) }
            return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: original, attributes: attributes, media: currentMessage.media))
        })
        wewSetOriginal(nil, for: storageKey)
    }
}
