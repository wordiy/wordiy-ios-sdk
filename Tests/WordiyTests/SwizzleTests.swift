import XCTest

@testable import Wordiy

@MainActor
final class SwizzleTests: XCTestCase {

    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = ZipTestSupport.tempDir()
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // CRITICAL: a leaked swizzle would corrupt NSLocalizedString for every other test class.
        let w = Wordiy.shared
        w.deswizzleMainBundle()
        WordiyBundleSwizzler.shared.setOTABundle(nil)
        w.preferredLanguageOverride = nil
        w.urlSession = URLSession.shared
        w.store = try? BundleStore()
        try? FileManager.default.removeItem(at: workDir)
    }

    /// Installs the Zip64 fixture (`en.lproj`: greeting=Hello, farewell=Goodbye) into a temp store via
    /// the stubbed pipeline, then pins the resolved language to `en` for determinism (the xctest host's
    /// `Bundle.main` has no `.lproj`). Returns the store so callers can reach `activeBundleURL`.
    @discardableResult
    private func installFixtureAndSwizzle(_ name: String) async throws -> BundleStore {
        let stub = StubURLSession()
        stub.checkData = Data(
            #"{"update_available":true,"bundle":{"version":"9.9.9","download_url":"https://ota/x.zip","size_bytes":1720}}"#
                .utf8)
        stub.downloadData = try ZipTestSupport.sampleBundleZip64()

        let w = Wordiy.shared
        w.setToken("cdl_test")
        w.currentVersion = "1.0.0"
        w.localizationType = .production
        w.urlSession = stub
        let store = BundleStore(rootDir: workDir.appendingPathComponent(name, isDirectory: true))
        w.store = store

        let updated = try await w.checkForUpdates()
        XCTAssertTrue(updated)

        w.preferredLanguageOverride = "en"
        w.swizzleMainBundle()
        return store
    }

    func testSwizzledMainBundleReturnsOTAValue() async throws {
        try await installFixtureAndSwizzle("hit")
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "greeting", value: nil, table: nil), "Hello")
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "farewell", value: nil, table: nil), "Goodbye")
    }

    func testMissingKeyFallsBackWithoutRecursion() async throws {
        try await installFixtureAndSwizzle("miss")
        // Absent from OTA and from the resource-less host main bundle → returns the key.
        // Reaching this assertion at all proves the fallback used the original IMP (no recursion crash).
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "__nope__", value: nil, table: nil), "__nope__")
        // A non-empty `value:` is honored per the NSBundle contract.
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "__nope__", value: "DEF", table: nil), "DEF")
    }

    func testTableIsDelegatedToFoundation() async throws {
        try await installFixtureAndSwizzle("table")
        // Default table resolves the OTA value...
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "greeting", value: nil, table: "Localizable"),
            "Hello")
        // ...a table the OTA bundle doesn't ship (no Main.strings) misses OTA and falls through.
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "greeting", value: nil, table: "Main"), "greeting")
    }

    func testDeswizzleRestoresOriginal() async throws {
        let w = Wordiy.shared
        try await installFixtureAndSwizzle("deswizzle")
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "greeting", value: nil, table: nil), "Hello")

        w.deswizzleMainBundle()
        // Host main bundle has no resources, so the genuine original returns the key.
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "greeting", value: nil, table: nil), "greeting")
    }

    func testSwizzleDeswizzleAreIdempotent() async throws {
        let w = Wordiy.shared
        try await installFixtureAndSwizzle("idem")
        w.swizzleMainBundle()  // second swizzle is a no-op
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "greeting", value: nil, table: nil), "Hello")

        w.deswizzleMainBundle()
        w.deswizzleMainBundle()  // second deswizzle is a no-op
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "greeting", value: nil, table: nil), "greeting")
    }

    func testConcurrentLookupsAreThreadSafe() async throws {
        try await installFixtureAndSwizzle("threads")
        // Hammer the swizzled lookup from many threads at once: NSLocalizedString runs off-main, so the
        // lock-protected bundle read must hold up. Run under `swift test --sanitize=thread` to assert it.
        DispatchQueue.concurrentPerform(iterations: 10_000) { _ in
            XCTAssertEqual(
                Bundle.main.localizedString(forKey: "greeting", value: nil, table: nil), "Hello")
        }
    }

    func testNonMainBundleIsNotRouted() async throws {
        try await installFixtureAndSwizzle("nonmain")
        // Bundle.module is neither Bundle.main nor the OTA bundle, so it is never routed through OTA;
        // it has no "greeting" key, so it returns the key.
        XCTAssertEqual(
            Bundle.module.localizedString(forKey: "greeting", value: nil, table: nil), "greeting")
        // Sanity: Bundle.main IS routed.
        XCTAssertEqual(
            Bundle.main.localizedString(forKey: "greeting", value: nil, table: nil), "Hello")
    }
}
