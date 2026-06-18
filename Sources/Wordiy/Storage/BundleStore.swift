import Foundation

/// Manages the on-device storage of the active translation bundle.
///
/// Stores under `Application Support/Wordiy/` (persistent, unlike `Caches/`), excluded from iCloud/iTunes
/// backup. Each install lands in a **new generation directory** (`wordiy-<n>.bundle`, `n` monotonic) and
/// older generations are removed. The fresh path matters: `NSBundle` caches a bundle's resources per path
/// for the process lifetime, so reusing one path would serve stale strings after a mid-session re-install
/// (only a relaunch would clear it). A new path each time guarantees the swizzle loads fresh content.
struct BundleStore: Sendable {

    let rootDir: URL

    private static let prefix = "wordiy-"
    private static let suffix = ".bundle"

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

    /// The newest installed generation (e.g. `…/Wordiy/wordiy-3.bundle`), or `nil` if none is installed.
    var activeBundleURL: URL? {
        installedGenerations().last?.url
    }

    /// Installs the bundle found inside `extractedDir` into a fresh generation directory, then removes
    /// older generations. A failed install leaves the previous generation active.
    /// - Returns: the new bundle URL and its version (from `Contents/Info.plist`).
    @discardableResult
    func install(fromExtractedDir extractedDir: URL) throws -> (bundleURL: URL, version: String?) {
        let fm = FileManager.default
        let source = try locateBundle(in: extractedDir)
        try ensureRoot()

        let generations = installedGenerations()
        let next = (generations.last?.number ?? 0) + 1
        let target = rootDir.appendingPathComponent(
            "\(Self.prefix)\(next)\(Self.suffix)", isDirectory: true)

        // Stage on the same volume as the target, then atomically move it into place — a brand-new path
        // `NSBundle` has never loaded, so the swizzle picks up the new content without a relaunch.
        let staging = rootDir.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        try? fm.removeItem(at: staging)
        do {
            try fm.copyItem(at: source, to: staging)
            try fm.moveItem(at: staging, to: target)
        } catch {
            try? fm.removeItem(at: staging)
            throw WordiyError.io(error)
        }

        // Best-effort cleanup of superseded generations (the new one is now active).
        for generation in generations {
            try? fm.removeItem(at: generation.url)
        }

        return (target, version(at: target))
    }

    /// The `CFBundleVersion` of the active installed bundle, or `nil` if none is installed.
    func installedVersion() -> String? {
        guard let url = activeBundleURL else { return nil }
        return version(at: url)
    }

    /// Loads the active installed bundle as an `NSBundle`, or `nil` if not installed.
    func loadInstalledBundle() -> Bundle? {
        guard let url = activeBundleURL else { return nil }
        return Bundle(url: url)
    }

    // MARK: - Helpers

    /// All installed generation directories, ascending by counter (so `.last` is the newest).
    private func installedGenerations() -> [(number: Int, url: URL)] {
        let items =
            (try? FileManager.default.contentsOfDirectory(
                at: rootDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return
            items
            .compactMap { url -> (number: Int, url: URL)? in
                let name = url.lastPathComponent
                guard name.hasPrefix(Self.prefix), name.hasSuffix(Self.suffix),
                    let number = Int(name.dropFirst(Self.prefix.count).dropLast(Self.suffix.count))
                else { return nil }
                return (number, url)
            }
            .sorted { $0.number < $1.number }
    }

    private func version(at bundleURL: URL) -> String? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard
            let data = try? Data(contentsOf: plistURL),
            let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let dict = object as? [String: Any]
        else {
            return nil
        }
        return dict["CFBundleVersion"] as? String
    }

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
