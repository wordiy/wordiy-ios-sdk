import Foundation

extension Wordiy {

    /// An async sequence that emits each time the resolved localizations change — after a successful
    /// OTA install (``checkForUpdates()``) or a ``setLanguage(_:makeDefault:)`` that actually changes
    /// the language. `NSLocalizedString` is not re-evaluated automatically, so observe this and re-read
    /// your strings to refresh UI that didn't trigger the change.
    ///
    /// Supports multiple concurrent subscribers; each call returns its own stream. Iteration ends when
    /// the consuming `Task` is cancelled or deallocated.
    ///
    /// ```swift
    /// // UIKit
    /// task = Task { for await _ in Wordiy.shared.localizationUpdates() { rerenderLabels() } }
    /// ```
    public func localizationUpdates() -> AsyncStream<Void> {
        // Coalesce bursts: a Void "something changed" signal only needs to wake the consumer once.
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            // The build closure runs synchronously in this (main-actor) context.
            let id = UUID()
            localizationContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                // @Sendable, arbitrary executor → hop back to the main actor to deregister.
                Task { @MainActor [weak self] in
                    self?.localizationContinuations[id] = nil
                }
            }
        }
    }

    /// Emits to every live ``localizationUpdates()`` subscriber. Called only on a real change.
    func notifyLocalizationChanged() {
        for continuation in localizationContinuations.values {
            continuation.yield(())
        }
    }

    /// Finishes and clears all subscribers. For test `tearDown` only — the singleton persists across
    /// tests, so leftover continuations would otherwise receive a later test's events.
    func _resetLocalizationSubscribersForTesting() {
        for continuation in localizationContinuations.values {
            continuation.finish()
        }
        localizationContinuations.removeAll()
    }
}
