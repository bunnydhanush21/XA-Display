# ADR 0002: Reject oversized frames before reading them

- Status: accepted
- Date: 2026-11-07

## Context

The upstream receiver appended bytes until a 32-bit length was satisfied. A peer could advertise a multi-gigabyte frame and grow memory without bound.

## Decision

`FrameParser` rejects length 0 and any declared length above the cap before reading the body. Video caps are 2 MB payload and 3 MB buffer. Input caps are 256 KB payload and 512 KB buffer, enough for one clipboard image. Incomplete frames expire after 2 seconds. A malformed input frame drops the connection instead of resynchronizing by guess. Unknown input types are skipped.

## Consequences

A hostile length cannot allocate the declared size. A truncated stream costs a reconnect. Caps are part of the protocol tests, not a comment.
