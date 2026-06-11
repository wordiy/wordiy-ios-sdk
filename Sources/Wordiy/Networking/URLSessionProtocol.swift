import Foundation

/// Minimal seam over `URLSession` so networking can be stubbed in tests.
///
/// Mirrors the approach used by other OTA SDKs (e.g. Tolgee's `FetchCdnService`): the production code
/// uses `URLSession.shared`, while tests inject a fake that returns canned responses.
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func download(for request: URLRequest) async throws -> (URL, URLResponse)
}

extension URLSession: URLSessionProtocol {
    // Explicit witnesses: URLSession's async APIs are `data(for:delegate:)` / `download(for:delegate:)`
    // (with a defaulted delegate), which don't directly satisfy the no-delegate protocol requirements.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }

    public func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        try await download(for: request, delegate: nil)
    }
}
