import Foundation
import ObjectiveC

/// Routes `Bundle.main`'s string lookups through the installed OTA bundle, Lokalise-style.
///
/// `NSLocalizedString` calls `-[NSBundle localizedStringForKey:value:table:]` from any thread, but
/// ``Wordiy`` is `@MainActor`. This controller is the thread-safe seam between them: ``Wordiy`` writes
/// the active bundles on the main actor (``setBundles(ota:appFallback:)``); the swizzled method reads
/// them off-main under a lock (``currentBundles()``). Both are real `NSBundle`s, so the actual lookup —
/// `.strings` parsing, table resolution, plurals — is delegated to Foundation, which mirrors how
/// Lokalise works (it keeps no parsed dictionary of its own; it too holds a local + an OTA locale bundle).
///
/// The swizzle resolves in three tiers: the OTA `.lproj` (if it has the key), else the forced-language
/// app `.lproj` (`appFallback`, set only when a language is explicitly selected), else the original
/// `Bundle.main` implementation (the launch/system language).
final class WordiyBundleSwizzler: @unchecked Sendable {

    static let shared = WordiyBundleSwizzler()
    private init() {}

    /// Passed as `value:` when probing the OTA bundle. `NSBundle` echoes `value` back verbatim when a
    /// key is absent, so a result equal to this sentinel means "not in OTA" → fall back to the app
    /// bundle. The control characters make a collision with a real translation effectively impossible.
    static let missSentinel = "\u{01}__WORDIY_OTA_MISS__\u{01}"

    /// `-[NSBundle localizedStringForKey:value:table:]` — the selector we swizzle.
    static let localizedSelector = #selector(Bundle.localizedString(forKey:value:table:))
    /// Our replacement, defined in `Bundle+Wordiy.swift`.
    static let swizzledSelector = #selector(Bundle.wordiy_localizedString(forKey:value:table:))

    /// C-calling-convention signature of `-[NSBundle localizedStringForKey:value:table:]`, used to
    /// invoke the captured original implementation directly.
    typealias LocalizedStringIMP = @convention(c) (
        AnyObject, Selector, NSString, NSString?, NSString?
    ) -> NSString

    private let lock = NSLock()
    // Everything below is guarded by `lock`.
    private var otaLocaleBundle: Bundle?
    private var appFallbackBundle: Bundle?
    private var originalIMP: IMP?
    private var isSwizzled = false

    // MARK: - Active bundles (written on the main actor by Wordiy, read off-main by the swizzle)

    /// Sets both resolution bundles together. `appFallback` is the forced-language `Bundle.main`
    /// `.lproj`, or `nil` to follow the system language.
    func setBundles(ota: Bundle?, appFallback: Bundle?) {
        lock.lock()
        defer { lock.unlock() }
        otaLocaleBundle = ota
        appFallbackBundle = appFallback
    }

    /// Reads both bundles in one critical section, so the swizzle never sees a torn pair (a fresh OTA
    /// bundle with a stale fallback) when a check completes mid-language-switch.
    func currentBundles() -> (ota: Bundle?, appFallback: Bundle?) {
        lock.lock()
        defer { lock.unlock() }
        return (otaLocaleBundle, appFallbackBundle)
    }

    // MARK: - Swizzle install / teardown (idempotent)

    func swizzle() {
        lock.lock()
        defer { lock.unlock() }
        guard !isSwizzled,
            let original = class_getInstanceMethod(Bundle.self, Self.localizedSelector),
            let replacement = class_getInstanceMethod(Bundle.self, Self.swizzledSelector)
        else { return }
        // Capture the genuine original IMP BEFORE exchanging, so the fallback can call it directly
        // instead of re-dispatching the swizzled selector (the documented infinite-recursion crash).
        originalIMP = method_getImplementation(original)
        method_exchangeImplementations(original, replacement)
        isSwizzled = true
    }

    func deswizzle() {
        lock.lock()
        defer { lock.unlock() }
        guard isSwizzled,
            let original = class_getInstanceMethod(Bundle.self, Self.localizedSelector),
            let replacement = class_getInstanceMethod(Bundle.self, Self.swizzledSelector)
        else { return }
        method_exchangeImplementations(replacement, original)
        originalIMP = nil
        isSwizzled = false
    }

    // MARK: - Recursion-safe original call

    /// Invokes the captured original `localizedStringForKey:value:table:` on `bundle` directly — never
    /// re-dispatching the swizzled selector. When not swizzled, the live method already *is* the
    /// original, so a normal call is safe.
    func callOriginal(_ bundle: Bundle, key: String, value: String?, table: String?) -> String {
        lock.lock()
        let imp = originalIMP
        lock.unlock()

        guard let imp else {
            return bundle.localizedString(forKey: key, value: value, table: table)
        }
        let function = unsafeBitCast(imp, to: LocalizedStringIMP.self)
        return function(
            bundle, Self.localizedSelector,
            key as NSString, value as NSString?, table as NSString?
        ) as String
    }
}
