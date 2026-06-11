import Foundation
import os

/// Downloads a bundle archive from a (signed) URL to a temporary file.
///
/// Validates the HTTP status and that the payload is non-empty. Checksum verification is intentionally
/// skipped for now (the checksum format is in flux); `sizeBytes` mismatches are logged, not fatal.
struct BundleDownloader: Sendable {

    let session: URLSessionProtocol

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    /// Downloads `url` and returns a temporary file URL holding the archive.
    /// The caller owns the returned file and should remove it when done.
    func download(from url: URL, expectedSize: Int?) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let tempURL: URL
        let response: URLResponse
        do {
            (tempURL, response) = try await session.download(for: request)
        } catch {
            throw WordiyError.network(error)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw WordiyError.downloadFailed(statusCode: http.statusCode)
        }

        let size = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int) ?? nil
        guard let size, size > 0 else {
            throw WordiyError.emptyDownload
        }
        if let expectedSize, expectedSize != size {
            Logger.wordiy.warning(
                "Downloaded size \(size) bytes != expected \(expectedSize) bytes (continuing; checksum not yet enforced)")
        }

        return tempURL
    }
}

extension Logger {
    /// Lightweight internal logger, quiet by default (visible via Console.app / os_log).
    static let wordiy = Logger(subsystem: "dev.wordiy.sdk", category: "Wordiy")
}
