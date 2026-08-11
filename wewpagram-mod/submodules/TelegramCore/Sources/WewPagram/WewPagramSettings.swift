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
}
