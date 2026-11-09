# ADR 0001: MIT iPad client, no GPL host

- Status: accepted
- Date: 2026-11-07

## Context

An iOS 12 receiver already existed under MIT (cuongpham1, commit `5ea40029`). OpenDisplay implements a similar video sender under GPL-3.0. Mixing those licenses in one app would make the whole tree GPL.

## Decision

Derive the iPad app from the MIT client and keep that notice in `LICENSE` and `NOTICE`. Write the Mac host as original MIT Swift. Do not copy OpenDisplay, Deskreen, or libusbmuxd source. The port 9000 layout (length prefix, JSON, Annex-B, `_opensidecar._tcp`) is implemented from the MIT client's documented behavior so an OpenDisplay 1.30.x sender can still drive basic video.

## Consequences

Keyboard, pairing, audio, and window actions require XA Display Host. Two senders at once are unsupported. A future GPL feature has to stay out of this tree or replace the license on purpose.
