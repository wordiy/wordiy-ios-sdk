# Wordiy iOS SDK

Over-the-air (OTA) localization for the Wordiy AI translation service.

Wordiy downloads a native `.lproj` localization bundle and **swizzles `NSBundle`** so that plain
`NSLocalizedString` (and storyboard/XIB strings) transparently return the OTA value when present, and
fall back to your app's baked-in `.strings` otherwise — with **zero call-site changes**. It also offers
live in-app language switching and a change signal that refreshes both UIKit and SwiftUI.

- Fetch → vendored Zip64 unzip → **atomic install** under Application Support (a failed update never
  corrupts the active bundle, and `checkForUpdates()` never traps).
- Resolution order: **OTA → app's baked-in `.strings` → the key**. Only `Bundle.main` is intercepted.
- Works identically across UIKit and SwiftUI because the system resolves the strings.

## Requirements

- iOS 16+ · macOS 13+ · tvOS 16+
- Swift 6 / Xcode 16+

## Install (Swift Package Manager)

```swift
.package(path: "path/to/wordiy-ios-sdk")   // local
// or .package(url: "https://github.com/wordiy/wordiy-ios-sdk.git", from: "1.0.0")  // once published
```

Add the **`Wordiy`** product to your target.

## Quick start

```swift
import Wordiy

// At launch (e.g. in AppDelegate.didFinishLaunchingWithOptions):
Wordiy.shared.setToken("cdl_…")          // required: the project-scoped Content Delivery key
Wordiy.shared.currentVersion = "1.0.0"   // the localization version your app ships with
Wordiy.shared.swizzleMainBundle()        // route NSLocalizedString through the OTA bundle

Task {
    // Fetch + install the latest bundle if newer. Safe to call; never crashes the host app.
    try? await Wordiy.shared.checkForUpdates()
}

// Everywhere else — no SDK calls needed:
label.text = NSLocalizedString("welcome", comment: "")
```

Recommended boot order: **`setToken` → `swizzleMainBundle()` → `checkForUpdates`**. A previously
installed bundle is loaded at `swizzleMainBundle()` time, so cached OTA strings show on the next launch
before any network call.

## Configuration

```swift
Wordiy.shared.setToken("cdl_…")          // REQUIRED — the Api-Key that scopes the project
Wordiy.shared.setProjectID("123")        // optional — reserved for future integrations
Wordiy.shared.localizationType = .production   // .production (default) | .staging | .development
Wordiy.shared.currentVersion = "1.0.0"   // your app's baseline localization version
```

| Member | Notes |
| --- | --- |
| `setToken(_:)` | **Required.** Sets the Content Delivery key and flips `isInitialized` to `true`. |
| `setProjectID(_:)` | Optional. Not part of the bundle-check request (the token already scopes the project). |
| `localizationType` | Content channel: `.production` / `.staging` / `.development`. |
| `currentVersion` | The version baked into your build. |
| `reportedVersion` | Read-only. The higher of `currentVersion` and the installed bundle version — what the SDK actually reports, so it won't re-download on every launch. |
| `isInitialized` / `token` / `projectID` / `platform` | Read-only. `platform` is `"ios"`. |

> **Migration:** the old `setProjectID(_:token:)` has been removed. Use `setToken(_:)` (and optionally
> `setProjectID(_:)`).

## Fetching updates

```swift
let updated = try await Wordiy.shared.checkForUpdates()   // true if a newer bundle was installed
```

`checkForUpdates()` checks the server and, if a newer bundle exists, downloads, unzips, and atomically
installs it. It runs networking and file I/O off the main actor, and **never traps** — every failure is
thrown as a `WordiyError` and the previously installed bundle is left intact.

A completion-handler variant is available for UIKit / Obj-C call sites (the completion runs on the main
actor):

```swift
Wordiy.shared.checkForUpdates { result in
    // .success(Bool) / .failure(WordiyError)
}
```

Inspect installed state with `installedBundleVersion: String?` and `installedBundleURL: URL?`.

## Switching language

```swift
Wordiy.shared.setLanguage("ar", makeDefault: true)   // switch live; remember across launches
Wordiy.shared.setLanguage(nil)                       // follow the system language again
Wordiy.shared.selectedLanguage                       // read-only current selection
```

`setLanguage(_:makeDefault:)` forces the language for **both** the OTA lookup and the baked-in fallback,
so UI switches live (`NSLocalizedString`'s language is otherwise fixed at launch). `nil` follows the
system. `makeDefault: true` persists the choice (restored on the next launch); the default is
session-only. Re-render after switching — see below.

## Observing changes (refresh your UI)

`NSLocalizedString` isn't re-evaluated automatically, so re-read your strings when localizations change.
The SDK emits on the main actor after an OTA install or a real language change.

**UIKit** — consume the async stream:

```swift
let task = Task {
    for await _ in Wordiy.shared.localizationUpdates() {
        welcomeLabel.text = NSLocalizedString("welcome", comment: "")
    }
}
// cancel `task` in deinit
```

**SwiftUI** — hold a `WordiyUpdater` and the view re-renders on each change:

```swift
struct HomeView: View {
    @StateObject private var updater = WordiyUpdater()
    var body: some View {
        Text(NSLocalizedString("welcome", comment: ""))   // re-read on every change
    }
}
```

To stop intercepting entirely, call `Wordiy.shared.deswizzleMainBundle()`.

## Example app

`Examples/WordiyUIKitExample` is a UIKit app that consumes this package locally
(`XCLocalSwiftPackageReference`, `relativePath = "../../"`). It shows two labels resolved via
`NSLocalizedString`, a live **English / العربية** switcher (with RTL), and a **SwiftUI screen** (nav-bar
button) that auto-refreshes via `WordiyUpdater` — both stay in sync.

```sh
swift build && swift test
open Examples/WordiyUIKitExample/WordiyUIKitExample.xcodeproj
```

## Public API

| Group | Members |
| --- | --- |
| Singleton | `Wordiy.shared` (`@MainActor`) |
| Configure | `setToken(_:)`, `setProjectID(_:)`, `localizationType`, `currentVersion` |
| Read-only state | `isInitialized`, `token`, `projectID`, `platform`, `reportedVersion`, `installedBundleVersion`, `installedBundleURL` |
| OTA updates | `checkForUpdates() async throws -> Bool`, `checkForUpdates(completion:)` |
| Localization | `swizzleMainBundle()`, `deswizzleMainBundle()`, `setLanguage(_:makeDefault:)`, `selectedLanguage`, `localizationUpdates() -> AsyncStream<Void>`, `WordiyUpdater` (SwiftUI) |
| Types | `LocalizationType` (`.production`/`.staging`/`.development`), `WordiyError` |
