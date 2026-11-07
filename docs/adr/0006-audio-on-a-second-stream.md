# ADR 0006: Route audio on its own capture stream

- Status: accepted
- Date: 2026-11-07

## Context

A mute-and-mirror switch does not let the person pick apps. Putting audio in the video stream couples A/V failure. Opus needs a third-party codec. Public device mute silences the speakers and usually the capture tap as well.

## Decision

Keep `capturesAudio = false` on the video stream. Start a second `SCStream` with `capturesAudio = true`, `excludesCurrentProcessAudio = true`, 48 kHz, stereo. Modes: all system audio, an include list of bundle ids, or bundles whose windows intersect the virtual display. Encode AAC-LC (1024-sample packets) when AudioToolbox accepts the converter, otherwise PCM. Stamp `hostTimeMs`. The iPad jitters (60 ms target, drop after 140 ms, queue cap 6). Volume scales PCM on the iPad. Document mute-on-Mac as unavailable.

## Consequences

Two capture sessions. Opus stays out. Empty include lists do not start capture. Xcode 16.4 renamed `includingApplications` to `including` on `SCContentFilter`.
