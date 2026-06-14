import UIKit
import Wordiy

/// Shows Wordiy's core: two labels resolved with plain `NSLocalizedString`, plus a live language
/// switcher. The app's baked-in strings are marked "(local)"/"(محلي)"; after an OTA check installs a
/// bundle, the same keys resolve to the OTA values and the marker disappears — the swizzle (installed
/// in `AppDelegate`) does this with no call-site changes. Tapping a language calls
/// `Wordiy.shared.setLanguage(_:makeDefault:)` and re-renders, switching both layers live.
final class ViewController: UIViewController {

    private let languageControl = UISegmentedControl(items: ["English", "العربية"])
    private let languageCodes = ["en", "ar"]

    private let welcomeLabel = UILabel()
    private let introLabel = UILabel()
    private let statusLabel = UILabel()
    private let button = UIButton(type: .system)
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Wordiy SDK"

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

        render()
        runCheck()
    }

    /// Re-reads the two strings. UIKit doesn't observe the bundle, so this must run after each check
    /// and after every language switch.
    private func render() {
        welcomeLabel.text = NSLocalizedString("welcome", comment: "Greeting on the home screen")
        introLabel.text = NSLocalizedString("intro", comment: "Short introduction on the home screen")
    }

    @objc private func languageChanged() {
        let code = languageCodes[languageControl.selectedSegmentIndex]
        Wordiy.shared.setLanguage(code, makeDefault: true)  // remember across launches
        applyDirection(for: code)
        render()
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
        // the view controller's main-actor isolation — updates the UI without concurrency warnings.
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
            render()
        }
    }
}
