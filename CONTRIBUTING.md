# Contributing

XA Display is a portfolio project by [Bunny Dhanush](https://github.com/bunnydhanush21). Issues and pull requests are welcome when they keep the license and the iOS 12 target intact.

## Ground rules

- The iPad app stays UIKit, deployment target iOS 12.0, arm64. No Swift concurrency in the apps.
- The Mac host stays macOS 14+ and original MIT code. Do not add OpenDisplay, Deskreen, libusbmuxd, or other GPL or LGPL source. Read [docs/adr/0001-mit-client-gpl-boundary.md](docs/adr/0001-mit-client-gpl-boundary.md).
- Pointer injection stays public `CGEvent` and `AXUIElement`. Do not synthesize undocumented touch.
- Do not add measured latency or FPS numbers unless the run is described in [docs/PERFORMANCE.md](docs/PERFORMANCE.md).
- Do not commit pairing tokens, device screenshots that show the token, or real captures labeled as placeholders.

## Build

Xcode 16.4. Xcode 26 cannot target iOS 12.

```bash
swift test
brew install xcodegen swiftlint
(cd ios && xcodegen generate && xcodebuild -scheme XADisplay -sdk iphoneos -configuration Release CODE_SIGNING_ALLOWED=NO build)
(cd macos && xcodegen generate && xcodebuild -scheme XADisplayHost -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build)
```

## Style

- Swift source is formatted with `.swift-format` (4 spaces, 200-column line length).
- SwiftLint 0.65.1 runs from `.swiftlint.yml` with `--strict`.
- `.editorconfig` covers the rest of the tree.

```bash
swift-format format --configuration .swift-format --recursive --in-place Sources Tests ios macos
swift-format lint --strict --configuration .swift-format --recursive Sources Tests ios macos
swiftlint lint --strict
```

## Commits

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add a paired clipboard image cap
fix: release the mouse button when the cable drops
docs: describe the jitter queue
test: cover title-bar double-tap
ci: pin SwiftLint 0.65.1
```

The subject is imperative, under about 72 characters, and says what changed.

## Pull requests

Describe the user-visible change, the tests you ran, and any preset or permission effect. Device checks you could not run belong in the PR text, not as a fake screenshot.

## Security

Pairing bypasses and frame-cap bugs should be reported privately. See [docs/SECURITY.md](docs/SECURITY.md).
