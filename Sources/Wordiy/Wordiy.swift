import Foundation

/// The main entry point for the Wordiy localization SDK.
///
/// Wordiy delivers translations over-the-air (OTA) for the Wordiy AI translation service. Translations
/// are shipped as a native localization bundle and resolved by the system, so they work uniformly across
/// UIKit and SwiftUI.
///
/// ## Usage
/// ```swift
/// Wordiy.shared.setProjectID("your-project-id", token: "your-sdk-token")
/// Wordiy.shared.localizationType = .production
/// Wordiy.shared.currentVersion = "v1.0.0"
///
/// // Fetch + install the latest bundle (safe to call; never crashes the host app):
/// let updated = try await Wordiy.shared.checkForUpdates()
/// ```
///
/// > Note: This milestone adds the OTA pipeline (fetch → unzip → atomically replace the bundle).
/// > Looking up translated strings from the installed bundle is added in a later milestone.
@MainActor
public final class Wordiy {

    /// The shared singleton instance.
    public static let shared = Wordiy()

    private init() {
        store = try? BundleStore()
        installedBundleVersion = store?.installedVersion()
    }

    // MARK: - Credentials

    /// The configured project identifier, or `nil` before ``setProjectID(_:token:)`` is called.
    public private(set) var projectID: String?

    /// The configured SDK token, or `nil` before ``setProjectID(_:token:)`` is called.
    public private(set) var token: String?

    /// Whether the SDK has been configured with a project ID and token.
    public private(set) var isInitialized = false

    /// Configures the SDK with the project credentials.
    public func setProjectID(_ projectID: String, token: String) {
        self.projectID = projectID
        self.token = token
        self.isInitialized = true
    }

    // MARK: - Settings

    /// The content channel to fetch translations from. Defaults to ``LocalizationType/production``.
    public var localizationType: LocalizationType = .production

    /// The localization version your app ships with (its baseline), e.g. `"1.0.0"`.
    ///
    /// This is the version baked into your app build. The SDK does not report this verbatim — see
    /// ``reportedVersion``, which also accounts for any newer OTA bundle already installed.
    public var currentVersion: String = ""

    /// The version the SDK actually reports to the server as `current_version`: the higher of
    /// ``currentVersion`` (your app's baseline) and the installed OTA bundle version.
    ///
    /// This is what prevents re-downloading on every launch: once `1.1.0` is installed, the next check
    /// reports `1.1.0` and the server replies "up to date". If a future app build raises the baseline
    /// above the cached bundle, the baseline wins and the stale bundle is superseded.
    public var reportedVersion: String {
        guard let installed = installedBundleVersion else { return currentVersion }
        return SemVer.higher(currentVersion, installed)
    }

    /// The platform identifier sent with requests. Hardcoded to `"ios"` and not configurable.
    public private(set) var platform = "ios"

    // MARK: - OTA state

    /// The version of the currently installed OTA bundle, or `nil` if none has been installed.
    public private(set) var installedBundleVersion: String?

    /// On-disk location of the installed OTA bundle, or `nil` if none is installed.
    /// Useful for inspecting/validating the downloaded content (the lookup API comes later).
    public var installedBundleURL: URL? {
        guard let store, FileManager.default.fileExists(atPath: store.activeBundleURL.path) else {
            return nil
        }
        return store.activeBundleURL
    }

    private var isUpdating = false

    // Injectable seams (internal — overridden in tests; production uses the defaults).
    var urlSession: URLSessionProtocol = URLSession.shared
    var store: BundleStore?

    // MARK: - Update

    /// Checks the server for a newer translation bundle and, if available, downloads, unzips, and
    /// atomically installs it.
    ///
    /// - Returns: `true` if a new bundle was installed; `false` if already up to date.
    /// - Throws: ``WordiyError`` on any failure. A failed update leaves the previously installed bundle
    ///   intact; this method never traps.
    @discardableResult
    public func checkForUpdates() async throws -> Bool {
        guard isInitialized, let token else { throw WordiyError.notInitialized }
        guard !currentVersion.isEmpty else { throw WordiyError.missingCurrentVersion }
        guard !isUpdating else { throw WordiyError.alreadyUpdating }
        guard let store else {
            throw WordiyError.io(
                NSError(
                    domain: "Wordiy", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Application Support is unavailable"]))
        }

        let request = BundleCheckClient.Request(
            platform: platform,
            environment: localizationType.rawValue,
            currentVersion: reportedVersion,  // installed bundle version wins once it's newer
            apiKey: token)
        let session = urlSession

        isUpdating = true
        defer { isUpdating = false }

        // Run networking + unzip + file IO off the main actor.
        let result = try await Task.detached(priority: .utility) {
            try await Wordiy.performUpdate(request: request, store: store, session: session)
        }.value

        if result.updated {
            installedBundleVersion = result.version ?? store.installedVersion()
        }
        return result.updated
    }

    /// Completion-handler variant of ``checkForUpdates()`` for UIKit/Objective-C callers.
    /// The completion is invoked on the main actor.
    public func checkForUpdates(completion: @escaping @Sendable (Result<Bool, any Error>) -> Void) {
        Task { @MainActor in
            do {
                completion(.success(try await checkForUpdates()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// The off-main pipeline: check → (if update) download → unzip → install.
    private static func performUpdate(
        request: BundleCheckClient.Request,
        store: BundleStore,
        session: URLSessionProtocol
    ) async throws -> (updated: Bool, version: String?) {
        let response = try await BundleCheckClient(session: session).check(request)

        // Obey `update_available`; treat `bundle` as defensively optional.
        guard response.updateAvailable else { return (false, nil) }
        guard
            let info = response.bundle,
            let urlString = info.downloadUrl,
            let downloadURL = URL(string: urlString)
        else {
            throw WordiyError.invalidResponse
        }

        let fm = FileManager.default
        let zipURL = try await BundleDownloader(session: session)
            .download(from: downloadURL, expectedSize: info.sizeBytes)
        defer { try? fm.removeItem(at: zipURL) }

        let extractDir = fm.temporaryDirectory
            .appendingPathComponent("wordiy-extract-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: extractDir) }

        try ZipArchiveReader.extract(zipURL: zipURL, to: extractDir)
        let installed = try store.install(fromExtractedDir: extractDir)
        return (true, installed.version)
    }
}
