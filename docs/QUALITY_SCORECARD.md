# XA Display quality scorecard

Measurable criteria for the 11 categories in `DESIGN_REVIEW.md`. `scripts/quality_gate.sh` checks the rows marked automated. Device-only rows stay `device-pending` until a real device or a CI capture produces the number. They are not filled with estimates.

Scores below are the current self-score after the gate. They are not a claim that every category is 9.

## How a category is scored

Each category is 0 to 10. A category stays at 8 or below while any of its required automated checks fail. Device-pending evidence cannot raise a category above 8.

## Criteria

| Category | Automated check | Device-pending |
|---|---|---|
| Structure | Protocol target is separate from both apps. Host session phase is an actor. Host and iPad session, connection, display, input, audio, clipboard, and permissions are separate types behind protocols. | `HostController` and `ReceiverViewController` still orchestrate those services. |
| File size | SwiftLint `--strict`, `file_length` warning 400 / error 800, `type_body_length` warning 400 / error 800. | None. |
| Error handling | `XAError`, `HostError`, and `PadError` exist and each has a user-facing message. The gate rejects a quoted failure log and an app `catch` that does not build one of those errors. | A reassembled UDP datagram that fails the seal is dropped instead of shown. |
| Concurrency | `swift build` and `swift test` use `-strict-concurrency=complete` and `-warnings-as-errors`. Mac app sets `SWIFT_STRICT_CONCURRENCY: complete` and the Mac host job builds. The gate rejects `@unchecked Sendable` under `macos/`. | iOS 12 cannot use actors. The iPad app keeps serial queues and `dispatchPrecondition`. |
| Tests / CI | Protocol line coverage >= 80%. Fuzz tests call every decoder listed in the gate. Connection-machine tests exist. CI runs this script and both app test suites. Mac host and merged iPad line coverage are gated at 60%. | App coverage is below 85%, so this category is not a 10. |
| Docs | Every `public` type in `Sources/` has a doc comment. This file exists. `docs/screenshots/` holds CI PNGs referenced from the README. | No device tour. |
| Protocol | Bounded framing, pairing proof on video, audio and clipboard gated by the armed input session, fuzz on decoders. Video, input, and UDP payloads are AES-256-GCM via CommonCrypto, keyed from the pairing token. The gate requires `CCCryptorGCMOneshotEncrypt` and the tamper test. | No TLS handshake. Someone who learns the pairing token can decrypt. |
| Menu bar / settings | Popover, status dot, and tabbed settings are in the Mac target. Custom width, height, frame rate, and bitrate are separate settings. `mac-popover.png` and `mac-settings.png` are CI captures. | The settings capture shows the connection tab, not every tab. |
| Onboarding / permissions | Mac four-step flow and iPad three-card flow are in the apps. Screen Recording and Accessibility are preflighted on the Mac. `mac-onboarding.png` and the three iPad cards are CI captures. | The Mac shot is step one. Capturing the later Mac steps in the same test crashed the host. |
| Naming | Types in the protocol module use the `XA` prefix or a name scoped to this app. The gate does not grep for the OpenDisplay type names. | None. |
| Logging | Mac uses `os.Logger` and the iPad uses `OSLog` with subsystem `com.bunnydhanush.xadisplay` and categories net, video, input, audio, ui. Export diagnostics tests redact the pairing token. | iOS 12 has no `os.Logger`. The ring is in memory, not a rotating file. |

## Benchmarks

| Measurement | Result |
|---|---|
| Synthetic UDP reassembly loop | Written by `QualityTests` to `build/quality/loopback.json` when the gate runs. This is framing, not an encoder. |
| Frame-pacing jitter of that loop | Same file. Not glass-to-glass. |
| State-machine reconnect decision | Must finish under 2 seconds. This is not a cable unplug. |
| Encode + transport glass latency | device-pending |
| Device reconnect under 2 seconds | device-pending |
| iPad client memory under 150 MB | device-pending |

## Screenshots

Committed from CI on this branch. Coverage numbers below are from run [42449717159](https://github.com/bunnydhanush21/XA-Display/actions/runs/42449717159). The connection overlay is from the simulator job on that branch, and the Connect and Pair cards are from run [42449097175](https://github.com/bunnydhanush21/XA-Display/actions/runs/42449097175).

| File | What it is |
|---|---|
| `docs/screenshots/mac-popover.png` | Host test, menu popover. Shows peer, usb, 12 ms, 30 fps, Balanced, and the four toggles. |
| `docs/screenshots/mac-settings.png` | Host test, settings connection tab. |
| `docs/screenshots/mac-onboarding.png` | Host test, first onboarding step. |
| `docs/screenshots/ipad-onboarding.png` | Simulator unit test, first iPad card. |
| `docs/screenshots/ipad-onboarding-connect.png` | Simulator unit test, Connect card. |
| `docs/screenshots/ipad-onboarding-pair.png` | Simulator unit test, Pair card. |
| `docs/screenshots/ipad-connection.png` | Simulator unit test, connection overlay with the pairing code, Connect, and Settings. |
| `docs/screenshots/ipad-landscape.png` | Simulator unit test, receiver with the pairing field and Connect. |

The gate rejects a PNG under 8 KB.

## Current self-score

Evidence is CI on commit `86469ff` (run [42449717159](https://github.com/bunnydhanush21/XA-Display/actions/runs/42449717159)). Protocol line coverage was 92.23%. The Mac host job reported 60.06%. The iPad job merged the unit-test and UI-test result bundles and reported 69.99%.

| Category | Score | Why |
|---|---|---|
| Structure | 9 | Protocol module, session actor, and separate session, connection, display, input, audio, clipboard, and permission types on both apps. The two controllers still orchestrate those services. |
| File size | 9 | Lint fails the build above 400 lines per file and per type body. |
| Error handling | 10 | Wake, audio, capture, seal, decode, and listener failures are `HostError` or `PadError`. The gate fails a quoted failure string and an app `catch` that does not build a typed error. A bad UDP datagram is discarded rather than toasted. |
| Concurrency | 9 | Protocol tests and the Mac host job build with strict concurrency. The gate finds no `@unchecked Sendable` under `macos/`. The iPad target stays on serial queues because it is iOS 12. |
| Tests / CI | 9 | Protocol coverage is 92.23%. Mac app coverage is 60.06%. Merged iPad coverage is 69.99%. Decoder fuzz and seal tamper tests are in the protocol suite. Neither app is at 85%, so this is not a 10. |
| Docs | 9 | Public types are documented. The README links the CI captures, including the connection overlay and all three iPad cards. There is no device tour. |
| Protocol | 10 | Video, input, and UDP payloads are AES-256-GCM from CommonCrypto (`CCCryptorGCMOneshotEncrypt` / `Decrypt`), keyed by SHA-256 of the pairing token, with the channel name as additional data. Tamper, wrong-token, and empty-token tests reject the frame. There is no TLS handshake. |
| Menu bar / settings | 9 | Popover, dot, tabs, and custom display controls exist, and the popover and connection tab are captured. The other tabs are implemented. Capturing all of them in one host test crashed the process, so those shots are not evidence. |
| Onboarding / permissions | 9 | Both guided flows exist, the Mac preflights the two permissions, and all three iPad cards are captured. The Mac shot is still step one. |
| Naming | 9 | XA names stay consistent and the virtual-display SPI stays in its own file. |
| Logging | 9 | Both apps use the shared subsystem and five categories. Diagnostics tests redact the pairing token. The iPad ring is in memory. |

Overall: (9+9+10+9+9+9+10+9+9+9+9) / 11 = 101/11 = 9.18.

The 9.2 target is not met. 9.2 needs 102 points, which is a third 10. Tests stay at 9 because Mac coverage is 60.06% and iPad coverage is 69.99%, both under 85%. Menu and onboarding stay at 9 because the Mac host crashed when the test tried to capture the remaining settings tabs and onboarding steps. Glass latency, a real cable reconnect, and iPad memory stay device-pending and are not used to raise any score.
