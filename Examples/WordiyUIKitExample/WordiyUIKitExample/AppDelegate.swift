import UIKit
import Wordiy

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Configure the Wordiy SDK.
        // Required: the cdl_ key is a read-only, embed-safe Content Delivery key (scopes the project).
        Wordiy.shared.setToken("cdl_r3UNt0bbu3bM3pENlyBGgkB1s8tTRdey")
        // Optional: reserved for future integrations; not used by the bundle-check request.
        Wordiy.shared.setProjectID("1")
        Wordiy.shared.localizationType = .production
        // `current_version` is "the version this app already has". Claim an OLDER version than the
        // latest published bundle so the server reports an update and we actually download one.
        // (Set this to the latest, e.g. "1.1.0", to see the "up to date / no download" branch.)
        Wordiy.shared.currentVersion = "1.0.0"
        // Route NSLocalizedString through the OTA bundle. Loads any previously cached bundle from disk
        // now, so on relaunch the labels show OTA values immediately — before any network call.
        Wordiy.shared.swizzleMainBundle()
        // The one app-level OTA check, at startup (boot pattern: setToken -> swizzleMainBundle ->
        // checkForUpdates). Screens just observe localizationUpdates() and re-render — they don't fetch.
        // checkForUpdates() returns true if a newer bundle was installed, false if already up to date,
        // and throws on failure (it never crashes the app).
        Task {
            do {
                let updated = try await Wordiy.shared.checkForUpdates()
                print("Wordiy: \(updated ? "installed a new localization bundle" : "localizations already up to date")")
            } catch {
                print("Wordiy: localization update check failed — \(error)")
            }
        }

        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
