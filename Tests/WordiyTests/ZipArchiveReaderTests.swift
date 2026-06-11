import XCTest

@testable import Wordiy

final class ZipArchiveReaderTests: XCTestCase {

    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = ZipTestSupport.tempDir()
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    func testExtractsDeflateFixture() throws {
        let zipData = try ZipTestSupport.sampleBundleZip()
        let zipURL = workDir.appendingPathComponent("fixture.zip")
        try zipData.write(to: zipURL)

        let dest = workDir.appendingPathComponent("out", isDirectory: true)
        try ZipArchiveReader.extract(zipURL: zipURL, to: dest)

        let strings = dest.appendingPathComponent(
            "wordiy.bundle/Contents/Resources/en.lproj/Localizable.strings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: strings.path))
        let content = try String(contentsOf: strings, encoding: .utf8)
        XCTAssertTrue(content.contains("\"greeting\" = \"Hello\";"))

        let info = dest.appendingPathComponent("wordiy.bundle/Contents/Info.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: info.path))
    }

    func testExtractsZip64Fixture() throws {
        // Real-server format: 32-bit sizes sentineled to 0xFFFFFFFF, real sizes in the Zip64 extra field.
        let zipData = try ZipTestSupport.sampleBundleZip64()
        let zipURL = workDir.appendingPathComponent("z64.zip")
        try zipData.write(to: zipURL)

        let dest = workDir.appendingPathComponent("z64out", isDirectory: true)
        try ZipArchiveReader.extract(zipURL: zipURL, to: dest)

        let strings = dest.appendingPathComponent(
            "wordiy.bundle/Contents/Resources/en.lproj/Localizable.strings")
        XCTAssertTrue(FileManager.default.fileExists(atPath: strings.path))
        XCTAssertTrue(
            try String(contentsOf: strings, encoding: .utf8).contains("\"greeting\" = \"Hello\";"))
    }

    func testExtractsStoredZip() throws {
        let data = ZipTestSupport.makeStoredZip(entries: [
            ("hello.txt", Array("hi there".utf8))
        ])
        let zipURL = workDir.appendingPathComponent("stored.zip")
        try data.write(to: zipURL)

        let dest = workDir.appendingPathComponent("out", isDirectory: true)
        try ZipArchiveReader.extract(zipURL: zipURL, to: dest)

        let file = dest.appendingPathComponent("hello.txt")
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hi there")
    }

    func testRejectsPathTraversal() throws {
        let data = ZipTestSupport.makeStoredZip(entries: [
            ("../escape.txt", Array("evil".utf8))
        ])
        let zipURL = workDir.appendingPathComponent("evil.zip")
        try data.write(to: zipURL)
        let dest = workDir.appendingPathComponent("out", isDirectory: true)

        XCTAssertThrowsError(try ZipArchiveReader.extract(zipURL: zipURL, to: dest)) { error in
            guard case WordiyError.unzipFailed = error else {
                return XCTFail("expected .unzipFailed, got \(error)")
            }
        }
        // Nothing should have been written outside the destination.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: workDir.appendingPathComponent("escape.txt").path))
    }

    func testRejectsGarbageArchive() throws {
        let zipURL = workDir.appendingPathComponent("garbage.zip")
        try Data("not a zip at all".utf8).write(to: zipURL)
        let dest = workDir.appendingPathComponent("out", isDirectory: true)
        XCTAssertThrowsError(try ZipArchiveReader.extract(zipURL: zipURL, to: dest))
    }
}
