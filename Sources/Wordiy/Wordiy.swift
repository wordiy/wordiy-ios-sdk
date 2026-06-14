import Foundation

/// The main entry point for the Wordiy localization SDK.
///
/// Wordiy delivers translations over-the-air (OTA) for the Wordiy AI translation service. Translations
/// are shipped as a native localization bundle and resolved by the system, so they work uniformly across
/// UIKit and SwiftUI.
///
/// ## Usage
/// ```swift
/// Wordiy.shared.setToken("your-sdk-token")   // required (the project-scoped Api-Key)
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
        loadPersistedLanguage()
    }

    // MARK: - Credentials

    /// The configured SDK token (the project-scoped Content Delivery key, sent as `Api-Key`), or
    /// `nil` before ``setToken(_:)`` is called.
    public private(set) var token: String?

    /// The optional project identifier, or `nil` if never set. Reserved for future integrations —
    /// it is **not** part of the bundle-check request (the token already scopes the project).
    public private(set) var projectID: String?

    /// Whether the SDK has been configured with a token.
    public private(set) var isInitialized = false

    /// Configures the SDK with its token — the project-scoped Content Delivery key sent as the
    /// `Api-Key` header. **Required** before calling ``checkForUpdates()``.
    public func setToken(_ token: String) {
        self.token = token
        self.isInitialized = true
    }

    /// Optionally sets the project identifier. This is reserved for future integrations and is not
    /// used by the bundle-check request, so it is not required to use the SDK.
    public func setProjectID(_ projectID: String) {
        self.projectID = projectID
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
    var defaults: UserDefaults = .standard

    /// Key under which ``setLanguage(_:makeDefault:)`` persists the selected language.
    private static let persistedLanguageKey = "com.wordiy.selectedLanguage"

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
            // Pick up the freshly installed strings so an active swizzle serves them.
            refreshOTABundle()
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

    // MARK: - Localization swizzling

    /// Routes plain `NSLocalizedString` (and storyboard/XIB strings) through the installed OTA bundle:
    /// a key present in the OTA bundle for the app's selected language returns the OTA value; anything
    /// else falls back to the app's baked-in `.strings`. Opt-in, idempotent, and safe to call before
    /// any bundle is installed.
    ///
    /// Recommended boot order: ``setToken(_:)`` → ``swizzleMainBundle()`` → ``checkForUpdates()``.
    public func swizzleMainBundle() {
        refreshOTABundle()
        WordiyBundleSwizzler.shared.swizzle()
    }

    /// Restores the original `NSBundle` behavior installed by ``swizzleMainBundle()``. Idempotent.
    public func deswizzleMainBundle() {
        WordiyBundleSwizzler.shared.deswizzle()
    }

    /// The language forced via ``setLanguage(_:makeDefault:)``, or `nil` when following the system.
    public private(set) var selectedLanguage: String?

    /// Forces the language used for **both** OTA lookups and the baked-in `.strings` fallback, so the
    /// UI can switch language live (`NSLocalizedString`'s language is otherwise fixed at launch). Pass
    /// `nil` to follow the system again.
    ///
    /// - Parameters:
    ///   - languageCode: a language code such as `"en"` or `"ar"`, or `nil` to follow the system.
    ///   - makeDefault: when `true`, remember the choice across launches (persisted, restored at init).
    ///     When `false` (default), the change is for this session only and any saved default is kept.
    ///
    /// Re-render your UI after calling — UIKit/SwiftUI do not observe the bundle. Safe to call before
    /// ``swizzleMainBundle()`` or any install; it just stages the bundles until content exists.
    public func setLanguage(_ languageCode: String?, makeDefault: Bool = false) {
        selectedLanguage = languageCode
        if makeDefault {
            if let languageCode {
                defaults.set(languageCode, forKey: Self.persistedLanguageKey)
            } else {
                defaults.removeObject(forKey: Self.persistedLanguageKey)
            }
        }
        refreshOTABundle()
    }

    /// Restores a previously persisted ``selectedLanguage`` (from ``setLanguage(_:makeDefault:)`` with
    /// `makeDefault: true`). Called at init, before any refresh, so a relaunch serves the saved language.
    func loadPersistedLanguage() {
        selectedLanguage = defaults.string(forKey: Self.persistedLanguageKey)
    }

    /// Recomputes both resolution bundles for the current language and hands them to the swizzler:
    /// the OTA `.lproj` (from the installed bundle) and — only when a language is explicitly selected —
    /// the forced-language app `.lproj` (from `Bundle.main`). Called on install and from ``setLanguage``.
    private func refreshOTABundle() {
        let candidates = preferredLanguageCandidates()
        let ota = resolveOTALocaleBundle(candidates)
        let appFallback = (selectedLanguage == nil) ? nil : resolveMainLprojBundle(candidates)
        WordiyBundleSwizzler.shared.setBundles(ota: ota, appFallback: appFallback)
    }

    /// The installed OTA bundle narrowed to the first matching language, or `nil` if none is installed
    /// or no candidate is shipped in the bundle.
    private func resolveOTALocaleBundle(_ candidates: [String]) -> Bundle? {
        guard let url = installedBundleURL, let whole = Bundle(url: url) else { return nil }
        return localeBundle(in: whole, candidates: candidates)
    }

    /// `Bundle.main` narrowed to the first matching language `.lproj`, or `nil` if the app ships none.
    /// Used as the baked-in fallback when a language is explicitly selected (so a key missing from OTA
    /// renders in the chosen language, not the launch language).
    private func resolveMainLprojBundle(_ candidates: [String]) -> Bundle? {
        localeBundle(in: .main, candidates: candidates)
    }

    /// Loads `<bundle>/<lang>.lproj` as a `Bundle` for the first matching candidate.
    private func localeBundle(in bundle: Bundle, candidates: [String]) -> Bundle? {
        for language in candidates {
            if let lprojPath = bundle.path(forResource: language, ofType: "lproj"),
                let localeBundle = Bundle(path: lprojPath)
            {
                return localeBundle
            }
        }
        return nil
    }

    /// The selected/app/system language, plus its bare language code as a fallback (e.g. `en-US` → `en`).
    private func preferredLanguageCandidates() -> [String] {
        let primary =
            selectedLanguage
            ?? Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        let bare = primary.split(separator: "-").first.map(String.init) ?? primary
        return primary == bare ? [primary] : [primary, bare]
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
