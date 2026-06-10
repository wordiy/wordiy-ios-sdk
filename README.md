# Wordiy iOS SDK

Over-the-air (OTA) localization SDK for the Wordiy AI translation service.

> **Status:** initialization & settings milestone. The SDK currently exposes configuration only —
> fetching/applying translations comes next. The chosen architecture is the **bundle approach**: the
> SDK will download a native `.lproj` localization bundle and let the system resolve strings (so it
> works identically across UIKit and SwiftUI).

## Install (Swift Package Manager)

```swift
.package(path: "path/to/wordiy-ios-sdk")   // local
// or .package(url: "…", from: "1.0.0")    // once published
```

Add the `Wordiy` product to your target.

## Configure

```swift
import Wordiy

Wordiy.shared.setProjectID("your-project-id", token: "your-sdk-token")
Wordiy.shared.localizationType = .production   // .production | .staging | .development
Wordiy.shared.currentVersion = "v1.0.0"

Wordiy.shared.platform        // "ios" (read-only)
Wordiy.shared.isInitialized   // true after setProjectID(_:token:)
```

## Example app

`Examples/WordiyUIKitExample` is a minimal UIKit app that consumes this package **locally**
(`XCLocalSwiftPackageReference`, `relativePath = "../../"`) and renders the resolved configuration,
so you can verify init + settings end-to-end.

```sh
swift build && swift test
open Examples/WordiyUIKitExample/WordiyUIKitExample.xcodeproj
```

## Public API (this milestone)

| Member | Kind | Notes |
| --- | --- | --- |
| `Wordiy.shared` | singleton | `@MainActor` |
| `setProjectID(_:token:)` | method | stores credentials, sets `isInitialized` |
| `projectID` / `token` / `isInitialized` | read-only | |
| `localizationType` | `LocalizationType` | `.production` (default) / `.staging` / `.development` |
| `currentVersion` | `String` | e.g. `"v1.0.0"` |
| `platform` | read-only | `"ios"`, not configurable |
