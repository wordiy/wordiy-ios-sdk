#if canImport(Combine)
    import Combine
    import Foundation

    /// Bridges ``Wordiy/localizationUpdates()`` to SwiftUI. Hold one as `@StateObject`; any view that
    /// observes it re-renders when localizations change — re-reading `NSLocalizedString` for the new
    /// values — without needing any `@Published` property.
    ///
    /// ```swift
    /// struct HomeView: View {
    ///     @StateObject private var updater = WordiyUpdater()
    ///     var body: some View {
    ///         Text(NSLocalizedString("welcome", comment: ""))  // re-read on every change
    ///     }
    /// }
    /// ```
    @MainActor
    public final class WordiyUpdater: ObservableObject {

        private var task: Task<Void, Never>?

        public init() {
            task = Task { [weak self] in
                for await _ in Wordiy.shared.localizationUpdates() {
                    self?.objectWillChange.send()
                }
            }
        }

        deinit {
            task?.cancel()
        }
    }
#endif
