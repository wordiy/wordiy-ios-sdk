import UIKit
import Wordiy

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // Configure the Wordiy SDK. (Init + settings milestone — no network yet.)
        Wordiy.shared.setProjectID("demo-project-id", token: "demo-sdk-token")
        Wordiy.shared.localizationType = .production
        Wordiy.shared.currentVersion = "v1.0.0"

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
