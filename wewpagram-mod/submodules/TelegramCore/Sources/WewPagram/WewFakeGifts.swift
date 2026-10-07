import Foundation

// Local "visual" gifts. When the mode is on, the gift screens skip the payment and the
// server completely: the gift is only remembered here, on this device. The recipient
// receives nothing and no stars are spent.
public final class WewFakeGifts {
    public static let shared = WewFakeGifts()

    public struct Entry: Codable {
        public var id: String
        public var title: String
        public var kind: String        // "gift" | "unique"
        public var giftId: Int64
        public var slug: String
        public var price: Int64
        public var peerId: Int64
        public var date: Int32
    }

    private let key = "WewPagram.fakeGiftsList"
    private let lock = NSLock()

    private init() {}

    private func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: self.key), let list = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return list
    }

    private func save(_ list: [Entry]) {
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: self.key)
        }
    }

    public func all() -> [Entry] {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load()
    }

    public func add(title: String, kind: String, giftId: Int64, slug: String, price: Int64, peerId: Int64) {
        self.lock.lock()
        var list = self.load()
        let entry = Entry(id: UUID().uuidString, title: title, kind: kind, giftId: giftId, slug: slug, price: price, peerId: peerId, date: Int32(Date().timeIntervalSince1970))
        list.append(entry)
        if list.count > 500 {
            list.removeFirst(list.count - 500)
        }
        self.save(list)
        self.lock.unlock()
        WewPluginManager.shared.dispatchAll(event: "gift.fake", args: [title, price, peerId])
    }

    public func clear() {
        self.lock.lock()
        self.save([])
        self.lock.unlock()
    }

    func jsonList() -> String {
        guard let data = try? JSONEncoder().encode(self.all()), let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }
}
