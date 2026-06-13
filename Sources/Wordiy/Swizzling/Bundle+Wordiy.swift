import Foundation

extension Bundle {

    /// OTA-aware replacement for `-[NSBundle localizedStringForKey:value:table:]`, installed by
    /// ``Wordiy/swizzleMainBundle()``. After the swizzle, this body runs for every
    /// `localizedString(forKey:value:table:)` call — and therefore every `NSLocalizedString`,
    /// storyboard, and XIB string.
    ///
    /// Only `Bundle.main` is routed through the OTA bundle; every other bundle, and any key missing
    /// from OTA, falls through to the captured original implementation. The fallback never
    /// re-dispatches the swizzled selector (see `WordiyBundleSwizzler.callOriginal(_:key:value:table:)`),
    /// so the documented swizzle-recursion crash cannot occur.
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

        // OTA wins: probe the active OTA locale bundle with a sentinel so a miss is detectable. The
        // `table:` argument is delegated to Foundation unchanged, so storyboard/custom tables resolve
        // naturally when the OTA bundle ships them.
        if let ota = controller.otaLocaleBundleSnapshot() {
            let result = controller.callOriginal(
                ota, key: key, value: WordiyBundleSwizzler.missSentinel, table: table)
            if result != WordiyBundleSwizzler.missSentinel {
                return result
            }
        }

        // OTA miss → the app's baked-in default (or the caller's `value`, else the key).
        return controller.callOriginal(self, key: key, value: value, table: table)
    }
}
