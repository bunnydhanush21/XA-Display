# ADR 0003: Pointer injection is CGEvent, not synthesized touch

- Status: accepted
- Date: 2026-11-07

## Context

The product copies some gestures from a touchscreen MacBook: title-bar fill, flicks, loupe, traffic lights, edge actions. macOS private touch synthesis (`NSTouch`, undocumented direct-touch events) would pretend the iPad is a touchscreen and would break without notice.

## Decision

Inject mouse, scroll, and keys with public `CGEvent`. Move and press windows with public `AXUIElement`, including `AXPress` on traffic lights and menu items. Remote zoom is a key binding (`Command-=` / `Command-Minus` unless a per-app binding says otherwise). Do not post a magnify event. Say this in the README and the host menu.

Direct Touch waits until a tap, drag, or long-press is known before mouse-down. Content double-taps are clicks. Title-bar double-taps are the only double-taps that fill a window.

## Consequences

Apps that look for real touch will not see one. Hit targets are enlarged on the iPad, not inside AppKit. MIDI and multitouch app integrations stay on the roadmap.
