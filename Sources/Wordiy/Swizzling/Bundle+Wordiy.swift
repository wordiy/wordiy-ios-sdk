import Foundation

extension Bundle {

    /// OTA-aware replacement for `-[NSBundle localizedStringForKey:value:table:]`, installed by
    /// ``Wordiy/swizzleMainBundle()``. After the swizzle, this body runs for every
    /// `localizedString(forKey:value:table:)` call — and therefore every `NSLocalizedString`,
    /// storyboard, and XIB string.
    ///
    /// Only `Bundle.main` is routed; every other bundle passes straight through. For `Bundle.main` it
    /// resolves in three tiers: (a) the OTA `.lproj`, (b) — only when a language is explicitly selected
    /// via ``Wordiy/setLanguage(_:makeDefault:)`` — the forced-language app `.lproj`, (c) the original
    /// `Bundle.main` implementation (launch/system language). Each tier calls the captured original IMP
    /// (`WordiyBundleSwizzler.callOriginal`), never re-dispatching the swizzled selector, so the
    /// documented swizzle-recursion crash cannot occur.
    ///
    /// `nonisolated` and run on whatever thread the caller used — it never hops to the main actor.
    @objc nonisolated func wordiy_localizedString(
        forKey key: String, value: String?, table: String?
    ) -> String {
        let controller = WordiyBundleSwizzler.shared

        // Everything except the app's main bundle passes straight through.
        guard self === Bundle.main else {
            return controller.callOriginal(self, key: key, value: value, table: table)
        }

        let bundles = controller.currentBundles()  // one atomic read of (ota, appFallback)

        // (a) OTA wins: probe with a sentinel so a miss is detectable. `table:` is delegated to
        // Foundation unchanged, so storyboard/custom tables resolve naturally when OTA ships them.
        if let ota = bundles.ota {
            let result = controller.callOriginal(
                ota, key: key, value: WordiyBundleSwizzler.missSentinel, table: table)
            if result != WordiyBundleSwizzler.missSentinel {
                return result
            }
        }

        // (b) Forced-language baked-in fallback: resolve against Bundle.main's selected-language
        // `.lproj` instead of the launch/system language. Only set when a language is selected.
        if let appFallback = bundles.appFallback {
            return controller.callOriginal(appFallback, key: key, value: value, table: table)
        }

        // (c) Follow the system: the original `Bundle.main` implementation (or the caller's `value`,
        // else the key).
        return controller.callOriginal(self, key: key, value: value, table: table)
    }
}
