# ADR 0008: Isolate CGVirtualDisplay

- Status: accepted
- Date: 2026-11-07

## Context

A virtual display on macOS 14 uses the private `CGVirtualDisplay` SPI. Copying declarations from a GPL project would break ADR 0001. Calling it from random Swift files would make the private dependency invisible.

## Decision

Keep the SPI in `macos/XADisplayHost/XAVirtualDisplay.m` and its header. Link with `-undefined dynamic_lookup`. Create the display on the main thread. Surface failure to the menu instead of substituting a fake display. On shutdown, move stranded windows back with public Accessibility APIs.

## Consequences

The SPI can break on an OS update and the host will say the display is unavailable. The rest of the Swift host does not import the private symbols.
