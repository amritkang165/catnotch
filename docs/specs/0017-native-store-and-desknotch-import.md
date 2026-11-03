# 0017. Native store and one-time DeskNotch import

**Date**: 2026-11-03
**Status**: Accepted

## Summary

Issue #18 (native rewrite, ADR 0001). The native app keeps its state in `catnotch-store.json` and imports the old DeskNotch store once.

## Requirements

- **AC-1** An old store in a temp folder is imported: tasks, focus log, shelf and settings land in the new store.
- **AC-2** The old `desknotch-store.json` is never written, so it is byte-identical afterwards.
- **AC-3** The import happens once. It only runs when `catnotch-store.json` does not exist, so a second launch keeps newer data (an unreadable new file starts clean instead of re-importing, and is moved aside to `catnotch-store.unreadable.json`). A store file missing a key loads with that key empty.
- **AC-4** A change made through the store reaches every observer, so a setting changed on one display shows on the others.

## Design

- `CatNotchStore` in `CatNotchCore`: `data`, `update { }`, `observe { }` (returns the stop function), `standard()` for `~/Library/Application Support/CatNotch` importing from `DeskNotch` beside it. An update that changes nothing does not save or notify, which stops echo loops.
- One instance is created in `AppDelegate` and shared by every display's Notch, so there is no cross-process sync like Electron's `store:changed`.
- `settings` is `[String: JSONValue]`, so the import is lossless and later features read typed keys. The old `todos` key is `tasks` here.
- Writes are synchronous and atomic. A missing or wrongly shaped old field imports as empty.

## Out of scope

Photo, pins, reminders, `aiConsent` and `claudeHooks` (their features import them later), shelf bookmarks, and wiring the display and fullscreen settings to the store. The store is used from the main actor.
