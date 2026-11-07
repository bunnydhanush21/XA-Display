# Changelog

All notable changes to XA Display are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Low Latency Wi-Fi mode: UDP video with sequencing, XOR parity, and NACKs. TCP stays the control and input path. The overlay shows capture-to-ack only after a sample exists.
- Read-only iPad battery telemetry, shown on the iPad and in the Mac menu. Missing registry fields stay unavailable.
- Experimental charge limit, off by default, with a separate root helper. Hysteresis, watchdog, and a kill-switch file restore normal charging.
- One-tap reconnect, a saved-Mac picker, and Bonjour discovery of the host. Wake-on-demand is a Bonjour connection, not a Wake-on-LAN packet.
- Media remote mode. Transport buttons post system media keys. The panel shows the frontmost app name.

## [1.0.0] - 2026-11-07

### Added

- iPad receiver (UIKit, iOS 12, arm64) derived from the MIT client by cuongpham1, and an original MIT Mac host.
- Virtual display, ScreenCaptureKit, and VideoToolbox H.264 with Balanced, Safe, and experimental Native presets.
- USB-first usbmuxd transport and Bonjour Wi-Fi fallback.
- Versioned input protocol on port 9001 with pairing, bounded parsers, and release of buttons on disconnect.
- Pointer, scroll, trackpad mode, sidebar, keyboard, clipboard text, and window snap through CGEvent and Accessibility.
- Touch-style window gestures: title-bar fill and flick, corner resize, loupe, traffic lights, menu overlay, right-edge drawer, momentum scroll.
- Optional AAC-LC or PCM audio with a jitter buffer and volume control.
- GitHub Actions on macOS 15 / Xcode 16.4: protocol tests, unsigned IPA, host zip, SwiftLint, and swift-format.
- Draft release workflow that attaches `XADisplay.ipa` and `XADisplayHost.zip` to a `v*` tag.

### Known limits

- No measured glass-to-glass latency. Preset numbers are targets.
- Clipboard images are framed and not applied. Mute-on-Mac and Opus are not implemented.
- MIDI, multitouch app integrations, launch at login, and a jailbreak launchd helper are not in this version.

[Unreleased]: https://github.com/bunnydhanush21/XA-Display/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/bunnydhanush21/XA-Display/releases/tag/v1.0.0
