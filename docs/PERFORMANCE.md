# Performance

No latency, FPS, bitrate, or power numbers in this repository were measured on hardware. Preset tables in the README are **targets**. This document is the method to fill them in later. Do not paste a number here until the run that produced it is described.

## What the software already records

These counters exist so a later measurement has a defined clock. They are not results.

| Name | Definition | Not this |
|---|---|---|
| FPS delivered | Frames the iPad enqueues to `AVSampleBufferDisplayLayer` in one second | Encoder setting, or frames captured but dropped |
| Handoff | iPad receive timestamp to enqueue timestamp | Hardware decode time inside the display layer |
| Capture→ack | Host time from capture until `frameAck` returns | One-way video delay. The ack's return trip is included |
| Encode time | Time inside the encoder for that frame, when the host records it | End-to-end latency |
| Input RTT | `pong` receive time minus `ping` send time on port 9001 | Glass-to-glass |

Glass-to-glass needs an external camera aimed at both screens, or a photodetector. This app does not estimate it.

## Method

Use the iPad mini 3 (iPad4,7, iOS 12.5.8) and the Mac that will ship the host. Charge state, cable, and preset go in the notes.

1. Install the IPA and host from the same commit. Record the commit SHA.
2. Pair. Confirm the overlay shows USB or Wi-Fi as expected.
3. Hold a high-motion window on the virtual display for 60 seconds. Record delivered FPS, handoff, and capture→ack from the overlay at the start, middle, and end. Those three samples are the run. Do not average a different definition in.
4. Repeat on Balanced, Safe, and Native. If Native falls back, record the fallback and skip a Native FPS claim.
5. For input RTT, rest a finger so pings continue and read Input RTT three times.
6. For glass-to-glass, use a camera. Report the camera frame rate and how the flash or cursor blink was timed. Until that exists, leave the cell blank.

Thermal runs: note `ProcessInfo.thermalState` from the overlay. Do not disable the step-down to get a higher number.

## Target sheet

Fill the measured columns only after a run. Leave them `—` until then.

| Preset | Link | Delivered FPS | Handoff ms | Capture→ack ms | Input RTT ms | Glass-to-glass ms | Commit |
|---|---|---|---|---|---|---|---|
| Balanced 1440×1080 target 30 | USB | — | — | — | — | — | — |
| Balanced | Wi-Fi | — | — | — | — | — | — |
| Safe 1024×768 target 30 | USB | — | — | — | — | — | — |
| Native 2048×1536 target 30 | USB | — | — | — | — | — | — |

Bitrate targets (8 / 6, 4 / 3, 18 / 12 Mb/s) are encoder settings, not measured throughput.

## Why the targets look like this

- Balanced 1440×1080 is 6,120 macroblocks per frame. H.264 Level 4.1 MaxFS is 8,192, so the preset fits a level A7-class decoders are expected to play.
- Safe 1024×768 is 3,072 macroblocks. Level 3.1 MaxFS is 3,600.
- Native 2048×1536 is 12,288 macroblocks. At 60 fps that exceeds Level 5.0 MaxMBPS, so the preset is Main 5.1. OpenDisplay has decoded the mode on an iPad mini 3. XA's own measurement is still empty.

Those are specification checks, tested in `BehaviorTests.testPresetsMatchLevelLimitsAndBitrates`. They are not playback measurements.
