import SwiftUI
import UIKit
import Wordiy

/// Shows Wordiy's core: labels resolved with plain `NSLocalizedString` (incl. a `%@` placeholder
/// formatted via `String(format:)`), plus a live language
/// switcher. The app's baked-in strings are marked "(local)"/"(محلي)"; after an OTA check installs a
/// bundle, the same keys resolve to the OTA values and the marker disappears — the swizzle (installed
/// in `AppDelegate`) does this with no call-site changes.
///
/// Refresh is driven by `Wordiy.shared.localizationUpdates()`: the SDK emits after an OTA install or a
/// language switch, and this screen re-reads its labels in response — no manual re-render at the call
/// site. The "SwiftUI" button opens an equivalent SwiftUI screen that refreshes the same way.
final class ViewController: UIViewController {

    private let languageControl = UISegmentedControl(items: ["English", "العربية"])
    private let languageCodes = ["en", "ar"]

    private let welcomeLabel = UILabel()
    private let introLabel = UILabel()
    private let varLabel = UILabel()
    private let statusLabel = UILabel()
    private let button = UIButton(type: .system)
    private let stack = UIStackView()

    /// Sample value substituted into the `with-var` placeholder (a real app would pass a user value).
    private let sampleName = "Sami"

    private var localizationTask: Task<Void, Never>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Wordiy SDK"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "SwiftUI", style: .plain, target: self, action: #selector(showSwiftUI))

        languageControl.addTarget(self, action: #selector(languageChanged), for: .valueChanged)

        welcomeLabel.font = .preferredFont(forTextStyle: .title2)
        welcomeLabel.numberOfLines = 0
        introLabel.font = .preferredFont(forTextStyle: .body)
        introLabel.textColor = .secondaryLabel
        introLabel.numberOfLines = 0
        varLabel.font = .preferredFont(forTextStyle: .callout)
        varLabel.numberOfLines = 0
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.numberOfLines = 0
        [welcomeLabel, introLabel, varLabel, statusLabel].forEach { $0.textAlignment = .natural }

        button.setTitle("Check for updates", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(checkTapped), for: .touchUpInside)

        [languageControl, welcomeLabel, introLabel, varLabel, statusLabel, button].forEach(
            stack.addArrangedSubview)
        stack.axis = .vertical
        stack.spacing = 16
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])

        // Reflect any persisted/active language (Wordiy restored it at init); default to English.
        let code = Wordiy.shared.selectedLanguage ?? "en"
        languageControl.selectedSegmentIndex = languageCodes.firstIndex(of: code) ?? 0

        render()  // first paint; subsequent refreshes come from the update stream
        observeLocalizationChanges()
        runCheck()
    }

    deinit { localizationTask?.cancel() }

    /// Re-reads the localized strings. Called once for first paint, then on every `localizationUpdates()`
    /// event. `with-var` carries a `%@` placeholder formatted with a sample name via `String(format:)`.
    private func render() {
        welcomeLabel.text = NSLocalizedString("welcome", comment: "Greeting on the home screen")
        introLabel.text = NSLocalizedString("intro", comment: "Short introduction on the home screen")
        varLabel.text = String(
            format: NSLocalizedString("with-var", comment: "Greeting with the user's name"), sampleName)
    }

    /// Re-render whenever the SDK reports a localization change (OTA install or language switch) —
    /// including changes made from the SwiftUI screen.
    private func observeLocalizationChanges() {
        localizationTask = Task { [weak self] in
            for await _ in Wordiy.shared.localizationUpdates() {
                self?.render()
            }
        }
    }

    @objc private func languageChanged() {
        let code = languageCodes[languageControl.selectedSegmentIndex]
        // Remember across launches + emit an update. The window's layout direction (managed in
        // SceneDelegate) and the labels both follow from this — no per-view direction forcing here.
        Wordiy.shared.setLanguage(code, makeDefault: true)
    }

    @objc private func checkTapped() { runCheck() }

    private func runCheck() {
        statusLabel.text = "Checking…"
        button.isEnabled = false
        // The async API has no @Sendable completion closure, so this unstructured Task — which inherits
        // the view controller's main-actor isolation — updates the UI without concurrency warnings. A
        // successful install emits an update, so the labels refresh via the stream (no render() here).
        Task {
            defer { button.isEnabled = true }
            do {
                let updated = try await Wordiy.shared.checkForUpdates()
                statusLabel.text =
                    updated
                    ? "Updated to v\(Wordiy.shared.installedBundleVersion ?? "?")"
                    : "Already up to date"
            } catch {
                statusLabel.text = "Update failed: \(error)"
            }
        }
    }

    @objc private func showSwiftUI() {
        let host = UIHostingController(rootView: LocalizedSwiftUIView())
        host.title = "SwiftUI"
        navigationController?.pushViewController(host, animated: true)
    }
}
