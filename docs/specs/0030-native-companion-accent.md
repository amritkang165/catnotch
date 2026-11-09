# 0030. Native companion accent

**Date**: 2026-11-08
**Status**: Accepted

## Summary

The Electron Notch has one `accent` (`avatarAccent` in `renderer/lib/catppuccin.ts`) that colours most of it: the cat's face, a bot's own colour, white for a photo. The native Notch only used it for the ambient glow. Now the same colour reaches the rest, read from the Electron build.

## Requirements

- **AC-1** Changing the companion or the flavour recolours, with no restart: the focus ring and time, the Start/Resume button (a dim pill while running), task rows, the closed Notch's focus ring, the calendar and reminders (today, Now, dots, headings, buttons), the shelf's drop target, and the glow behind the companion tile.
- **AC-2** The colour is `Character.accent(flavor:)`: the flavour's Mauve for the cat, the bot's own colour, white for a photo.
- **AC-3** Fixed colours stay fixed: now playing's own tint and progress bar, AI usage lavender and warning orange, mic and camera dots, Claude's waiting amber.

## Design

`NotchView` sets `\.companionAccent` once (`NotchBody.swift`); `FocusTile`, `ClosedFocus`, `TaskRow`, the calendar views, `ShelfWell` and `CompanionTile` read it. The Electron coat picker is not ported (the cat keeps Mauve, Electron's default).

## Out of scope

The status tile's usage page and the reminder and done views (no native counterparts yet). Colour is platform behaviour, checked by hand.
