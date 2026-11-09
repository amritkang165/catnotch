# 0016. Native display rules and fullscreen hiding

**Date**: 2026-11-03
**Status**: Accepted

## Summary

Issue #17 (native rewrite, ADR 0001). The Notch is sized to the hardware notch, one panel is made per target display, and a panel hides while a fullscreen app fills its display.

## Requirements

- **AC-1** On a notched Mac the closed Notch is the hardware notch size (read from `NSScreen`, no helper). Elsewhere it is 200x32.
- **AC-2** Display rules: `all` gives every display, `chosen` gives that display, `primary` (also unset or unreadable) gives the primary. A chosen display that is unplugged falls back to the primary. The primary is the first `NSScreen`.
- **AC-3** A panel hides while a fullscreen app fills its display, and returns, closed, after.
- **AC-4** Fullscreen and foreground-app parsing is pure and tested in `CatNotchCore`, with the terminal tests ported from `main/fullscreen.test.ts`.

## Design

- `DisplaySelection`, `NotchSize`, `ForegroundState` (with `WindowInfo`, `DisplayBounds`) in `CatNotchCore`. Detection is ported from the Swift helper: a layer 0 window of the frontmost app covering a display within 2pt, menu bar included, is fullscreen; the display is the one the windows overlap most.
- `NotchController` owns one `NotchPanel` per target display and the pointer monitors. `NotchPanel` is per display: it finds its `NSScreen` by id and sizes its closed Notch from it.
- No polling timer. The foreground is re-read on app activation, Space change and screen change, plus re-checks at 0.3s, 0.7s and 1.4s because the window list lags the Space switch animation. A screen change re-reads it too. CatNotch itself being frontmost leaves state as it was.

## Out of scope

The saved `selectedDisplayId` and `hideOnFullscreen` settings (no store yet: `selection` defaults to primary, hiding is always on), tucking for browsers, and showing over fullscreen while a Claude request waits. Multi-display and fullscreen are checked by hand; the logic is tested.
