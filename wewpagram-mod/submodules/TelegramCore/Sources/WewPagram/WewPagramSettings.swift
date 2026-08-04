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
        static let fakeNftUsername   = "WewPagram.fakeNftUsername"
        static let fakeNftPrice      = "WewPagram.fakeNftPrice"
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
        Keys.fakeNftUsername,
        Keys.fakeNftPrice,
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
        if let v = self.fakeNftUsername { dict[Keys.fakeNftUsername] = v }
        if let v = self.fakeNftPrice    { dict[Keys.fakeNftPrice]    = v }
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
        for key in [Keys.fakePhoneNumber, Keys.fakeUsername, Keys.fakeNftUsername, Keys.fakeNftPrice] {
            if let value = snapshot[key] as? String, !value.isEmpty {
                self.defaults.set(value, forKey: key)
                applied += 1
            }
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

    public var fakeNftUsername: String? {
        get { self.defaults.string(forKey: Keys.fakeNftUsername) }
        set { self.defaults.set(newValue, forKey: Keys.fakeNftUsername) }
    }

    public var fakeNftPrice: String? {
        get { self.defaults.string(forKey: Keys.fakeNftPrice) }
        set { self.defaults.set(newValue, forKey: Keys.fakeNftPrice) }
    }
}
