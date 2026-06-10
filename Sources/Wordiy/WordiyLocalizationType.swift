import Foundation

extension Wordiy {
    /// Selects which content channel Wordiy fetches over-the-air translations from.
    ///
    /// Mirrors the release-channel concept used by comparable OTA SDKs. Sent to the backend so it
    /// can serve the matching bundle for the environment.
    public enum LocalizationType: String, Sendable, CaseIterable {
        /// Production bundles served to end users. The default.
        case production
        /// Staging bundles for pre-production verification.
        case staging
        /// Development bundles for local/in-progress work.
        case development
    }
}
