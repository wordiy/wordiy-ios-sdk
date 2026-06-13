import XCTest

@testable import Wordiy

@MainActor
final class WordiyTests: XCTestCase {

    func testDefaults() {
        let sut = Wordiy.shared
        // platform is hardcoded and read-only.
        XCTAssertEqual(sut.platform, "ios")
        // localizationType defaults to production.
        XCTAssertEqual(sut.localizationType, .production)
    }

    func testSetTokenStoresTokenAndInitializes() {
        let sut = Wordiy.shared
        sut.setToken("demo-token")
        XCTAssertEqual(sut.token, "demo-token")
        XCTAssertTrue(sut.isInitialized, "the token alone is enough to initialize")
    }

    func testSetProjectIDIsOptional() {
        let sut = Wordiy.shared
        // projectID can be set independently; it is not required and does not gate initialization.
        sut.setProjectID("demo-project-id")
        XCTAssertEqual(sut.projectID, "demo-project-id")
    }

    func testSettingsRoundTrip() {
        let sut = Wordiy.shared
        sut.localizationType = .staging
        sut.currentVersion = "v1.0.0"
        XCTAssertEqual(sut.localizationType, .staging)
        XCTAssertEqual(sut.currentVersion, "v1.0.0")
        // Reset so other tests/runs see the default again.
        sut.localizationType = .production
    }

    func testLocalizationTypeRawValues() {
        XCTAssertEqual(Wordiy.LocalizationType.production.rawValue, "production")
        XCTAssertEqual(Wordiy.LocalizationType.staging.rawValue, "staging")
        XCTAssertEqual(Wordiy.LocalizationType.development.rawValue, "development")
    }
}
