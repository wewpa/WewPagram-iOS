import Foundation
import Postbox

// Builds local "ghost" copies of messages that the other side is deleting,
// archives their text and keeps their media alive.
//
// Why media survives: the ghost copy carries the very same Media objects, so
// Postbox keeps them referenced, and the caller skips removing their files
// from the MediaBox (see `preservedMediaIds`). Everything is stored in
// Postbox / on disk, so none of it needs a network connection.
public struct WewDeletedCopies {
    public var messages: [StoreMessage] = []
    public var preservedMediaIds: Set<MediaId> = []
}

private enum WewMediaKind {
    case media
    case audio
    case voice
}

private func wewMediaKind(_ media: Media) -> WewMediaKind? {
    if media is TelegramMediaImage {
        return .media
    }
    if let file = media as? TelegramMediaFile {
        for attribute in file.attributes {
            if case let .Audio(isVoice, _, _, _, _) = attribute {
                return isVoice ? .voice : .audio
            }
        }
        return .media
    }
    return nil
}

private func wewMediaTitle(_ media: Media) -> String? {
    if media is TelegramMediaImage {
        return "Фото"
    }
    if let file = media as? TelegramMediaFile {
        for attribute in file.attributes {
            switch attribute {
            case let .Audio(isVoice, _, _, _, _):
                return isVoice ? "Голосовое сообщение" : "Аудио"
            case let .Video(_, _, flags, _, _, _):
                return flags.contains(.instantRoundVideo) ? "Видеосообщение" : "Видео"
            case .Sticker:
                return "Стикер"
            case .Animated:
                return "GIF"
            default:
                break
            }
        }
        return "Файл"
    }
    return nil
}

public func wewPrepareDeletedCopies(transaction: Transaction, ids: [MessageId]) -> WewDeletedCopies {
    var result = WewDeletedCopies()
    let settings = WewPagramSettings.shared
    guard settings.deletedMessagesEnabled else {
        return result
    }
    let now = Int32(Date().timeIntervalSince1970)

    for id in ids {
        guard let message = transaction.getMessage(id) else {
            continue
        }

        var keptMedia: [Media] = []
        var mediaTitles: [String] = []
        for media in message.media {
            switch wewMediaKind(media) {
            case .media?:
                if settings.deletedMessagesSaveMedia { keptMedia.append(media) }
            case .audio?:
                if settings.deletedMessagesSaveAudio { keptMedia.append(media) }
            case .voice?:
                if settings.deletedMessagesSaveVoiceNotes { keptMedia.append(media) }
            case nil:
                // Webpage previews, polls, locations... travel with the text.
                if settings.deletedMessagesSaveText { keptMedia.append(media) }
            }
            if keptMedia.last === media, let title = wewMediaTitle(media) {
                mediaTitles.append(title)
            }
        }

        let hasText = !message.text.isEmpty && settings.deletedMessagesSaveText
        guard hasText || !keptMedia.isEmpty else {
            continue
        }

        let text = hasText ? message.text : ""
        let mediaType = mediaTitles.isEmpty ? nil : mediaTitles.joined(separator: ", ")

        settings.archiveDeletedMessage(WewPagramSettings.DeletedMessageRecord(
            peerId: id.peerId.toInt64(),
            authorId: message.author?.id.toInt64(),
            authorName: message.author?.debugDisplayTitle,
            text: text,
            timestamp: message.timestamp,
            deletedAt: now,
            mediaType: mediaType
        ))

        // Same numeric id under the Local namespace - the real message is
        // about to disappear, so nothing collides, and Postbox places the copy
        // at the right chronological spot through its timestamp.
        let localId = MessageId(peerId: id.peerId, namespace: Namespaces.Message.Local, id: id.id)
        if transaction.getMessage(localId) == nil {
            for media in keptMedia {
                if let mediaId = media.id {
                    result.preservedMediaIds.insert(mediaId)
                }
            }
            result.messages.append(StoreMessage(
                id: localId,
                customStableId: nil,
                globallyUniqueId: nil,
                groupingKey: nil,
                threadId: message.threadId,
                timestamp: message.timestamp,
                flags: StoreMessageFlags(message.flags),
                tags: [],
                globalTags: [],
                localTags: [],
                forwardInfo: nil,
                authorId: message.author?.id,
                text: message.text,
                attributes: [WewDeletedMessageAttribute(deletedAt: now)],
                media: keptMedia
            ))
        }
    }
    return result
}
