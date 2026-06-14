import XCTest

@testable import Wordiy

@MainActor
final class LocalizationUpdatesTests: XCTestCase {

    private var workDir: URL!

    override func setUpWithError() throws {
        workDir = ZipTestSupport.tempDir()
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        let w = Wordiy.shared
        w._resetLocalizationSubscribersForTesting()
        w.setLanguage(nil)
        w.defaults = .standard
        w.urlSession = URLSession.shared
        w.store = try? BundleStore()
        try? FileManager.default.removeItem(at: workDir)
    }

    private func freshStore(_ name: String) -> BundleStore {
        BundleStore(rootDir: workDir.appendingPathComponent(name, isDirectory: true))
    }

    /// Subscribes on the main actor and fulfills `exp` on the first event. The stream registers its
    /// continuation synchronously when `localizationUpdates()` is evaluated, so a later event is never
    /// missed once the returned task has started.
    private func observeFirstEvent(fulfilling exp: XCTestExpectation) -> Task<Void, Never> {
        Task { @MainActor in
            for await _ in Wordiy.shared.localizationUpdates() {
                exp.fulfill()
                break
            }
        }
    }

    func testFiresOnLanguageChange() async throws {
        let w = Wordiy.shared
        w.setLanguage(nil)  // known starting point

        let received = expectation(description: "emits on language change")
        let task = observeFirstEvent(fulfilling: received)
        await Task.yield()  // let the subscriber register + reach `for await`

        w.setLanguage("ar")

        await fulfillment(of: [received], timeout: 2.0)
        task.cancel()
    }

    func testFiresOnInstall() async throws {
        let stub = StubURLSession()
        stub.checkData = Data(
            #"{"update_available":true,"bundle":{"version":"9.9.9","download_url":"https://ota/x.zip","size_bytes":1720}}"#
                .utf8)
        stub.downloadData = try ZipTestSupport.sampleBundleZip64()

        let w = Wordiy.shared
        w.setToken("cdl_test")
        w.currentVersion = "1.0.0"
        w.urlSession = stub
        w.store = freshStore("updates-install")

        let received = expectation(description: "emits on OTA install")
        let task = observeFirstEvent(fulfilling: received)
        await Task.yield()

        let updated = try await w.checkForUpdates()
        XCTAssertTrue(updated)

        await fulfillment(of: [received], timeout: 2.0)
        task.cancel()
    }

    func testDoesNotFireWhenLanguageUnchanged() async throws {
        let w = Wordiy.shared
        w.setLanguage("ar")  // establish current language BEFORE subscribing

        let notReceived = expectation(description: "no event when re-selecting the same language")
        notReceived.isInverted = true
        let task = observeFirstEvent(fulfilling: notReceived)
        await Task.yield()

        w.setLanguage("ar")  // no change → must not emit

        await fulfillment(of: [notReceived], timeout: 0.5)
        task.cancel()
    }

    func testAllSubscribersReceiveTheEvent() async throws {
        let w = Wordiy.shared
        w.setLanguage(nil)

        let a = expectation(description: "subscriber A")
        let b = expectation(description: "subscriber B")
        let t1 = observeFirstEvent(fulfilling: a)
        let t2 = observeFirstEvent(fulfilling: b)
        await Task.yield()

        w.setLanguage("ar")

        await fulfillment(of: [a, b], timeout: 2.0)
        t1.cancel()
        t2.cancel()
    }
}
