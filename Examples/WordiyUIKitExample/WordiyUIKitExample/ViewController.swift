import SwiftUI
import UIKit
import Wordiy

/// Shows Wordiy's core: two labels resolved with plain `NSLocalizedString`, plus a live language
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
    private let statusLabel = UILabel()
    private let button = UIButton(type: .system)
    private let stack = UIStackView()

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
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .tertiaryLabel
        statusLabel.numberOfLines = 0
        [welcomeLabel, introLabel, statusLabel].forEach { $0.textAlignment = .natural }

        button.setTitle("Check for updates", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(checkTapped), for: .touchUpInside)

        [languageControl, welcomeLabel, introLabel, statusLabel, button].forEach(stack.addArrangedSubview)
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
        applyDirection(for: code)

        render()  // first paint; subsequent refreshes come from the update stream
        observeLocalizationChanges()
        runCheck()
    }

    deinit { localizationTask?.cancel() }

    /// Re-reads the two strings. Called once for first paint, then on every `localizationUpdates()` event.
    private func render() {
        welcomeLabel.text = NSLocalizedString("welcome", comment: "Greeting on the home screen")
        introLabel.text = NSLocalizedString("intro", comment: "Short introduction on the home screen")
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
        Wordiy.shared.setLanguage(code, makeDefault: true)  // remember across launches; emits an update
        applyDirection(for: code)  // layout direction isn't a localized string, so set it directly
    }

    /// Minimal RTL: flip the layout direction for Arabic. Labels use `.natural` alignment, which follows
    /// the effective direction set here.
    private func applyDirection(for code: String) {
        let attribute: UISemanticContentAttribute = (code == "ar") ? .forceRightToLeft : .forceLeftToRight
        view.semanticContentAttribute = attribute
        stack.semanticContentAttribute = attribute
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
