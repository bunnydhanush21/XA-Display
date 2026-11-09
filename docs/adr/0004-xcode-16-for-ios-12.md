# ADR 0004: Build the iPad app with Xcode 16.4

- Status: accepted
- Date: 2026-11-07

## Context

The iPad mini 3 runs iOS 12.5.8. Xcode 26 cannot target iOS 12. The GitHub `macos-14` runners were retired. `macos-15` still provides Xcode 16.4.

## Decision

CI selects `/Applications/Xcode_16.4.app` and checks that `xcodebuild -version` starts with `Xcode 16.`. The iOS deployment target is 12.0, architecture arm64, iPad idiom. The Mac deployment target is 14. The shared package is Swift tools 5.9 and avoids CoreGraphics so Linux can run `swift test`.

## Consequences

A runner image that drops Xcode 16.4 breaks the IPA job until the pin moves. Newer Swift in local editors must stay source-compatible with the 5.9 package and the iOS 12 SDK (no Swift concurrency in the apps).
