# 0029. Native characters, photo, motion switches and ambient video

**Date**: 2026-11-08
**Status**: Accepted

## Summary

Issue #31 (native rewrite, ADR 0001). The companion engine of 0026 gets the rest of its cast, a picker and the three motion switches in Settings, the user's photo as a companion, and the ambient video along the bottom of Home while music plays.

## Requirements

- **AC-1** Settings, Companion offers, in this order: the Catppuccin cat, the orange cat, Claude Code's mascot, ghost, blob, clover, droid, alien, cloud and the user's photo. The choice is saved as `avatar` (the Electron key; unset is `ghost`) and shown on Home's companion tile at once.
- **AC-2** Each of **Look around**, **Sleep at night** and **React to events** (`companionLook`, `companionSleepOn`, `companionReact`, off unless saved on) turns its motion off for every character, the photo included where it applies.
  - Look around off: the head and eyes keep still (no wander, glance, idle jump) and the pointer is ignored and not read. A click still hops.
  - Sleep at night off: never asleep.
  - React to events off: no burst (hop) on a track, a task or the timer.
- **AC-3** The ambient video (`loopbg.mp4`, switch `ambientVideo`, on unless saved off) plays on Home while music plays and the Notch is open. Its hue turns towards the companion's colour (`AmbientShift`, the Electron `shiftFor` rules).

## Design

- `CatNotchCore/Characters.swift`: `CompanionCharacter` (colour, face place, ink, outline), the `StoreData` keys, `AmbientShift`.
- Outlines are the `bot-avatars` strings. `SVGPath` now reads arcs (`A`, as cubics); the droid's antenna is part of its outline. Face ink is `autoInk`. Only the Catppuccin cat follows the flavour. Claude Code's mascot (`claude`, orange 0xd77757) is our own blocky outline with square-ended eyes.
- `CompanionSim.looksAround`, `CompanionState.current(hour:bursting:sleeps:)`: the switches live in the engine, so they are tested without a window.
- `CompanionView.swift`: the tile draws the character or `CompanionPhoto` (a round picture that hops on a cheer or a click); `CompanionStill` draws the picker's buttons.
- `AmbientVideo.swift`: an `AVPlayerLayer` over `loopbg.mp4` (a bundle resource), graded by a Core Image pass (hue, saturation, exposure, contrast), screen blended at 0.32 and faded upward. It is only made while it shows.

## Out of scope

The Coat row (cat accents), the Sleep schedule row, the collapsed Notch cat in the left wing, the droid antenna drawn as a separate thin part, and the Zs.
