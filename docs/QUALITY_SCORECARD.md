# XA Display quality scorecard

Measurable criteria for the 11 categories in `DESIGN_REVIEW.md`. `scripts/quality_gate.sh` checks the rows marked automated. Device-only rows stay `device-pending` until a real device or a CI capture produces the number. They are not filled with estimates.

Scores below are the current self-score after the gate. They are not a claim that every category is 9.

## How a category is scored

Each category is 0 to 10. A category stays at 8 or below while any of its required automated checks fail. Device-pending evidence cannot raise a category above 8.

## Criteria

| Category | Automated check | Device-pending |
|---|---|---|
| Structure | Protocol target is separate from both apps. Host session phase is an actor. | Host and iPad behavior still share large types split across files, not separate service objects. |
| File size | SwiftLint `--strict`, `file_length` warning 400 / error 800, `type_body_length` warning 400 / error 800. | None. |
| Error handling | `XAError`, `HostError`, and `PadError` exist and each has a user-facing message. | Not every failure path returns those enums. |
| Concurrency | `swift build` and `swift test` use `-strict-concurrency=complete` and `-warnings-as-errors`. Mac app sets `SWIFT_STRICT_CONCURRENCY: complete`. iPad uses serial queues plus `dispatchPrecondition`. | Host classes that cross queues are `@unchecked Sendable`. iOS 12 cannot use actors. |
| Tests / CI | Protocol line coverage >= 80%. Fuzz tests call every decoder listed in the gate. Connection-machine tests exist. CI runs this script. | App-target line coverage is not 60%. No iPad UI test run. |
| Docs | Every `public` type in `Sources/` has a doc comment. This file exists. | Screenshots are device-pending. One-line comments are not a substitute for a device tour. |
| Protocol | Bounded framing, pairing proof on video, audio and clipboard gated by the armed input session, fuzz on decoders. | No TLS. UDP packets are not individually signed. |
| Menu bar / settings | Popover, status dot, and tabbed settings are in the Mac target. Custom width, height, frame rate, and bitrate are separate settings. | No captured screenshot of the popover. |
| Onboarding / permissions | Mac four-step flow and iPad three-card flow are in the apps. Screen Recording and Accessibility are preflighted on the Mac. | No captured screenshot. |
| Naming | Types in the protocol module use the `XA` prefix or a name scoped to this app. The gate does not grep for the OpenDisplay type names. | None. |
| Logging | Mac uses `os.Logger` and the iPad uses `OSLog` with subsystem `com.bunnydhanush.xadisplay` and categories net, video, input, audio, ui. The components listed in the gate call `XALog`. | iOS 12 has no `os.Logger`. The ring is in memory, not a rotating file. |

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

device-pending. The gate rejects a PNG under 8 KB so a placeholder cannot satisfy this row. No screenshot is invented here.

## Current self-score

| Category | Score | Why |
|---|---|---|
| Structure | 8 | Shared protocol module and a session actor. Host and iPad logic are still one type per app, split into files. |
| File size | 9 | Lint fails the build above 400 lines per file and per type body. |
| Error handling | 8 | Three typed error enums have user text. Many paths still log a string. |
| Concurrency | 8 | Protocol library is clean under strict concurrency. The Mac target opts in. Host classes are unchecked Sendable. |
| Tests / CI | 8 | Protocol line coverage is above 80%, with fuzz and state-machine tests. App coverage is below the 60% target. |
| Docs | 8 | Public types have a doc comment and this scorecard exists. Screenshots are device-pending. |
| Protocol | 9 | Bounds, auth gate, and decoder fuzz. No transport encryption. |
| Menu bar / settings | 8 | Popover, dot, tabs, and independent custom display controls exist. Not screenshot-verified. |
| Onboarding / permissions | 8 | Both guided flows exist and the Mac preflights the two permissions. Not screenshot-verified. |
| Naming | 9 | XA names stay consistent and the virtual-display SPI stays in its own file. |
| Logging | 8 | Both apps log through the shared subsystem and the five categories. The iPad uses `os_log`. |

Overall: (8+9+8+8+8+8+9+8+8+9+8) / 11 = 8.27.

The 9.2 target is not met. The gaps are app-target coverage, separate service objects, checked Sendable on the host, screenshots, and device benchmarks.
