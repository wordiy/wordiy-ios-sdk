import UIKit
import Wordiy

/// Shows the resolved Wordiy configuration and drives the OTA check, then displays concrete proof the
/// bundle was fetched/unzipped/installed: on-disk path, locales, and a real key→value from the bundle.
final class ViewController: UIViewController {

    private let stack = UIStackView()
    private let statusLabel = UILabel()
    private let detailLabel = UILabel()
    private let button = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Wordiy SDK"

        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])

        let w = Wordiy.shared
        addRow("projectID", w.projectID ?? "—")
        addRow("token", mask(w.token))
        addRow("environment", w.localizationType.rawValue)
        addRow("currentVersion", w.currentVersion.isEmpty ? "—" : w.currentVersion)
        addRow("platform", w.platform)

        statusLabel.font = .monospacedSystemFont(ofSize: 16, weight: .semibold)
        statusLabel.numberOfLines = 0
        detailLabel.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        button.setTitle("Check for OTA updates", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.contentHorizontalAlignment = .leading
        button.addTarget(self, action: #selector(checkTapped), for: .touchUpInside)

        stack.addArrangedSubview(spacer(12))
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(detailLabel)
        stack.addArrangedSubview(spacer(4))
        stack.addArrangedSubview(button)

        refreshDetail()
        runCheck()
    }

    @objc private func checkTapped() { runCheck() }

    private func runCheck() {
        statusLabel.text = "OTA: checking…"
        button.isEnabled = false
        Wordiy.shared.checkForUpdates { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let updated):
                self.statusLabel.text =
                    updated
                    ? "OTA: ✓ downloaded & installed v\(Wordiy.shared.installedBundleVersion ?? "?")"
                    : "OTA: up to date (server has nothing newer than currentVersion)"
            case .failure(let error):
                self.statusLabel.text = "OTA: ✗ \(error)"
            }
            self.button.isEnabled = true
            self.refreshDetail()
        }
    }

    /// Concrete proof the content actually landed on disk.
    private func refreshDetail() {
        var lines: [String] = []
        lines.append("reports current_version: \(Wordiy.shared.reportedVersion)")
        lines.append("installed version: \(Wordiy.shared.installedBundleVersion ?? "—")")

        if let bundleURL = Wordiy.shared.installedBundleURL {
            lines.append("on disk: yes")
            lines.append("path: …/\(bundleURL.lastPathComponent)")

            let resources = bundleURL.appendingPathComponent("Contents/Resources")
            let locales =
                ((try? FileManager.default.contentsOfDirectory(atPath: resources.path)) ?? [])
                .filter { $0.hasSuffix(".lproj") }
                .map { $0.replacingOccurrences(of: ".lproj", with: "") }
                .sorted()
            lines.append("locales: \(locales.isEmpty ? "—" : locales.joined(separator: ", "))")

            // Read the en strings file directly (.strings is plist format) to prove real content.
            let en = resources.appendingPathComponent("en.lproj/Localizable.strings")
            if let dict = NSDictionary(contentsOf: en) as? [String: String], let first = dict.first {
                lines.append("en keys: \(dict.count)")
                lines.append("sample: \"\(first.key)\" → \"\(first.value)\"")
            }
        } else {
            lines.append("on disk: no (nothing downloaded yet)")
        }
        detailLabel.text = lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private func addRow(_ key: String, _ value: String) {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        let text = NSMutableAttributedString(
            string: "\(key): ", attributes: [.foregroundColor: UIColor.secondaryLabel])
        text.append(NSAttributedString(string: value, attributes: [.foregroundColor: UIColor.label]))
        label.attributedText = text
        stack.addArrangedSubview(label)
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let v = UIView()
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }

    private func mask(_ token: String?) -> String {
        guard let token, token.count > 8 else { return token ?? "—" }
        return String(token.prefix(8)) + "…"
    }
}
