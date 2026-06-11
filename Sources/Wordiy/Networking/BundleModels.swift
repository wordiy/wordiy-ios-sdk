import Foundation

/// Response from `GET /api/v1/bundles/check`.
///
/// The decision to update is keyed off ``updateAvailable``; ``bundle`` is treated as optional because
/// the live API has been observed to return a populated bundle even when `update_available` is `false`.
struct BundleCheckResponse: Decodable, Sendable {
    var updateAvailable: Bool
    var bundle: BundleInfo?
}

/// The bundle descriptor returned by the check endpoint.
struct BundleInfo: Decodable, Sendable {
    var version: String?
    /// JSON `download_url` (→ `downloadUrl` under `.convertFromSnakeCase`).
    var downloadUrl: String?
    /// Integrity checksum. Not verified yet (format is in flux: spec says SHA-256 hex, live data looks
    /// like base64 MD5). Captured for when verification is enabled.
    var checksum: String?
    var sizeBytes: Int?
    // `metadata` is intentionally not modeled (free-form object); ignored on decode.
}

/// Structured error body returned by the API on 4xx responses.
struct APIErrorBody: Decodable, Sendable {
    var message: String?
    var error: String?
    var statusCode: Int?
}

extension JSONDecoder {
    /// Decoder configured for the Wordiy API (snake_case → camelCase).
    static func wordiy() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
