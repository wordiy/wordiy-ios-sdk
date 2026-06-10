# Wordiy SDK — Internal TODO

Tracking deferred/internal work for the SDK. Add items as they come up.

## CI/CD + Release Tags
- [ ] `git init` the SDK repo and push to a remote.
- [ ] Adopt **semver git tags** (e.g. `1.0.0`) — this is what gives the package its SwiftPM version
      (there is no version field in `Package.swift`; SPM resolves versions from tags).
- [ ] Keep the in-code `Wordiy.sdkVersion` constant in sync with the release tag (reported in OTA requests).
- [ ] CI pipeline: build + run `swift test` and the example-app build on PRs.
- [ ] Release automation: tag → (optional) build artifacts → publish / changelog.
