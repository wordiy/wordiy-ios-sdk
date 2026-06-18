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

        let active = try XCTUnwrap(store.activeBundleURL)
        XCTAssertEqual(result.bundleURL.lastPathComponent, active.lastPathComponent)
        XCTAssertTrue(FileManager.default.fileExists(atPath: active.path))
        let strings = active.appendingPathComponent("Contents/Resources/en.lproj/Localizable.strings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: strings.path))
        XCTAssertEqual(result.version, "9.9.9")
        XCTAssertEqual(store.installedVersion(), "9.9.9")
    }

    /// A re-install must land on a NEW generation path (so `NSBundle` can't serve a cached, stale
    /// bundle without a relaunch) and the previous generation must be cleaned up.
    func testReinstallUsesFreshGenerationAndRemovesOld() throws {
        let store = BundleStore(rootDir: workDir.appendingPathComponent("store", isDirectory: true))
        try store.install(fromExtractedDir: try extractedFixture())
        let first = try XCTUnwrap(store.activeBundleURL)

        // Re-extract (fresh temp) and install again.
        let again = workDir.appendingPathComponent("extract2", isDirectory: true)
        let zipURL = workDir.appendingPathComponent("fixture2.zip")
        try ZipTestSupport.sampleBundleZip().write(to: zipURL)
        try ZipArchiveReader.extract(zipURL: zipURL, to: again)
        try store.install(fromExtractedDir: again)
        let second = try XCTUnwrap(store.activeBundleURL)

        XCTAssertNotEqual(first, second, "a new install must use a fresh path")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: first.path), "old generation should be removed")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
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
