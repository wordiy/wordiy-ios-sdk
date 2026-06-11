import Foundation

/// Manages the on-device storage of the active translation bundle.
///
/// Stores under `Application Support/Wordiy/` (persistent, unlike `Caches/`), excluded from iCloud/iTunes
/// backup. Installs use a **stage-then-promote** swap so a failed/interrupted update can never corrupt
/// the active bundle.
struct BundleStore: Sendable {

    let rootDir: URL

    /// Production initializer: `Application Support/Wordiy/`.
    init() throws {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        self.rootDir = appSupport.appendingPathComponent("Wordiy", isDirectory: true)
    }

    /// Test/override initializer.
    init(rootDir: URL) {
        self.rootDir = rootDir
    }

    /// The active installed bundle, e.g. `…/Wordiy/wordiy.bundle`.
    var activeBundleURL: URL {
        rootDir.appendingPathComponent("wordiy.bundle", isDirectory: true)
    }

    /// Installs the bundle found inside `extractedDir`, atomically replacing the active bundle.
    /// - Returns: the active bundle URL and its version (from `Contents/Info.plist`).
    @discardableResult
    func install(fromExtractedDir extractedDir: URL) throws -> (bundleURL: URL, version: String?) {
        let fm = FileManager.default
        let source = try locateBundle(in: extractedDir)
        try ensureRoot()

        let staging = rootDir.appendingPathComponent("wordiy.bundle.staging", isDirectory: true)
        try? fm.removeItem(at: staging)

        do {
            // Copy onto the same volume as the active bundle so the final swap is atomic.
            try fm.copyItem(at: source, to: staging)
            if fm.fileExists(atPath: activeBundleURL.path) {
                _ = try fm.replaceItemAt(activeBundleURL, withItemAt: staging)
            } else {
                try fm.moveItem(at: staging, to: activeBundleURL)
            }
        } catch {
            try? fm.removeItem(at: staging)
            throw WordiyError.io(error)
        }

        return (activeBundleURL, installedVersion())
    }

    /// The `CFBundleVersion` of the installed bundle (read directly from `Contents/Info.plist`).
    func installedVersion() -> String? {
        let plistURL = activeBundleURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = object as? [String: Any]
        else {
            return nil
        }
        return dict["CFBundleVersion"] as? String
    }

    /// Loads the installed bundle as an `NSBundle` (for the lookup milestone), or `nil` if not installed.
    func loadInstalledBundle() -> Bundle? {
        guard FileManager.default.fileExists(atPath: activeBundleURL.path) else { return nil }
        return Bundle(url: activeBundleURL)
    }

    // MARK: - Helpers

    private func ensureRoot() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: rootDir.path) {
            try fm.createDirectory(at: rootDir, withIntermediateDirectories: true)
        }
        // Re-downloadable content should not be backed up.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = rootDir
        try? mutableRoot.setResourceValues(values)
    }

    /// Finds the `*.bundle` directory (one containing `Contents/Resources`) inside `dir`.
    private func locateBundle(in dir: URL) throws -> URL {
        let fm = FileManager.default

        // Case 1: dir itself is the bundle (has Contents/Resources).
        if hasContentsResources(dir) { return dir }

        // Case 2: a child directory is the bundle — prefer a *.bundle name.
        let children =
            (try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]))
            ?? []
        let dirs = children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

        if let bundleDir = dirs.first(where: { $0.lastPathComponent.hasSuffix(".bundle") && hasContentsResources($0) }) {
            return bundleDir
        }
        if let anyBundle = dirs.first(where: { hasContentsResources($0) }) {
            return anyBundle
        }
        throw WordiyError.bundleNotFoundInArchive
    }

    private func hasContentsResources(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        let resources = url.appendingPathComponent("Contents/Resources")
        return FileManager.default.fileExists(atPath: resources.path, isDirectory: &isDir) && isDir.boolValue
    }
}
