import Foundation

/// Errors surfaced by the Wordiy SDK.
///
/// Every failure path in the SDK is funneled into one of these cases — the SDK never traps or crashes
/// the host app. Network/IO underlying errors are wrapped so callers can inspect them if needed.
public enum WordiyError: Error, Sendable {
    /// `setProjectID(_:token:)` has not been called (missing project ID / token).
    case notInitialized
    /// `currentVersion` is empty; the bundles API requires a version.
    case missingCurrentVersion
    /// A transport-level error occurred (no connectivity, timeout, TLS, …).
    case network(any Error)
    /// The server returned a non-success status for the check request.
    case server(statusCode: Int, message: String?)
    /// The check response could not be decoded into the expected shape.
    case invalidResponse
    /// Downloading the bundle archive failed at the HTTP level.
    case downloadFailed(statusCode: Int?)
    /// The downloaded archive was empty.
    case emptyDownload
    /// The archive could not be unzipped.
    case unzipFailed(String)
    /// The archive did not contain a `*.bundle` with a `Contents/Resources` directory.
    case bundleNotFoundInArchive
    /// A check/update is already in progress.
    case alreadyUpdating
    /// A filesystem error occurred while installing the bundle.
    case io(any Error)
}

extension WordiyError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .notInitialized:
            return "Wordiy is not initialized. Call setProjectID(_:token:) first."
        case .missingCurrentVersion:
            return "currentVersion is empty. Set Wordiy.shared.currentVersion before checking for updates."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .server(let statusCode, let message):
            return "Server error \(statusCode)\(message.map { ": \($0)" } ?? "")."
        case .invalidResponse:
            return "The server response could not be parsed."
        case .downloadFailed(let statusCode):
            return "Bundle download failed\(statusCode.map { " (HTTP \($0))" } ?? "")."
        case .emptyDownload:
            return "The downloaded bundle was empty."
        case .unzipFailed(let reason):
            return "Failed to unzip the bundle: \(reason)"
        case .bundleNotFoundInArchive:
            return "The archive did not contain a valid .bundle."
        case .alreadyUpdating:
            return "A bundle update is already in progress."
        case .io(let error):
            return "Filesystem error: \(error.localizedDescription)"
        }
    }
}
