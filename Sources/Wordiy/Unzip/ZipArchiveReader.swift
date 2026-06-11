import Foundation

/// Minimal, dependency-free ZIP extractor for the bundle archives Wordiy serves.
///
/// Supports the two methods our server uses — **stored (0)** and **deflate (8)** — by reading the
/// central directory for sizes/offsets and decompressing via ``Inflate``. It is intentionally small
/// and defensive rather than a general-purpose ZIP library:
/// - rejects path-traversal entries (absolute paths or `..` components),
/// - caps entry size to guard against zip bombs,
/// - throws ``WordiyError/unzipFailed(_:)`` on any malformed input (never traps).
enum ZipArchiveReader {

    /// Hard cap on a single entry's uncompressed size (defense against malicious archives).
    private static let maxEntrySize = 64 * 1024 * 1024  // 64 MB

    // Signatures (little-endian on disk).
    private static let eocdSignature: UInt32 = 0x0605_4b50
    private static let centralDirSignature: UInt32 = 0x0201_4b50
    private static let localHeaderSignature: UInt32 = 0x0403_4b50

    /// Extracts the archive at `zipURL` into `destinationDir` (created if needed).
    static func extract(zipURL: URL, to destinationDir: URL) throws {
        let fm = FileManager.default

        guard let raw = try? Data(contentsOf: zipURL), !raw.isEmpty else {
            throw WordiyError.unzipFailed("could not read archive or it is empty")
        }
        let bytes = [UInt8](raw)

        try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let destRoot = destinationDir.standardizedFileURL.path

        let (centralOffset, entryCount) = try findCentralDirectory(in: bytes)

        var cursor = centralOffset
        for _ in 0..<entryCount {
            guard cursor + 46 <= bytes.count,
                readUInt32(bytes, cursor) == centralDirSignature
            else {
                throw WordiyError.unzipFailed("malformed central directory entry")
            }

            let method = readUInt16(bytes, cursor + 10)
            let comp32 = readUInt32(bytes, cursor + 20)
            let uncomp32 = readUInt32(bytes, cursor + 24)
            let nameLen = Int(readUInt16(bytes, cursor + 28))
            let extraLen = Int(readUInt16(bytes, cursor + 30))
            let commentLen = Int(readUInt16(bytes, cursor + 32))
            let loc32 = readUInt32(bytes, cursor + 42)

            guard cursor + 46 + nameLen + extraLen <= bytes.count else {
                throw WordiyError.unzipFailed("truncated central directory")
            }
            let nameBytes = Array(bytes[(cursor + 46)..<(cursor + 46 + nameLen)])
            let name = String(decoding: nameBytes, as: UTF8.self)

            // Resolve Zip64: when a 32-bit size/offset is 0xFFFFFFFF, the real 64-bit value is in the
            // Zip64 extended-information extra field (id 0x0001). The server emits Zip64 even for tiny files.
            let (compressedSize, uncompressedSize, localOffset) = try resolveZip64(
                bytes, extraStart: cursor + 46 + nameLen, extraLen: extraLen,
                comp32: comp32, uncomp32: uncomp32, loc32: loc32)

            try extractEntry(
                name: name, method: method,
                compressedSize: compressedSize, uncompressedSize: uncompressedSize,
                localOffset: localOffset, bytes: bytes,
                destinationDir: destinationDir, destRoot: destRoot, fm: fm)

            cursor += 46 + nameLen + extraLen + commentLen
        }
    }

    // MARK: - Per-entry

    private static func extractEntry(
        name: String, method: UInt16,
        compressedSize: Int, uncompressedSize: Int,
        localOffset: Int, bytes: [UInt8],
        destinationDir: URL, destRoot: String, fm: FileManager
    ) throws {
        // Skip empty names.
        guard !name.isEmpty else { return }

        // Path-traversal guard.
        guard !name.hasPrefix("/"), !name.hasPrefix("\\") else {
            throw WordiyError.unzipFailed("rejected absolute path entry: \(name)")
        }
        let components = name.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else {
            throw WordiyError.unzipFailed("rejected path-traversal entry: \(name)")
        }

        let target = destinationDir.appendingPathComponent(name)
        // Defense in depth: the resolved path must stay inside the destination.
        guard target.standardizedFileURL.path.hasPrefix(destRoot) else {
            throw WordiyError.unzipFailed("entry escapes destination: \(name)")
        }

        // Directory entry.
        if name.hasSuffix("/") {
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
            return
        }

        guard uncompressedSize >= 0, uncompressedSize <= maxEntrySize else {
            throw WordiyError.unzipFailed("entry too large: \(name)")
        }

        // Compute data start from the LOCAL header (its name/extra lengths can differ from central).
        guard localOffset + 30 <= bytes.count,
            readUInt32(bytes, localOffset) == localHeaderSignature
        else {
            throw WordiyError.unzipFailed("bad local header for \(name)")
        }
        let localNameLen = Int(readUInt16(bytes, localOffset + 26))
        let localExtraLen = Int(readUInt16(bytes, localOffset + 28))
        let dataStart = localOffset + 30 + localNameLen + localExtraLen
        guard dataStart + compressedSize <= bytes.count else {
            throw WordiyError.unzipFailed("truncated entry data for \(name)")
        }
        let compressed = Array(bytes[dataStart..<(dataStart + compressedSize)])

        let output: [UInt8]
        switch method {
        case 0:  // stored
            guard compressedSize == uncompressedSize else {
                throw WordiyError.unzipFailed("stored size mismatch for \(name)")
            }
            output = compressed
        case 8:  // deflate
            guard let inflated = Inflate.inflate(compressed, expectedSize: uncompressedSize) else {
                throw WordiyError.unzipFailed("inflate failed for \(name)")
            }
            output = inflated
        default:
            throw WordiyError.unzipFailed("unsupported compression method \(method) for \(name)")
        }

        do {
            try fm.createDirectory(
                at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(output).write(to: target)
        } catch {
            throw WordiyError.io(error)
        }
    }

    // MARK: - EOCD

    private static func findCentralDirectory(in bytes: [UInt8]) throws -> (offset: Int, count: Int) {
        // EOCD is 22 bytes + optional comment. Scan backwards for the signature.
        let minEOCD = 22
        guard bytes.count >= minEOCD else { throw WordiyError.unzipFailed("file too small") }
        let searchStart = max(0, bytes.count - (minEOCD + 0xFFFF))
        var i = bytes.count - minEOCD
        while i >= searchStart {
            if readUInt32(bytes, i) == eocdSignature {
                var count = Int(readUInt16(bytes, i + 10))
                var offset = Int(readUInt32(bytes, i + 16))
                // Full Zip64: the EOCD fields are sentineled; the real values live in the Zip64 EOCD
                // record, located via the Zip64 EOCD locator (20 bytes before this EOCD).
                if offset == 0xFFFF_FFFF || count == 0xFFFF {
                    (offset, count) = try parseZip64EOCD(bytes, eocdIndex: i)
                }
                guard offset >= 0, offset < bytes.count else {
                    throw WordiyError.unzipFailed("invalid central directory offset")
                }
                return (offset, count)
            }
            i -= 1
        }
        throw WordiyError.unzipFailed("end-of-central-directory not found")
    }

    /// Reads the Zip64 EOCD record (via the locator immediately before the regular EOCD) and returns
    /// the real central-directory offset and entry count.
    private static func parseZip64EOCD(_ b: [UInt8], eocdIndex: Int) throws -> (offset: Int, count: Int) {
        // Zip64 EOCD locator: 20 bytes, signature 0x07064b50, located just before the regular EOCD.
        let locIndex = eocdIndex - 20
        guard locIndex >= 0, readUInt32(b, locIndex) == 0x0706_4b50 else {
            throw WordiyError.unzipFailed("zip64 locator not found")
        }
        let eocd64Offset = Int(clamping: readUInt64(b, locIndex + 8))
        // Zip64 EOCD record: signature 0x06064b50; totalEntries @ +32 (8), cdOffset @ +48 (8).
        guard
            eocd64Offset >= 0, eocd64Offset + 56 <= b.count,
            readUInt32(b, eocd64Offset) == 0x0606_4b50
        else {
            throw WordiyError.unzipFailed("zip64 end-of-central-directory not found")
        }
        let count = Int(clamping: readUInt64(b, eocd64Offset + 32))
        let offset = Int(clamping: readUInt64(b, eocd64Offset + 48))
        return (offset, count)
    }

    // MARK: - Zip64

    /// Overrides 32-bit size/offset fields with their 64-bit values from the Zip64 extra field
    /// (header id 0x0001) when they are sentineled to 0xFFFFFFFF.
    private static func resolveZip64(
        _ b: [UInt8], extraStart: Int, extraLen: Int,
        comp32: UInt32, uncomp32: UInt32, loc32: UInt32
    ) throws -> (compressed: Int, uncompressed: Int, localOffset: Int) {
        var compressed = Int(comp32)
        var uncompressed = Int(uncomp32)
        var localOffset = Int(loc32)

        let needsZip64 = comp32 == 0xFFFF_FFFF || uncomp32 == 0xFFFF_FFFF || loc32 == 0xFFFF_FFFF
        guard needsZip64 else { return (compressed, uncompressed, localOffset) }

        let end = extraStart + extraLen
        guard end <= b.count else { throw WordiyError.unzipFailed("truncated extra field") }

        var p = extraStart
        while p + 4 <= end {
            let id = readUInt16(b, p)
            let len = Int(readUInt16(b, p + 2))
            let dataStart = p + 4
            guard dataStart + len <= end else { break }

            if id == 0x0001 {
                // Order: uncompressed (8), compressed (8), local offset (8) — each present only if
                // its 32-bit counterpart was 0xFFFFFFFF.
                var q = dataStart
                if uncomp32 == 0xFFFF_FFFF {
                    guard q + 8 <= dataStart + len else { throw WordiyError.unzipFailed("bad zip64 field") }
                    uncompressed = Int(clamping: readUInt64(b, q)); q += 8
                }
                if comp32 == 0xFFFF_FFFF {
                    guard q + 8 <= dataStart + len else { throw WordiyError.unzipFailed("bad zip64 field") }
                    compressed = Int(clamping: readUInt64(b, q)); q += 8
                }
                if loc32 == 0xFFFF_FFFF {
                    guard q + 8 <= dataStart + len else { throw WordiyError.unzipFailed("bad zip64 field") }
                    localOffset = Int(clamping: readUInt64(b, q)); q += 8
                }
                break
            }
            p = dataStart + len
        }
        return (compressed, uncompressed, localOffset)
    }

    // MARK: - Little-endian readers

    private static func readUInt16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func readUInt32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | (UInt32(b[i + 1]) << 8) | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }

    private static func readUInt64(_ b: [UInt8], _ i: Int) -> UInt64 {
        var v: UInt64 = 0
        for k in 0..<8 { v |= UInt64(b[i + k]) << (8 * k) }
        return v
    }
}
