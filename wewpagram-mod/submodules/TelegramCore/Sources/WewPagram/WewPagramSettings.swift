import Foundation
import SwiftSignalKit

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
        static let fakeGiftsV2       = "WewPagram.fakeGiftsV2"
        static let cloudServerURL    = "WewPagram.cloudServerURL"
        static let cloudApiKey       = "WewPagram.cloudApiKey"
        
        // Deleted messages archive settings
        static let deletedMessagesEnabled         = "WewPagram.deletedMessagesEnabled"
        static let deletedMessagesSaveText        = "WewPagram.deletedMessagesSaveText"
        static let deletedMessagesSaveMedia       = "WewPagram.deletedMessagesSaveMedia"
        static let deletedMessagesSaveAudio       = "WewPagram.deletedMessagesSaveAudio"
        static let deletedMessagesSaveVoiceNotes  = "WewPagram.deletedMessagesSaveVoiceNotes"
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

    // MARK: - Fake gifts (local-only, cosmetic - never sent to the server)
    // Each record keeps the JSON-encoded ProfileGiftsContext.State.StarGift blob
    // plus its own pinned / hidden flags, so fake gifts can be pinned to the
    // top, hidden and deleted individually, exactly like real ones. Ids are
    // always negative so they can never collide with a real saved-gift id.
    public struct FakeGiftRecord: Codable, Equatable {
        public var id: Int64
        public var data: Data
        public var pinned: Bool
        public var hidden: Bool
        public var addedAt: Int32

        public init(id: Int64, data: Data, pinned: Bool, hidden: Bool, addedAt: Int32) {
            self.id = id
            self.data = data
            self.pinned = pinned
            self.hidden = hidden
            self.addedAt = addedAt
        }
    }

    // Bumped on every change so open profile screens can refresh immediately.
    public let fakeGiftsRevision = ValuePromise<Int>(0, ignoreRepeated: false)
    private var fakeGiftsRevisionCounter = 0
    private let fakeGiftsLock = NSLock()
    private var fakeGiftsCache: [FakeGiftRecord]?

    public var fakeGiftRecords: [FakeGiftRecord] {
        get {
            self.fakeGiftsLock.lock()
            defer { self.fakeGiftsLock.unlock() }
            return self.loadFakeGiftsLocked()
        }
        set {
            self.fakeGiftsLock.lock()
            self.storeFakeGiftsLocked(newValue)
            self.fakeGiftsRevisionCounter += 1
            let revision = self.fakeGiftsRevisionCounter
            self.fakeGiftsLock.unlock()
            self.fakeGiftsRevision.set(revision)
        }
    }

    private func loadFakeGiftsLocked() -> [FakeGiftRecord] {
        if let cache = self.fakeGiftsCache {
            return cache
        }
        var records: [FakeGiftRecord] = []
        if let raw = self.defaults.array(forKey: Keys.fakeGiftsV2) as? [Data] {
            let decoder = JSONDecoder()
            records = raw.compactMap { try? decoder.decode(FakeGiftRecord.self, from: $0) }
        } else if let legacy = self.defaults.array(forKey: Keys.fakeGiftsData) as? [Data], !legacy.isEmpty {
            // One-time migration from the old plain-blob format. Old fake gifts
            // were always created pinned and visible.
            for blob in legacy {
                records.append(FakeGiftRecord(id: Self.makeFakeGiftId(existing: records), data: blob, pinned: true, hidden: false, addedAt: Int32(Date().timeIntervalSince1970)))
            }
            self.storeFakeGiftsLocked(records)
            self.defaults.removeObject(forKey: Keys.fakeGiftsData)
            return records
        }
        self.fakeGiftsCache = records
        return records
    }

    private func storeFakeGiftsLocked(_ records: [FakeGiftRecord]) {
        let encoder = JSONEncoder()
        self.defaults.set(records.compactMap { try? encoder.encode($0) }, forKey: Keys.fakeGiftsV2)
        self.fakeGiftsCache = records
    }

    private static func makeFakeGiftId(existing: [FakeGiftRecord]) -> Int64 {
        while true {
            let candidate = -Int64.random(in: 1_000_000 ... (Int64(1) << 50))
            if !existing.contains(where: { $0.id == candidate }) {
                return candidate
            }
        }
    }

    public func isFakeGiftId(_ id: Int64) -> Bool {
        guard id < 0 else { return false }
        return self.fakeGiftRecords.contains(where: { $0.id == id })
    }

    // New gifts go to the top of the profile, pinned and visible.
    public func addFakeGiftData(_ data: Data) {
        var records = self.fakeGiftRecords
        records.append(FakeGiftRecord(id: Self.makeFakeGiftId(existing: records), data: data, pinned: true, hidden: false, addedAt: Int32(Date().timeIntervalSince1970)))
        self.fakeGiftRecords = records
    }

    public func setFakeGiftPinned(id: Int64, pinned: Bool) {
        var records = self.fakeGiftRecords
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].pinned = pinned
        self.fakeGiftRecords = records
    }

    public func setFakeGiftHidden(id: Int64, hidden: Bool) {
        var records = self.fakeGiftRecords
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].hidden = hidden
        self.fakeGiftRecords = records
    }

    public func removeFakeGift(id: Int64) {
        var records = self.fakeGiftRecords
        records.removeAll(where: { $0.id == id })
        self.fakeGiftRecords = records
    }

    public func removeAllFakeGifts() {
        self.fakeGiftRecords = []
    }

    // MARK: - Cloud (own server + userbot)
    // The server and userbot are self-hosted by the user: the userbot keeps
    // receiving messages while the app is suspended and the app can reach the
    // same archive through this URL / key.
    public var cloudServerURL: String {
        get { self.defaults.string(forKey: Keys.cloudServerURL) ?? "" }
        set { self.defaults.set(newValue, forKey: Keys.cloudServerURL) }
    }

    public var cloudApiKey: String {
        get { self.defaults.string(forKey: Keys.cloudApiKey) ?? "" }
        set { self.defaults.set(newValue, forKey: Keys.cloudApiKey) }
    }

    public var isCloudConfigured: Bool {
        return !self.cloudServerURL.isEmpty && !self.cloudApiKey.isEmpty
    }

    // MARK: - Deleted messages archive (AyuGram-style: capture before real
    // deletion happens, show in a separate local-only viewer. We never
    // interfere with the actual deletion - this is purely additive with
    // respect to the real sync pipeline, so it can't break message sync.
    //
    // The archive lives in a file (not UserDefaults), written atomically with
    // "until first user authentication" protection, so it is saved and
    // readable at any moment - online, offline, in the background, or while
    // the device is locked. Media is kept alive by the synthetic copy of the
    // message that stays in the chat (see WewDeletedArchive.swift).

    public struct DeletedMessageRecord: Codable {
        public var peerId: Int64
        public var authorId: Int64?
        public var authorName: String?
        public var text: String
        public var timestamp: Int32
        public var deletedAt: Int32
        public var mediaType: String?        // Human readable, e.g. "Фото", "Видео"

        public init(peerId: Int64, authorId: Int64?, authorName: String?, text: String, timestamp: Int32, deletedAt: Int32, mediaType: String? = nil) {
            self.peerId = peerId
            self.authorId = authorId
            self.authorName = authorName
            self.text = text
            self.timestamp = timestamp
            self.deletedAt = deletedAt
            self.mediaType = mediaType
        }
    }

    private static let maxDeletedMessageRecords = 5000
    private static let legacyDeletedMessagesKey = "WewPagram.deletedMessages"

    private let archiveQueue = DispatchQueue(label: "WewPagram.deletedArchive")
    private var archiveCache: [DeletedMessageRecord]?

    private static let archiveFileURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WewPagram", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true, attributes: nil)
        return base.appendingPathComponent("deleted-messages.json")
    }()

    // Archive configuration
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

    // Must be called on archiveQueue.
    private func loadArchiveLocked() -> [DeletedMessageRecord] {
        if let cache = self.archiveCache {
            return cache
        }
        var records: [DeletedMessageRecord] = []
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: Self.archiveFileURL), let decoded = try? decoder.decode([DeletedMessageRecord].self, from: data) {
            records = decoded
        }
        // One-time migration of the old UserDefaults archive.
        if let legacy = self.defaults.array(forKey: Self.legacyDeletedMessagesKey) as? [Data] {
            let migrated = legacy.compactMap { try? decoder.decode(DeletedMessageRecord.self, from: $0) }
            records.append(contentsOf: migrated)
            records.sort(by: { $0.deletedAt < $1.deletedAt })
            self.defaults.removeObject(forKey: Self.legacyDeletedMessagesKey)
            self.writeArchiveLocked(records)
        }
        self.archiveCache = records
        return records
    }

    private func writeArchiveLocked(_ records: [DeletedMessageRecord]) {
        guard let data = try? JSONEncoder().encode(records) else {
            return
        }
        try? data.write(to: Self.archiveFileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public func archiveDeletedMessage(_ record: DeletedMessageRecord) {
        guard self.deletedMessagesEnabled else { return }
        self.archiveQueue.sync {
            var current = self.loadArchiveLocked()
            current.append(record)
            if current.count > Self.maxDeletedMessageRecords {
                current.removeFirst(current.count - Self.maxDeletedMessageRecords)
            }
            self.archiveCache = current
            self.writeArchiveLocked(current)
        }
    }

    public func deletedMessages() -> [DeletedMessageRecord] {
        return self.archiveQueue.sync { self.loadArchiveLocked() }
    }

    public func clearDeletedMessages() {
        self.archiveQueue.sync {
            self.archiveCache = []
            self.writeArchiveLocked([])
        }
    }
}
