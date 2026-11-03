# 0020. Native focus timer

**Date**: 2026-11-03
**Status**: Accepted

## Summary

Issue #21 (native rewrite, ADR 0001). The focus timer: a ring and time left on the closed Notch while a session runs, a Start, Pause and Reset tile on the Focus & tasks view, the focus log, and the timer controls in Settings.

## Requirements

- **AC-1** A session can be started, paused, resumed and reset. When the time runs out it finishes. Starting after a finish begins a new session.
- **AC-2** While a session runs, the closed Notch shows a ring and the time left (`m:ss`) instead of the clock. A paused session does not take the closed Notch.
- **AC-3** A finished session is logged once (`focusLog`, the Electron key: `at` ms since the epoch, `minutes` rounded from the length) and the log keeps 90 days. The log survives a relaunch.
- **AC-4** The Focus & tasks view shows the tile (ring, time, Start, Pause, Reset) and today's tally.
- **AC-5** Settings has the session length (`focusMinutes`, default 25, the lengths the Electron app offers) and the same Start, Pause and Reset.

## Design

- `CatNotchCore/FocusTimer.swift`: `FocusTimer`, a value type with no clock of its own (every call is given `now`), so it is tested without waiting. `FocusLength` holds the lengths and `m:ss` text. `StoreData.focusMinutes`, `CatNotchStore.logFocus` and `StoreData.focusToday`.
- `CatNotch/FocusModel.swift`: one `@Observable` model for the app, shared by every display's Notch and Settings. It wakes once a second only while a session runs, finishes it and logs it.
- The closed ring and the tile are drawn in `NotchBody.swift`; the Settings controls in `SettingsWindow.swift`.

## Out of scope

The week chart, the companion and task link on the tile, the finish sound or notification, keeping a running session across a quit (the Electron app does not either). The drawing is a platform draw, checked by hand.
