import UIKit
import Wordiy

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Configure the Wordiy SDK.
        // The cdl_ key is a read-only, embed-safe Content Delivery key for the staging project.
        Wordiy.shared.setProjectID("1", token: "cdl_r3UNt0bbu3bM3pENlyBGgkB1s8tTRdey")
        Wordiy.shared.localizationType = .production
        // `current_version` is "the version this app already has". Claim an OLDER version than the
        // latest published bundle so the server reports an update and we actually download one.
        // (Set this to the latest, e.g. "1.1.0", to see the "up to date / no download" branch.)
        Wordiy.shared.currentVersion = "1.0.0"

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
