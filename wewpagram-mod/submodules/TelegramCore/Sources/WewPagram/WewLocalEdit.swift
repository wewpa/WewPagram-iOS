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

public func wewLocalEditMessage(account: Account, id: MessageId, text: String) -> Signal<Void, NoError> {
    let base = wewStripEditedMarker(text.trimmingCharacters(in: .whitespacesAndNewlines))
    return account.postbox.transaction { transaction -> Void in
        transaction.updateMessage(id, update: { currentMessage in
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
