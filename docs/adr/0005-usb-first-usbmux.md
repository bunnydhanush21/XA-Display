# ADR 0005: USB through Apple usbmuxd, Wi-Fi as fallback

- Status: accepted
- Date: 2026-11-07

## Context

The iPad should work on the cable that already trusts the device. libusbmuxd is LGPL and would pull another license into the host. A Wi-Fi-only design leaves the cable unused and puts cleartext video on the LAN by default.

## Decision

Talk to `/var/run/usbmuxd` with Apple's plist protocol version 1. Connect with `Darwin.connect`, because Swift otherwise resolves `connect` to an instance method. Try the byte-swapped port first (`9000` → `10275`), then the plain port. If the accepted socket's remote host is loopback, call the link USB. Use Bonjour Wi-Fi only when USB is gone and the switch is on.

## Consequences

No libimobiledevice daemon ships in the app. The iPad must be trusted for USB. Wi-Fi frames are AES-256-GCM keyed from the pairing token; pairing is still the control gate for input ([SECURITY.md](../SECURITY.md)).
