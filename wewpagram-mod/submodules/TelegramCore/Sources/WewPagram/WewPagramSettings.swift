import Foundation

// Central switchboard for WewPagram mod features.
// UserDefaults-backed so it's readable from anywhere in the app without
// threading a settings object through every call site.
//
// Ghost mode now exposes a per-activity switch (online presence, typing,
// video / voice recording and uploading, photo uploading, read receipts).
// The legacy `isGhostModeEnabled` accessor is preserved as an aggregate
// read/write: reading it returns true iff every sub-toggle is on; writing
// it flips every sub-toggle in lockstep. Older call sites keep working.
public final class WewPagramSettings {
    public static let shared = WewPagramSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let disableOnlineStatus         = "WewPagram.disableOnlineStatus"
        static let disableTyping               = "WewPagram.disableTyping"
        static let disableRecordingVideo       = "WewPagram.disableRecordingVideo"
        static let disableUploadingVideo       = "WewPagram.disableUploadingVideo"
        static let disableVoiceRecording       = "WewPagram.disableVoiceRecording"
        static let disableVoiceUploading       = "WewPagram.disableVoiceUploading"
        static let disableUploadingPhoto       = "WewPagram.disableUploadingPhoto"
        static let disableReadReceipts         = "WewPagram.disableReadReceipts"

        // Legacy master switch; kept only for one-time migration.
        static let legacyGhostMode             = "WewPagram.ghostModeEnabled"

        static let fakePhoneNumber   = "WewPagram.fakePhoneNumber"
        static let fakeUsername      = "WewPagram.fakeUsername"
        static let fakeNftEntries    = "WewPagram.fakeNftEntries"

        static let fakeRatingEnabled = "WewPagram.fakeRatingEnabled"
        static let fakeRatingLevel   = "WewPagram.fakeRatingLevel"
        static let fakeRatingStars   = "WewPagram.fakeRatingStars"
        static let injectedFakeStars = "WewPagram.injectedFakeStars"
        static let fakeGiftsData     = "WewPagram.fakeGiftsData"
        
        // Deleted messages archive settings
        static let deletedMessagesEnabled         = "WewPagram.deletedMessagesEnabled"
        static let deletedMessagesSaveText        = "WewPagram.deletedMessagesSaveText"
        static let deletedMessagesSaveMedia       = "WewPagram.deletedMessagesSaveMedia"
        static let deletedMessagesSaveAudio       = "WewPagram.deletedMessagesSaveAudio"
        static let deletedMessagesSaveVoiceNotes  = "WewPagram.deletedMessagesSaveVoiceNotes"
        static let deletedMessagesOfflineMode     = "WewPagram.deletedMessagesOfflineMode"
    }

    private init() {
        // One-shot migration: if the legacy master flag was set, propagate its
        // value to every new sub-toggle, then clear it so we never migrate twice.
        if self.defaults.object(forKey: Keys.legacyGhostMode) != nil {
            let legacyValue = self.defaults.bool(forKey: Keys.legacyGhostMode)
            for key in Self.ghostSubKeys {
                self.defaults.set(legacyValue, forKey: key)
            }
            self.defaults.removeObject(forKey: Keys.legacyGhostMode)
        }
        
        // Initialize deleted messages settings with defaults
        if self.defaults.object(forKey: Keys.deletedMessagesEnabled) == nil {
            self.defaults.set(true, forKey: Keys.deletedMessagesEnabled)
            self.defaults.set(true, forKey: Keys.deletedMessagesSaveText)
            self.defaults.set(true, forKey: Keys.deletedMessagesSaveMedia)
            self.defaults.set(true, forKey: Keys.deletedMessagesSaveAudio)
            self.defaults.set(true, forKey: Keys.deletedMessagesSaveVoiceNotes)
            self.defaults.set(true, forKey: Keys.deletedMessagesOfflineMode)
        }
    }

    private static let ghostSubKeys: [String] = [
        Keys.disableOnlineStatus,
        Keys.disableTyping,
        Keys.disableRecordingVideo,
        Keys.disableUploadingVideo,
        Keys.disableVoiceRecording,
        Keys.disableVoiceUploading,
        Keys.disableUploadingPhoto,
        Keys.disableReadReceipts,
    ]

    // MARK: - Ghost-mode sub-toggles

    public var disableOnlineStatus: Bool {
        get { self.defaults.bool(forKey: Keys.disableOnlineStatus) }
        set { self.defaults.set(newValue, forKey: Keys.disableOnlineStatus) }
    }

    public var disableTyping: Bool {
        get { self.defaults.bool(forKey: Keys.disableTyping) }
        set { self.defaults.set(newValue, forKey: Keys.disableTyping) }
    }

    public var disableRecordingVideo: Bool {
        get { self.defaults.bool(forKey: Keys.disableRecordingVideo) }
        set { self.defaults.set(newValue, forKey: Keys.disableRecordingVideo) }
    }

    public var disableUploadingVideo: Bool {
        get { self.defaults.bool(forKey: Keys.disableUploadingVideo) }
        set { self.defaults.set(newValue, forKey: Keys.disableUploadingVideo) }
    }

    public var disableVoiceRecording: Bool {
        get { self.defaults.bool(forKey: Keys.disableVoiceRecording) }
        set { self.defaults.set(newValue, forKey: Keys.disableVoiceRecording) }
    }

    public var disableVoiceUploading: Bool {
        get { self.defaults.bool(forKey: Keys.disableVoiceUploading) }
        set { self.defaults.set(newValue, forKey: Keys.disableVoiceUploading) }
    }

    public var disableUploadingPhoto: Bool {
        get { self.defaults.bool(forKey: Keys.disableUploadingPhoto) }
        set { self.defaults.set(newValue, forKey: Keys.disableUploadingPhoto) }
    }

    public var disableReadReceipts: Bool {
        get { self.defaults.bool(forKey: Keys.disableReadReceipts) }
        set { self.defaults.set(newValue, forKey: Keys.disableReadReceipts) }
    }

    // MARK: - Legacy aggregate accessor
    // Reads as "everything ghosted"; writes propagate to every sub-toggle.
    public var isGhostModeEnabled: Bool {
        get {
            for key in Self.ghostSubKeys where !self.defaults.bool(forKey: key) {
                return false
            }
            return true
        }
        set {
            for key in Self.ghostSubKeys {
                self.defaults.set(newValue, forKey: key)
            }
        }
    }

    // MARK: - Bulk operations

    // Keys that are eligible for export / import / reset. Legacy migration key
    // is deliberately excluded — we don't want to bring it back after a reset.
    private static let managedKeys: [String] = ghostSubKeys + [
        Keys.fakePhoneNumber,
        Keys.fakeUsername,
        Keys.fakeNftEntries,
    ]

    // Wipe every WewPagram-managed key back to its default (unset/false).
    public func resetAll() {
        for key in Self.managedKeys {
            self.defaults.removeObject(forKey: key)
        }
    }

    // Snapshot of every managed key. Booleans stay as Bool, strings as String,
    // missing entries are omitted. JSON-serialisable by construction.
    public func exportSnapshot() -> [String: Any] {
        var dict: [String: Any] = [:]
        for key in Self.ghostSubKeys {
            dict[key] = self.defaults.bool(forKey: key)
        }
        if let v = self.fakePhoneNumber { dict[Keys.fakePhoneNumber] = v }
        if let v = self.fakeUsername    { dict[Keys.fakeUsername]    = v }
        dict[Keys.fakeNftEntries] = self.fakeNftEntries.map { ["username": $0.username, "price": $0.price] }
        return dict
    }

    // Overwrite settings from a snapshot dictionary. Keys not present in the
    // snapshot are cleared, so importing an old export doesn't leak stale
    // values from a newer state. Unknown keys are ignored — future-proof.
    // Returns true when at least one recognised key was applied.
    @discardableResult
    public func importSnapshot(_ snapshot: [String: Any]) -> Bool {
        var applied = 0
        // Wipe managed state first so absent keys revert to defaults.
        for key in Self.managedKeys {
            self.defaults.removeObject(forKey: key)
        }
        for key in Self.ghostSubKeys {
            if let value = snapshot[key] as? Bool {
                self.defaults.set(value, forKey: key)
                applied += 1
            } else if let value = snapshot[key] as? NSNumber {
                self.defaults.set(value.boolValue, forKey: key)
                applied += 1
            }
        }
        for key in [Keys.fakePhoneNumber, Keys.fakeUsername] {
            if let value = snapshot[key] as? String, !value.isEmpty {
                self.defaults.set(value, forKey: key)
                applied += 1
            }
        }
        if let raw = snapshot[Keys.fakeNftEntries] as? [[String: String]] {
            self.fakeNftEntries = raw.compactMap { entry in
                guard let username = entry["username"], !username.isEmpty else { return nil }
                return FakeNftEntry(username: username, price: entry["price"] ?? "")
            }
            applied += 1
        }
        return applied > 0
    }

    // MARK: - Fake identity display (local-only, cosmetic — never sent to the server)
    public var fakePhoneNumber: String? {
        get { self.defaults.string(forKey: Keys.fakePhoneNumber) }
        set { self.defaults.set(newValue, forKey: Keys.fakePhoneNumber) }
    }

    public var fakeUsername: String? {
        get { self.defaults.string(forKey: Keys.fakeUsername) }
        set { self.defaults.set(newValue, forKey: Keys.fakeUsername) }
    }

    // MARK: - Fake NFT (collectible) usernames — additive, shown only on the
    // read-only "My Profile" screen, alongside real additional usernames.
    public struct FakeNftEntry: Equatable {
        public var username: String
        public var price: String

        public init(username: String, price: String) {
            self.username = username
            self.price = price
        }
    }

    public var fakeNftEntries: [FakeNftEntry] {
        get {
            guard let raw = self.defaults.array(forKey: Keys.fakeNftEntries) as? [[String: String]] else {
                return []
            }
            return raw.compactMap { entry in
                guard let username = entry["username"], !username.isEmpty else { return nil }
                return FakeNftEntry(username: username, price: entry["price"] ?? "")
            }
        }
        set {
            let raw = newValue.map { ["username": $0.username, "price": $0.price] }
            self.defaults.set(raw, forKey: Keys.fakeNftEntries)
        }
    }

    public func addFakeNftEntry(username: String, price: String) {
        guard !username.isEmpty else { return }
        var entries = self.fakeNftEntries
        entries.append(FakeNftEntry(username: username, price: price))
        self.fakeNftEntries = entries
    }

    public func removeFakeNftEntry(at index: Int) {
        var entries = self.fakeNftEntries
        guard entries.indices.contains(index) else { return }
        entries.remove(at: index)
        self.fakeNftEntries = entries
    }

    // MARK: - Fake profile rating (local-only, cosmetic — never sent to the server)
    // Mirrors Telegram's own TelegramStarRating shape (level / stars), so the
    // caller can build a TelegramStarRating straight from these values.
    public var fakeRatingEnabled: Bool {
        get { self.defaults.bool(forKey: Keys.fakeRatingEnabled) }
        set { self.defaults.set(newValue, forKey: Keys.fakeRatingEnabled) }
    }

    public var fakeRatingLevel: Int {
        get { self.defaults.object(forKey: Keys.fakeRatingLevel) as? Int ?? 1 }
        set { self.defaults.set(max(0, min(newValue, 999)), forKey: Keys.fakeRatingLevel) }
    }

    // Clamped well below Int32/Int64 formatter edge cases (Telegram's own
    // Stars amounts are nowhere near this large in practice).
    public var fakeRatingStars: Int {
        get { self.defaults.object(forKey: Keys.fakeRatingStars) as? Int ?? 0 }
        set { self.defaults.set(max(0, min(newValue, 999_999_999)), forKey: Keys.fakeRatingStars) }
    }

    // Tracks how much fake balance we've already injected into the real
    // StarsContext, so toggling/editing the fake amount can add just the
    // delta instead of compounding on every change.
    public var injectedFakeStars: Int {
        get { self.defaults.object(forKey: Keys.injectedFakeStars) as? Int ?? 0 }
        set { self.defaults.set(newValue, forKey: Keys.injectedFakeStars) }
    }

    // Raw JSON-encoded ProfileGiftsContext.State.StarGift blobs (built once
    // when the user taps "Добавить подарок", reusing a real gift's artwork).
    // Decoded and merged into the displayed gift grid at render time — never
    // touches the real synced Postbox state, so nothing overwrites it.
    public var fakeGiftsData: [Data] {
        get { self.defaults.array(forKey: Keys.fakeGiftsData) as? [Data] ?? [] }
        set { self.defaults.set(newValue, forKey: Keys.fakeGiftsData) }
    }

    public func addFakeGiftData(_ data: Data) {
        var current = self.fakeGiftsData
        current.append(data)
        self.fakeGiftsData = current
    }

    // MARK: - Deleted messages archive (AyuGram-style: capture before real
    // deletion happens, show in a separate local-only viewer. We never
    // interfere with the actual deletion — this is purely additive/read-only
    // with respect to the real sync pipeline, so it can't break message sync.
    // Extended with media/audio support and offline mode.
    
    public struct DeletedMessageRecord: Codable {
        public var peerId: Int64
        public var authorId: Int64?
        public var authorName: String?
        public var text: String
        public var timestamp: Int32
        public var deletedAt: Int32
        
        // Media and audio archival
        public var mediaData: Data?          // Encoded media (photo, video, doc)
        public var audioData: Data?          // Encoded audio (MP3, etc)
        public var voiceNoteData: Data?      // Voice message OGG
        public var mediaType: String?        // Type identifier (photo, video, audio, voice)

        public init(peerId: Int64, authorId: Int64?, authorName: String?, text: String, timestamp: Int32, deletedAt: Int32, mediaData: Data? = nil, audioData: Data? = nil, voiceNoteData: Data? = nil, mediaType: String? = nil) {
            self.peerId = peerId
            self.authorId = authorId
            self.authorName = authorName
            self.text = text
            self.timestamp = timestamp
            self.deletedAt = deletedAt
            self.mediaData = mediaData
            self.audioData = audioData
            self.voiceNoteData = voiceNoteData
            self.mediaType = mediaType
        }
    }

    private static let maxDeletedMessageRecords = 2000

    // Deleted messages archive configuration
    public var deletedMessagesEnabled: Bool {
        get { self.defaults.bool(forKey: Keys.deletedMessagesEnabled) }
        set { self.defaults.set(newValue, forKey: Keys.deletedMessagesEnabled) }
    }
    
    public var deletedMessagesSaveText: Bool {
        get { self.defaults.bool(forKey: Keys.deletedMessagesSaveText) }
        set { self.defaults.set(newValue, forKey: Keys.deletedMessagesSaveText) }
    }
    
    public var deletedMessagesSaveMedia: Bool {
        get { self.defaults.bool(forKey: Keys.deletedMessagesSaveMedia) }
        set { self.defaults.set(newValue, forKey: Keys.deletedMessagesSaveMedia) }
    }
    
    public var deletedMessagesSaveAudio: Bool {
        get { self.defaults.bool(forKey: Keys.deletedMessagesSaveAudio) }
        set { self.defaults.set(newValue, forKey: Keys.deletedMessagesSaveAudio) }
    }
    
    public var deletedMessagesSaveVoiceNotes: Bool {
        get { self.defaults.bool(forKey: Keys.deletedMessagesSaveVoiceNotes) }
        set { self.defaults.set(newValue, forKey: Keys.deletedMessagesSaveVoiceNotes) }
    }
    
    // Offline mode: continue archiving messages even when not connected
    public var deletedMessagesOfflineMode: Bool {
        get { self.defaults.bool(forKey: Keys.deletedMessagesOfflineMode) }
        set { self.defaults.set(newValue, forKey: Keys.deletedMessagesOfflineMode) }
    }

    public var deletedMessagesData: [Data] {
        get { self.defaults.array(forKey: "WewPagram.deletedMessages") as? [Data] ?? [] }
        set { self.defaults.set(newValue, forKey: "WewPagram.deletedMessages") }
    }

    public func archiveDeletedMessage(_ record: DeletedMessageRecord) {
        // Check if archiving is enabled globally
        guard deletedMessagesEnabled else { return }
        
        // Determine what should be archived based on content type and settings
        var shouldArchive = false
        
        if !record.text.isEmpty && deletedMessagesSaveText {
            shouldArchive = true
        } else if record.mediaData != nil && deletedMessagesSaveMedia {
            shouldArchive = true
        } else if record.audioData != nil && deletedMessagesSaveAudio {
            shouldArchive = true
        } else if record.voiceNoteData != nil && deletedMessagesSaveVoiceNotes {
            shouldArchive = true
        }
        
        guard shouldArchive else { return }
        guard let encoded = try? JSONEncoder().encode(record) else { return }
        
        var current = self.deletedMessagesData
        current.append(encoded)
        if current.count > Self.maxDeletedMessageRecords {
            current.removeFirst(current.count - Self.maxDeletedMessageRecords)
        }
        self.deletedMessagesData = current
    }

    public func deletedMessages() -> [DeletedMessageRecord] {
        let decoder = JSONDecoder()
        return self.deletedMessagesData.compactMap { try? decoder.decode(DeletedMessageRecord.self, from: $0) }
    }

    public func clearDeletedMessages() {
        self.defaults.removeObject(forKey: "WewPagram.deletedMessages")
    }
}
