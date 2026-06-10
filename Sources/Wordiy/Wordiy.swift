import Foundation

/// The main entry point for the Wordiy localization SDK.
///
/// Wordiy delivers translations over-the-air (OTA) for our AI translation service. Translations are
/// shipped as a native localization bundle and resolved by the system, so they work uniformly across
/// UIKit and SwiftUI.
///
/// ## Usage
/// ```swift
/// Wordiy.shared.setProjectID("your-project-id", token: "your-sdk-token")
/// Wordiy.shared.localizationType = .production
/// Wordiy.shared.currentVersion = "v1.0.0"
/// ```
///
/// > Note: This is the initialization & settings milestone. Fetching/applying translations is added
/// > in a later milestone.
@MainActor
public final class Wordiy {

    /// The shared singleton instance.
    public static let shared = Wordiy()

    private init() {}

    // MARK: - Credentials

    /// The configured project identifier, or `nil` before ``setProjectID(_:token:)`` is called.
    public private(set) var projectID: String?

    /// The configured SDK token, or `nil` before ``setProjectID(_:token:)`` is called.
    public private(set) var token: String?

    /// Whether the SDK has been configured with a project ID and token.
    public private(set) var isInitialized = false

    /// Configures the SDK with the project credentials.
    ///
    /// - Parameters:
    ///   - projectID: The Wordiy project identifier.
    ///   - token: The Wordiy SDK token for this project.
    public func setProjectID(_ projectID: String, token: String) {
        self.projectID = projectID
        self.token = token
        self.isInitialized = true
    }

    // MARK: - Settings

    /// The content channel to fetch translations from. Defaults to ``LocalizationType/production``.
    public var localizationType: LocalizationType = .production

    /// The app's current version, e.g. `"v1.0.0"`. Used to scope OTA bundles to a release.
    public var currentVersion: String = ""

    /// The platform identifier sent with requests. Hardcoded to `"ios"` and not configurable.
    public private(set) var platform = "ios"
}
