import Foundation
import XCTest

/// Helpers for the unzip/storage tests.
enum ZipTestSupport {

    /// Loads the committed deflate fixture (`Resources/sample-bundle.zip`) as data.
    static func sampleBundleZip() throws -> Data {
        try fixture("sample-bundle")
    }

    /// Loads the committed **Zip64** fixture (`Resources/sample-bundle-zip64.zip`) — matches the real
    /// server's archive format (32-bit size fields sentineled, real sizes in the Zip64 extra field).
    static func sampleBundleZip64() throws -> Data {
        try fixture("sample-bundle-zip64")
    }

    private static func fixture(_ name: String) throws -> Data {
        guard
            let url = Bundle.module.url(
                forResource: name, withExtension: "zip", subdirectory: "Resources")
        else {
            throw XCTSkip("\(name).zip fixture not found in test bundle")
        }
        return try Data(contentsOf: url)
    }

    /// Builds a minimal **stored** (uncompressed) ZIP from `entries`. Enough to exercise the reader's
    /// stored path and its path-traversal guard without depending on a zip writer.
    static func makeStoredZip(entries: [(name: String, data: [UInt8])]) -> Data {
        var local = [UInt8]()
        var central = [UInt8]()
        var offsets = [Int]()

        for entry in entries {
            offsets.append(local.count)
            let nameBytes = Array(entry.name.utf8)
            let size = UInt32(entry.data.count)

            // Local file header.
            local.append(contentsOf: le32(0x0403_4b50))
            local.append(contentsOf: le16(20))  // version needed
            local.append(contentsOf: le16(0))  // flags
            local.append(contentsOf: le16(0))  // method = stored
            local.append(contentsOf: le16(0))  // mod time
            local.append(contentsOf: le16(0))  // mod date
            local.append(contentsOf: le32(0))  // crc32 (reader ignores)
            local.append(contentsOf: le32(size))  // compressed size
            local.append(contentsOf: le32(size))  // uncompressed size
            local.append(contentsOf: le16(UInt16(nameBytes.count)))
            local.append(contentsOf: le16(0))  // extra len
            local.append(contentsOf: nameBytes)
            local.append(contentsOf: entry.data)
        }

        let centralStart = local.count
        for (i, entry) in entries.enumerated() {
            let nameBytes = Array(entry.name.utf8)
            let size = UInt32(entry.data.count)
            central.append(contentsOf: le32(0x0201_4b50))
            central.append(contentsOf: le16(20))  // version made by
            central.append(contentsOf: le16(20))  // version needed
            central.append(contentsOf: le16(0))  // flags
            central.append(contentsOf: le16(0))  // method = stored
            central.append(contentsOf: le16(0))  // mod time
            central.append(contentsOf: le16(0))  // mod date
            central.append(contentsOf: le32(0))  // crc32
            central.append(contentsOf: le32(size))  // compressed
            central.append(contentsOf: le32(size))  // uncompressed
            central.append(contentsOf: le16(UInt16(nameBytes.count)))
            central.append(contentsOf: le16(0))  // extra
            central.append(contentsOf: le16(0))  // comment
            central.append(contentsOf: le16(0))  // disk start
            central.append(contentsOf: le16(0))  // internal attrs
            central.append(contentsOf: le32(0))  // external attrs
            central.append(contentsOf: le32(UInt32(offsets[i])))  // local header offset
            central.append(contentsOf: nameBytes)
        }

        var eocd = [UInt8]()
        eocd.append(contentsOf: le32(0x0605_4b50))
        eocd.append(contentsOf: le16(0))  // disk
        eocd.append(contentsOf: le16(0))  // disk w/ CD
        eocd.append(contentsOf: le16(UInt16(entries.count)))
        eocd.append(contentsOf: le16(UInt16(entries.count)))
        eocd.append(contentsOf: le32(UInt32(central.count)))
        eocd.append(contentsOf: le32(UInt32(centralStart)))
        eocd.append(contentsOf: le16(0))  // comment len

        return Data(local + central + eocd)
    }

    static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wordiy-test-\(UUID().uuidString)", isDirectory: true)
        return url
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xff), UInt8(v >> 8)] }
    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8((v >> 24) & 0xff)]
    }
}
