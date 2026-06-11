import Foundation

/// Calls `GET /api/v1/bundles/check` and decodes the response.
///
/// Stateless and `Sendable` so it can run off the main actor. All failures are mapped to ``WordiyError``.
struct BundleCheckClient: Sendable {

    /// Staging base URL. Single place to switch environments later.
    static let defaultBaseURL = URL(string: "https://stg.wordiy.dev/api/v1")!

    let baseURL: URL
    let session: URLSessionProtocol

    init(baseURL: URL = BundleCheckClient.defaultBaseURL, session: URLSessionProtocol = URLSession.shared) {
        self.baseURL = baseURL
        self.session = session
    }

    /// Inputs needed to build the request — snapshotted from `Wordiy` on the main actor.
    struct Request: Sendable {
        var platform: String
        var environment: String
        var currentVersion: String
        var apiKey: String
    }

    func check(_ input: Request) async throws -> BundleCheckResponse {
        guard
            var components = URLComponents(
                url: baseURL.appendingPathComponent("bundles/check"),
                resolvingAgainstBaseURL: false)
        else {
            throw WordiyError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "platform", value: input.platform),
            URLQueryItem(name: "environment", value: input.environment),
            URLQueryItem(name: "current_version", value: input.currentVersion),
        ]
        guard let url = components.url else { throw WordiyError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(input.apiKey, forHTTPHeaderField: "Api-Key")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw WordiyError.network(error)
        }

        guard let http = response as? HTTPURLResponse else {
            throw WordiyError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? JSONDecoder.wordiy().decode(APIErrorBody.self, from: data))?.message
            throw WordiyError.server(statusCode: http.statusCode, message: message)
        }

        do {
            return try JSONDecoder.wordiy().decode(BundleCheckResponse.self, from: data)
        } catch {
            throw WordiyError.invalidResponse
        }
    }
}
