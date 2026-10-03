import Foundation
import Compression

// Minimal read-only ZIP reader (stored + deflate). iOS has no public unzip
// API, and plugins are small, so a compact reader based on the central
// directory is enough. ZIP64 and encryption are intentionally unsupported.
public enum WewZipError: Error {
    case invalid
    case unsupported
    case tooLarge
}

public struct WewZipEntry {
    public let name: String
    let method: UInt16
    let compressedSize: Int
    let uncompressedSize: Int
    let localHeaderOffset: Int

    public var isDirectory: Bool {
        return self.name.hasSuffix("/")
    }
}

public final class WewZipArchive {
    private let bytes: [UInt8]
    public private(set) var entries: [WewZipEntry] = []

    public static let maxEntrySize = 8 * 1024 * 1024
    public static let maxTotalSize = 24 * 1024 * 1024
    public static let maxEntryCount = 400

    public init(data: Data) throws {
        self.bytes = [UInt8](data)
        try self.parse()
    }

    private func u16(_ offset: Int) -> Int {
        return Int(self.bytes[offset]) | (Int(self.bytes[offset + 1]) << 8)
    }

    private func u32(_ offset: Int) -> Int {
        return Int(self.bytes[offset]) | (Int(self.bytes[offset + 1]) << 8) | (Int(self.bytes[offset + 2]) << 16) | (Int(self.bytes[offset + 3]) << 24)
    }

    private func parse() throws {
        let count = self.bytes.count
        guard count >= 22 else {
            throw WewZipError.invalid
        }

        // End of central directory record: search backwards for its signature.
        var eocd = -1
        var position = count - 22
        let lowerBound = max(0, count - 22 - 65535)
        while position >= lowerBound {
            if self.bytes[position] == 0x50 && self.bytes[position + 1] == 0x4b && self.bytes[position + 2] == 0x05 && self.bytes[position + 3] == 0x06 {
                eocd = position
                break
            }
            position -= 1
        }
        guard eocd >= 0 else {
            throw WewZipError.invalid
        }

        let totalEntries = self.u16(eocd + 10)
        let directoryOffset = self.u32(eocd + 16)
        if totalEntries == 0xFFFF || directoryOffset == 0xFFFFFFFF {
            throw WewZipError.unsupported
        }
        guard totalEntries <= WewZipArchive.maxEntryCount else {
            throw WewZipError.tooLarge
        }

        var cursor = directoryOffset
        var total = 0
        for _ in 0 ..< totalEntries {
            guard cursor + 46 <= count, self.u32(cursor) == 0x02014b50 else {
                throw WewZipError.invalid
            }
            let flags = self.u16(cursor + 8)
            let method = self.u16(cursor + 10)
            let compressedSize = self.u32(cursor + 20)
            let uncompressedSize = self.u32(cursor + 24)
            let nameLength = self.u16(cursor + 28)
            let extraLength = self.u16(cursor + 30)
            let commentLength = self.u16(cursor + 32)
            let localOffset = self.u32(cursor + 42)
            guard cursor + 46 + nameLength <= count else {
                throw WewZipError.invalid
            }
            if flags & 0x1 != 0 {
                throw WewZipError.unsupported
            }
            let nameBytes = Array(self.bytes[(cursor + 46) ..< (cursor + 46 + nameLength)])
            let name = String(bytes: nameBytes, encoding: .utf8) ?? String(bytes: nameBytes, encoding: .isoLatin1) ?? ""

            if uncompressedSize > WewZipArchive.maxEntrySize {
                throw WewZipError.tooLarge
            }
            total += uncompressedSize
            if total > WewZipArchive.maxTotalSize {
                throw WewZipError.tooLarge
            }

            self.entries.append(WewZipEntry(name: name, method: UInt16(method), compressedSize: compressedSize, uncompressedSize: uncompressedSize, localHeaderOffset: localOffset))
            cursor += 46 + nameLength + extraLength + commentLength
        }
    }

    public func read(_ entry: WewZipEntry) throws -> Data {
        let offset = entry.localHeaderOffset
        guard offset + 30 <= self.bytes.count, self.u32(offset) == 0x04034b50 else {
            throw WewZipError.invalid
        }
        let nameLength = self.u16(offset + 26)
        let extraLength = self.u16(offset + 28)
        let start = offset + 30 + nameLength + extraLength
        let end = start + entry.compressedSize
        guard start >= 0, end <= self.bytes.count else {
            throw WewZipError.invalid
        }

        switch entry.method {
        case 0:
            return Data(self.bytes[start ..< end])
        case 8:
            if entry.uncompressedSize == 0 {
                return Data()
            }
            var output = [UInt8](repeating: 0, count: entry.uncompressedSize)
            let compressedSize = entry.compressedSize
            let written: Int = self.bytes.withUnsafeBufferPointer { source in
                return output.withUnsafeMutableBufferPointer { destination in
                    return compression_decode_buffer(destination.baseAddress!, destination.count, source.baseAddress! + start, compressedSize, nil, COMPRESSION_ZLIB)
                }
            }
            guard written == entry.uncompressedSize else {
                throw WewZipError.invalid
            }
            return Data(output)
        default:
            throw WewZipError.unsupported
        }
    }
}
