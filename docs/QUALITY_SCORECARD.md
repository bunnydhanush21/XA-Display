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
| Error handling | `XAError`, `HostError`, and `PadError` exist and each has a user-facing message. Host and iPad failure paths called from tests log those enums. | `Wake service unavailable` is still a string. Not every catch site builds an enum. |
| Concurrency | `swift build` and `swift test` use `-strict-concurrency=complete` and `-warnings-as-errors`. Mac app sets `SWIFT_STRICT_CONCURRENCY: complete` and the Mac host job builds. The gate rejects `@unchecked Sendable` under `macos/`. | iOS 12 cannot use actors. The iPad app keeps serial queues and `dispatchPrecondition`. |
| Tests / CI | Protocol line coverage >= 80%. Fuzz tests call every decoder listed in the gate. Connection-machine tests exist. CI runs this script and both app test suites. Mac host line coverage is gated at 60%. | iPad merged line coverage is below 60%, so that gate fails. |
| Docs | Every `public` type in `Sources/` has a doc comment. This file exists. `docs/screenshots/` holds CI PNGs referenced from the README. | No device tour. The connection-overlay bitmap was black and is not in the tree. |
| Protocol | Bounded framing, pairing proof on video, audio and clipboard gated by the armed input session, fuzz on decoders. | No TLS. UDP packets are not individually signed. |
| Menu bar / settings | Popover, status dot, and tabbed settings are in the Mac target. Custom width, height, frame rate, and bitrate are separate settings. `mac-popover.png` and `mac-settings.png` are CI captures. | The settings capture shows the connection tab, not every tab. |
| Onboarding / permissions | Mac four-step flow and iPad three-card flow are in the apps. Screen Recording and Accessibility are preflighted on the Mac. `mac-onboarding.png` and `ipad-onboarding.png` are CI captures. | The Mac shot is step one. The iPad shot is the first card. |
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

Committed from CI run [42439302012](https://github.com/bunnydhanush21/XA-Display/actions/runs/42439302012) and the Mac artifact on that run:

| File | What it is |
|---|---|
| `docs/screenshots/mac-popover.png` | Host test, menu popover. Shows peer, usb, 12 ms, 30 fps, Balanced, and the four toggles. |
| `docs/screenshots/mac-settings.png` | Host test, settings connection tab. |
| `docs/screenshots/mac-onboarding.png` | Host test, first onboarding step. |
| `docs/screenshots/ipad-onboarding.png` | Simulator unit test, first iPad card. |
| `docs/screenshots/ipad-landscape.png` | Simulator unit test, receiver with the pairing field and Connect. |

The connection-overlay render was almost black, so it is not in the tree. The gate still rejects a PNG under 8 KB.

## Current self-score

Evidence is CI on commit `64b7c5c` (run 42439302012) unless noted. Protocol line coverage in that run was 91.80%. The Mac host job reported 60.01%. The iPad job merged the unit-test and UI-test result bundles and reported 51.78%.

| Category | Score | Why |
|---|---|---|
| Structure | 9 | Protocol module, session actor, and separate session, connection, display, input, audio, clipboard, and permission types on both apps. |
| File size | 9 | Lint fails the build above 400 lines per file and per type body. |
| Error handling | 8 | `XAError`, `HostError`, and `PadError` have user text and tests log them. One wake-service failure is still a string. |
| Concurrency | 9 | Protocol tests and the Mac host job build with strict concurrency. The gate finds no `@unchecked Sendable` under `macos/`. |
| Tests / CI | 8 | Protocol coverage is 91.80% and the Mac app is 60.01%. Merged iPad coverage is 51.78%, under the 60% gate. |
| Docs | 9 | Public types are documented. The README links the five CI captures above. |
| Protocol | 9 | Bounds, auth gate, and decoder fuzz. No transport encryption. |
| Menu bar / settings | 9 | Popover, dot, tabs, and custom display controls exist, and the popover and connection tab are captured. |
| Onboarding / permissions | 9 | Both guided flows exist, the Mac preflights the two permissions, and both first steps are captured. |
| Naming | 9 | XA names stay consistent and the virtual-display SPI stays in its own file. |
| Logging | 9 | Both apps use the shared subsystem and five categories. Diagnostics tests redact the pairing token. |

Overall: (9+9+8+9+8+9+9+9+9+9+9) / 11 = 8.82.

The 9.2 target is not met. The open gaps are iPad line coverage under 60% and the string wake-service log. Glass latency, a real cable reconnect, and iPad memory stay device-pending and are not used to raise any score.
