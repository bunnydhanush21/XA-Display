# XA Display manual acceptance

Run these on the iPad mini 3 and the Mac after installing the unsigned app and the host. Automated coverage is `swift test` (protocol, mapping, gestures, pairing, presets, adaptation). It does not replace this list.

## Core

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

## Security and metrics

- [ ] Wrong token: the iPad says pairing rejected and the Mac cursor does not move.
- [ ] Require pairing off on only one side still rejects an empty token. Off on both sides allows control. Turn it back on.
- [ ] Overlay FPS is frames actually handed to the display, not the encoder setting. Handoff and Capture→ack change when the link is busy. Capture→ack is larger than one-way video delay because it includes the reply. Input RTT is the ping, not glass-to-glass.

## Toggleable extras

- [ ] Clipboard on both sides copies a short string both ways. A string over 12 KB is not sent. Clipboard off does not paste.
- [ ] Three-finger swipes: left undo, right redo, up copy, down paste. Off when the switch is off.
- [ ] Pinch zooms the picture and a tap still hits the pixel under the finger. It does not pinch-zoom a Mac view.
- [ ] Command strip buttons fire. Hidden when the strip is off.
- [ ] Snap left, snap right, and fill move a window on the virtual display. Flick-to-tile does the same when touchscreen gestures are on. Quit the host and the window returns to the main display.
- [ ] Audio on both sides plays system audio. Audio off is silent. Dropped audio does not stall video.
- [ ] Saved presets restore Balanced, Safe, or Native across a relaunch.
- [ ] Sidebar moves to the right. Tap slop, double-tap window, and long-press time change behavior.
- [ ] Auto-connect off does not attach when the cable is plugged in. On attaches without a click.
- [ ] Title-bar double-tap sends fill. Edge swipe opens the sidebar. Precision draws the crosshair and slows the trackpad.

## Presets and heat

- [ ] Balanced is the first connection: 1440×1080, 30 fps.
- [ ] Safe is softer and lighter.
- [ ] Native is labeled experimental. If the iPad cannot decode it, the host leaves Native for Balanced without a manual reset. Confirm the SPS level is not advertised as 4.2.
- [ ] Force a warm thermal state if you can do it safely. Quality steps down. Nothing disables thermal protection.

## Not in this build

Jailbreak cable-launch tweaks, UDP, HEVC, Pencil, and camera-measured glass-to-glass numbers.
