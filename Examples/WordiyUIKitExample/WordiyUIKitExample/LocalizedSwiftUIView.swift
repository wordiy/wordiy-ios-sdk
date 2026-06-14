import SwiftUI
import Wordiy

/// SwiftUI counterpart of `ViewController`, proving the SDK works in SwiftUI too. `WordiyUpdater` (an
/// `ObservableObject` bridge over `Wordiy.shared.localizationUpdates()`) makes the view re-render — and
/// re-read `NSLocalizedString` — whenever the language switches or an OTA bundle installs, with no
/// manual refresh. Changing the language here also updates the UIKit screen, and vice versa.
struct LocalizedSwiftUIView: View {

    @StateObject private var updater = WordiyUpdater()
    @State private var status = ""

    /// Reads/writes the SDK's selected language directly, so the picker stays in sync with changes made
    /// elsewhere (e.g. the UIKit screen).
    private var language: Binding<String> {
        Binding(
            get: { Wordiy.shared.selectedLanguage ?? "en" },
            set: { Wordiy.shared.setLanguage($0, makeDefault: true) })
    }

    var body: some View {
        Form {
            Section("Localized strings") {
                Text(NSLocalizedString("welcome", comment: ""))
                    .font(.title3)
                Text(NSLocalizedString("intro", comment: ""))
                    .foregroundStyle(.secondary)
            }

            Picker("Language", selection: language) {
                Text("English").tag("en")
                Text("العربية").tag("ar")
            }

            Section {
                Button("Check for updates") {
                    Task {
                        status = "Checking…"
                        do {
                            let updated = try await Wordiy.shared.checkForUpdates()
                            status =
                                updated
                                ? "Updated to v\(Wordiy.shared.installedBundleVersion ?? "?")"
                                : "Already up to date"
                        } catch {
                            status = "Update failed: \(error)"
                        }
                    }
                }
                if !status.isEmpty {
                    Text(status).font(.footnote).foregroundStyle(.tertiary)
                }
            }
        }
        .environment(\.layoutDirection, language.wrappedValue == "ar" ? .rightToLeft : .leftToRight)
    }
}
