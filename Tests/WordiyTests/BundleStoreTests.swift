import XCTest

@testable import Wordiy

final class BundleStoreTests: XCTestCase {

    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = ZipTestSupport.tempDir()
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    /// Extracts the fixture zip into a temp dir and returns the extraction directory.
    private func extractedFixture() throws -> URL {
        let zipURL = workDir.appendingPathComponent("fixture.zip")
        try ZipTestSupport.sampleBundleZip().write(to: zipURL)
        let dest = workDir.appendingPathComponent("extract", isDirectory: true)
        try ZipArchiveReader.extract(zipURL: zipURL, to: dest)
        return dest
    }

    func testInstallPlacesBundleAndReadsVersion() throws {
        let extracted = try extractedFixture()
        let store = BundleStore(rootDir: workDir.appendingPathComponent("store", isDirectory: true))

        let result = try store.install(fromExtractedDir: extracted)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.activeBundleURL.path))
        let strings = store.activeBundleURL.appendingPathComponent(
            "Contents/Resources/en.lproj/Localizable.strings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: strings.path))
        XCTAssertEqual(result.version, "9.9.9")
        XCTAssertEqual(store.installedVersion(), "9.9.9")
    }

    func testReinstallReplacesAtomically() throws {
        let store = BundleStore(rootDir: workDir.appendingPathComponent("store", isDirectory: true))
        try store.install(fromExtractedDir: try extractedFixture())
        // Re-extract (fresh temp) and install again — should not throw and should still resolve.
        let again = workDir.appendingPathComponent("extract2", isDirectory: true)
        let zipURL = workDir.appendingPathComponent("fixture2.zip")
        try ZipTestSupport.sampleBundleZip().write(to: zipURL)
        try ZipArchiveReader.extract(zipURL: zipURL, to: again)
        XCTAssertNoThrow(try store.install(fromExtractedDir: again))
        XCTAssertEqual(store.installedVersion(), "9.9.9")
    }

    func testMissingBundleThrows() throws {
        let store = BundleStore(rootDir: workDir.appendingPathComponent("store", isDirectory: true))
        let empty = workDir.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try store.install(fromExtractedDir: empty)) { error in
            guard case WordiyError.bundleNotFoundInArchive = error else {
                return XCTFail("expected .bundleNotFoundInArchive, got \(error)")
            }
        }
    }
}
