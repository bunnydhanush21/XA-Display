# Testing

Automated coverage is `swift test` on the protocol package: framing, pairing, presets, adaptation, audio sync math, and gesture rules. It does not boot the iPad or the Mac UI. The device list below is still required before calling a build accepted.

CI runs the same tests on `macos-15` with Xcode 16.4, then builds an unsigned IPA and the host. Lint is SwiftLint 0.65.1 `--strict` and `swift-format lint --strict`.

## Automated

```bash
swift test
swiftlint lint --strict
swift-format lint --strict --configuration .swift-format --recursive Sources Tests ios macos
```

| Suite | What it locks |
|---|---|
| `ProtocolTests` | Length caps, fuzz, input codec, unknown types, timing prefix |
| `BehaviorTests` | Pairing, rate limit, release on disconnect, presets, recovery, gestures |
| `AudioTests` | AAC framing, jitter schedule, route planner, volume scale |
| `TouchChromeTests` | Title bar versus content, flick, fill/restore, edge drawer, momentum sign |

## Device checklist

Run these on the iPad mini 3 and the Mac after installing the unsigned app and the host.

### Core

- [ ] Corners of the picture, including letterbox edges, move the pointer to the matching corner of the virtual display. A tap in the black bar does nothing.
- [ ] Single tap clicks. Double tap double-clicks. Drag moves a window. Release does not leave the button down.
- [ ] Two-finger scroll follows the fingers. With momentum on, a flick keeps scrolling briefly and then stops.
- [ ] Two-finger tap and two-finger long-press right-click.
- [ ] Sidebar Cmd/Opt/Ctrl/Shift stick until toggled off. Esc, Undo, and Redo arrive. Disconnect releases every stuck modifier and button.
- [ ] Software keyboard inserts text. A hardware keyboard shortcut (Cmd-C, Cmd-Z, arrows) arrives.
- [ ] Rotate the iPad. The picture and the pointer still agree. Held modifiers are released across the rotation.
- [ ] Unplug USB. Status changes to Wi-Fi without a manual reconnect. Plug USB back in and the host prefers USB.
- [ ] Background the iPad, then foreground it. The picture returns. A backgrounding event releases modifiers.
- [ ] 30-minute soak on Balanced while charging and on battery. Watch for heat, growing memory, and stuck keys.

### Security and metrics

- [ ] Wrong token: the iPad says pairing rejected and the Mac cursor does not move.
- [ ] Require pairing off on only one side still rejects an empty token. Off on both sides allows control. Turn it back on.
- [ ] Overlay FPS is frames actually handed to the display, not the encoder setting. Handoff and Capture→ack change when the link is busy. Capture→ack is larger than one-way video delay because it includes the reply. Input RTT is the ping, not glass-to-glass.

### Switches

- [ ] Clipboard on both sides copies a short string both ways. A string over 12 KB is not sent. Clipboard off does not paste.
- [ ] Three-finger swipes: left undo, right redo, up copy, down paste. Off when the switch is off.
- [ ] Pinch zooms the picture and a tap still hits the pixel under the finger. It does not pinch-zoom a Mac view.
- [ ] Command strip buttons fire. Hidden when the strip is off.
- [ ] Snap left, snap right, and fill move a window on the virtual display. A title-bar flick tiles a half or a quarter. Quit the host and the window returns to the main display.
- [ ] Double-tap inside a window still double-clicks. Double-tap on that window's title bar fills, then restores.
- [ ] Audio on both sides plays through the iPad speaker or headphones. Routes: all audio, selected apps, apps on the virtual display. Volume slider changes loudness. Mute-on-Mac stays unavailable.
- [ ] Right-edge swipe opens the action drawer and does not open iOS Control Center. Left-edge swipe opens a left sidebar.
- [ ] Trackpad mode moves the drawn cursor. Direct Touch does not.

### Presets and heat

- [ ] Balanced is the first connection: 1440×1080, 30 fps target.
- [ ] Safe is the smaller preset.
- [ ] Native is labeled experimental. If the iPad cannot decode it, the host leaves Native for Balanced. Confirm the SPS level is not advertised as 4.2.
- [ ] A warm thermal state steps quality down.

## Not in this build

Jailbreak cable-launch tweaks, UDP, HEVC, Pencil, measured glass-to-glass numbers, and screenshots. Placeholder images in `docs/assets/` are not captures.
