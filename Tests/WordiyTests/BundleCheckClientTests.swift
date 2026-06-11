import XCTest

@testable import Wordiy

final class BundleCheckClientTests: XCTestCase {

    private func request() -> BundleCheckClient.Request {
        .init(platform: "ios", environment: "production", currentVersion: "1.0.0", apiKey: "cdl_test")
    }

    func testParsesUpdateAvailable() async throws {
        let stub = StubURLSession()
        stub.checkData = Data(
            """
            {"update_available":true,"bundle":{"version":"1.1.0","download_url":"https://x/y.zip","checksum":"abc","size_bytes":123,"metadata":{}}}
            """.utf8)
        let client = BundleCheckClient(session: stub)

        let response = try await client.check(request())
        XCTAssertTrue(response.updateAvailable)
        XCTAssertEqual(response.bundle?.version, "1.1.0")
        XCTAssertEqual(response.bundle?.downloadUrl, "https://x/y.zip")
        XCTAssertEqual(response.bundle?.sizeBytes, 123)
    }

    func testParsesNoUpdate() async throws {
        let stub = StubURLSession()
        stub.checkData = Data(#"{"update_available":false,"bundle":null}"#.utf8)
        let response = try await BundleCheckClient(session: stub).check(request())
        XCTAssertFalse(response.updateAvailable)
        XCTAssertNil(response.bundle)
    }

    func testServerErrorMapsWithMessage() async throws {
        let stub = StubURLSession()
        stub.checkStatus = 401
        stub.checkData = Data(
            #"{"message":"invalid api key","error":"UNAUTHORIZED","statusCode":401}"#.utf8)
        do {
            _ = try await BundleCheckClient(session: stub).check(request())
            XCTFail("expected throw")
        } catch let WordiyError.server(statusCode, message) {
            XCTAssertEqual(statusCode, 401)
            XCTAssertEqual(message, "invalid api key")
        }
    }

    func testMalformedJSONMapsToInvalidResponse() async throws {
        let stub = StubURLSession()
        stub.checkData = Data("{ not json".utf8)
        do {
            _ = try await BundleCheckClient(session: stub).check(request())
            XCTFail("expected throw")
        } catch {
            guard case WordiyError.invalidResponse = error else {
                return XCTFail("expected .invalidResponse, got \(error)")
            }
        }
    }

    func testTransportErrorMapsToNetwork() async throws {
        let stub = StubURLSession()
        stub.checkError = URLError(.notConnectedToInternet)
        do {
            _ = try await BundleCheckClient(session: stub).check(request())
            XCTFail("expected throw")
        } catch {
            guard case WordiyError.network = error else {
                return XCTFail("expected .network, got \(error)")
            }
        }
    }
}
