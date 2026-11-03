# 0018. Native Settings window shell

**Date**: 2026-11-03
**Status**: Accepted

## Summary

Issue #19 (native rewrite, ADR 0001). A Settings window opened by a global shortcut, with open at login, the display selector and Quit. Later feature tickets add their own controls to it.

## Requirements

- **AC-1** Cmd+Option+, opens Settings, or brings the open one to the front. If another app owns the shortcut, the app logs a warning and runs on.
- **AC-2** Open at login can be turned on and off (`SMAppService.mainApp`). The switch shows the real state each time the window is focused.
- **AC-3** The display selector (primary, all, or one connected display) changes which displays have a Notch, live, with no restart. A chosen display that is unplugged shows as the primary.
- **AC-4** Quit closes the app.

## Design

- `CatNotchCore`: `DisplaySelection.setting` (inverse of `init(setting:)`) and `StoreData.displaySelection`, saved under `selectedDisplayId`, the Electron key, so the import carries the old choice. Tested through the store.
- `SettingsWindow` (one `NSWindow` hosting a SwiftUI `Form`, closing hides it) and `GlobalShortcut` (Carbon hot key, no Accessibility permission) live in the app target.
- `NotchController` takes the store and follows `observe`, so the picker writes the store and every Notch syncs.

## Out of scope

The Update button (own ticket), sidebar sections and styling (added with the features), a configurable shortcut. The window, shortcut and login item are platform calls, checked by hand.
