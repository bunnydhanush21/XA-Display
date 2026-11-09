# ADR 0007: Pair on port 9001, ignore video-port touch

- Status: accepted
- Date: 2026-11-07

## Context

The OpenDisplay-style video JSON includes `touch` and `scroll` with no secret. Keeping that path on the XA host would bypass any token.

## Decision

Require a token on input hello unless **both** the Mac `requirePairing` flag and the iPad hello flag are off. Compare tokens case-insensitively with hyphens and spaces stripped. The host drops video-port touch and scroll. Session ids come from the host. Sequence numbers are monotonic. Disconnect releases held buttons and modifiers.

## Consequences

OpenDisplay can still be the sender for basic video and its own touch path. XA Host will not honor that touch path. A stolen token is full control until it is regenerated. The token is redacted in diagnostics and must not be committed.
