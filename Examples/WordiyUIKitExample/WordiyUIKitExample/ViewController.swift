import UIKit
import Wordiy

/// Renders the resolved Wordiy configuration so a run visually confirms init + settings work.
final class ViewController: UIViewController {

    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Wordiy SDK"

        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .leading
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
        ])

        let w = Wordiy.shared
        addRow("initialized", "\(w.isInitialized)")
        addRow("projectID", w.projectID ?? "—")
        addRow("token", mask(w.token))
        addRow("localizationType", w.localizationType.rawValue)
        addRow("currentVersion", w.currentVersion.isEmpty ? "—" : w.currentVersion)
        addRow("platform", w.platform)
    }

    private func addRow(_ key: String, _ value: String) {
        let label = UILabel()
        label.numberOfLines = 0
        label.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        let keyText = NSMutableAttributedString(
            string: "\(key): ",
            attributes: [.foregroundColor: UIColor.secondaryLabel])
        keyText.append(NSAttributedString(
            string: value,
            attributes: [.foregroundColor: UIColor.label, .font: UIFont.monospacedSystemFont(ofSize: 16, weight: .semibold)]))
        label.attributedText = keyText
        stack.addArrangedSubview(label)
    }

    private func mask(_ token: String?) -> String {
        guard let token, token.count > 4 else { return token ?? "—" }
        return String(token.prefix(4)) + "…"
    }
}
