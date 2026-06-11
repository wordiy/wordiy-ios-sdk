import XCTest

@testable import Wordiy

@MainActor
final class CheckForUpdatesTests: XCTestCase {

    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = ZipTestSupport.tempDir()
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    private func freshStore(_ name: String) -> BundleStore {
        BundleStore(rootDir: workDir.appendingPathComponent(name, isDirectory: true))
    }

    func testHappyPathDownloadsUnzipsAndInstalls() async throws {
        let stub = StubURLSession()
        stub.checkData = Data(
            """
            {"update_available":true,"bundle":{"version":"9.9.9","download_url":"https://ota/x.zip","size_bytes":1720}}
            """.utf8)
        // Use the Zip64 fixture — matches the real server's archive format.
        stub.downloadData = try ZipTestSupport.sampleBundleZip64()

        let w = Wordiy.shared
        w.setProjectID("proj", token: "cdl_test")
        w.currentVersion = "1.0.0"
        w.localizationType = .production
        w.urlSession = stub
        let store = freshStore("store-happy")
        w.store = store

        let updated = try await w.checkForUpdates()

        XCTAssertTrue(updated)
        XCTAssertEqual(w.installedBundleVersion, "9.9.9")
        let strings = store.activeBundleURL.appendingPathComponent(
            "Contents/Resources/en.lproj/Localizable.strings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: strings.path))
    }

    func testReportsInstalledVersionOnSubsequentCheck() async throws {
        // 1st check: app baseline 1.0.0, server has an update → installs 9.9.9 (fixture version).
        let stub = StubURLSession()
        stub.checkData = Data(
            """
            {"update_available":true,"bundle":{"version":"9.9.9","download_url":"https://ota/x.zip"}}
            """.utf8)
        stub.downloadData = try ZipTestSupport.sampleBundleZip64()

        let w = Wordiy.shared
        w.setProjectID("proj", token: "cdl_test")
        w.currentVersion = "1.0.0"
        w.urlSession = stub
        w.store = freshStore("store-report")

        _ = try await w.checkForUpdates()
        XCTAssertEqual(w.installedBundleVersion, "9.9.9")
        // reportedVersion now reflects the installed bundle, not the 1.0.0 baseline.
        XCTAssertEqual(w.reportedVersion, "9.9.9")

        // 2nd check: server says up to date; the SDK must report the INSTALLED version, not 1.0.0.
        stub.checkData = Data(#"{"update_available":false,"bundle":null}"#.utf8)
        let updated = try await w.checkForUpdates()

        XCTAssertFalse(updated)
        let sent = URLComponents(url: stub.lastCheckURL!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "current_version" })?.value
        XCTAssertEqual(sent, "9.9.9", "second check must report the installed bundle version")
    }

    func testNoUpdateIsNoOp() async throws {
        let stub = StubURLSession()
        stub.checkData = Data(#"{"update_available":false,"bundle":null}"#.utf8)

        let w = Wordiy.shared
        w.setProjectID("proj", token: "cdl_test")
        w.currentVersion = "1.0.0"
        w.urlSession = stub
        let store = freshStore("store-noop")
        w.store = store

        let updated = try await w.checkForUpdates()
        XCTAssertFalse(updated)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.activeBundleURL.path))
    }

    func testMissingCurrentVersionThrows() async throws {
        let w = Wordiy.shared
        w.setProjectID("proj", token: "cdl_test")
        w.currentVersion = ""
        w.store = freshStore("store-missing")
        do {
            _ = try await w.checkForUpdates()
            XCTFail("expected throw")
        } catch {
            guard case WordiyError.missingCurrentVersion = error else {
                return XCTFail("expected .missingCurrentVersion, got \(error)")
            }
        }
    }

    func testServerErrorIsThrownNotCrashed() async throws {
        let stub = StubURLSession()
        stub.checkStatus = 401
        stub.checkData = Data(#"{"message":"bad key","statusCode":401}"#.utf8)

        let w = Wordiy.shared
        w.setProjectID("proj", token: "cdl_bad")
        w.currentVersion = "1.0.0"
        w.urlSession = stub
        w.store = freshStore("store-401")
        do {
            _ = try await w.checkForUpdates()
            XCTFail("expected throw")
        } catch let WordiyError.server(statusCode, _) {
            XCTAssertEqual(statusCode, 401)
        }
    }
}
