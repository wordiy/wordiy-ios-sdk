import Foundation

@testable import Wordiy

/// Stub `URLSessionProtocol` for offline tests.
///
/// `data(for:)` services the `/bundles/check` request; `download(for:)` writes `downloadData` to a temp
/// file and returns it (mimicking `URLSession.download`).
final class StubURLSession: URLSessionProtocol, @unchecked Sendable {

    var checkData: Data = Data()
    var checkStatus: Int = 200
    var checkError: (any Error)?

    var downloadData: Data = Data()
    var downloadStatus: Int = 200
    var downloadError: (any Error)?

    /// The most recent check request URL (for asserting query params like current_version).
    private(set) var lastCheckURL: URL?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lastCheckURL = request.url
        if let checkError { throw checkError }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://stg.wordiy.dev")!,
            statusCode: checkStatus, httpVersion: nil, headerFields: nil)!
        return (checkData, response)
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        if let downloadError { throw downloadError }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://ota-bundles-staging.wordiy.dev")!,
            statusCode: downloadStatus, httpVersion: nil, headerFields: nil)!
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".zip")
        try downloadData.write(to: tmp)
        return (tmp, response)
    }
}
