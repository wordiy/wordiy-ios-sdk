import Compression
import Foundation

/// Raw DEFLATE (RFC 1951) decompression via Apple's `Compression` framework.
///
/// ZIP entries with method 8 store a raw DEFLATE stream, which is exactly what `COMPRESSION_ZLIB`
/// decodes (it expects raw deflate, no zlib header). Decompression is one-shot into a buffer sized to
/// the entry's known uncompressed size (from the central directory).
enum Inflate {

    /// Decompresses `data` (raw DEFLATE) to exactly `expectedSize` bytes. Returns `nil` on failure.
    static func inflate(_ data: [UInt8], expectedSize: Int) -> [UInt8]? {
        if expectedSize == 0 { return [] }
        guard !data.isEmpty else { return nil }

        var dst = [UInt8](repeating: 0, count: expectedSize)
        let written = dst.withUnsafeMutableBufferPointer { dstBuf -> Int in
            data.withUnsafeBufferPointer { srcBuf -> Int in
                guard let dstBase = dstBuf.baseAddress, let srcBase = srcBuf.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase, expectedSize,
                    srcBase, srcBuf.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { return nil }
        return dst
    }
}
