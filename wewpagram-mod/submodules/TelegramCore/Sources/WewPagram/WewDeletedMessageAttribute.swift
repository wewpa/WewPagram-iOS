import Foundation
import Postbox

// Marks a locally-synthesized copy of a message that was deleted by the
// other side. Carries the deletion timestamp (the synthetic message's own
// `timestamp` gets used for chat-list positioning and matches the original
// send time, so this is purely extra metadata for future UI use).
public class WewDeletedMessageAttribute: MessageAttribute {
    public let deletedAt: Int32

    public var associatedMessageIds: [MessageId] = []

    public init(deletedAt: Int32) {
        self.deletedAt = deletedAt
    }

    required public init(decoder: PostboxDecoder) {
        self.deletedAt = decoder.decodeInt32ForKey("d", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt32(self.deletedAt, forKey: "d")
    }
}
