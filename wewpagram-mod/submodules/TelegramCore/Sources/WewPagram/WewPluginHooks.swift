import Foundation
import Postbox

// Applied at the top of enqueueMessages(): lets plugins with the "send"
// permission rewrite the text of outgoing messages. Entities (bold, links...)
// are dropped when the text changed, because their offsets would no longer match.
func wewTransformOutgoingMessages(_ messages: [EnqueueMessage]) -> [EnqueueMessage] {
    guard WewPluginManager.shared.hasOutgoingHooks else {
        return messages
    }
    return messages.map { message in
        guard case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets) = message, !text.isEmpty else {
            return message
        }
        let newText = WewPluginManager.shared.transformOutgoingText(text)
        if newText == text {
            return message
        }
        let newAttributes = attributes.filter { !($0 is TextEntitiesMessageAttribute) }
        return .message(text: newText, attributes: newAttributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
    }
}
