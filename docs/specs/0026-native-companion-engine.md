# 0026. Native companion engine with the cat

**Date**: 2026-11-05
**Status**: Accepted

## Summary

Issue #30 (native rewrite, ADR 0001). The `bot-avatars` engine behind the Electron companion, ported to Swift, drawing the Catppuccin cat on Home's companion tile.

## Requirements

- **AC-1** The cat turns its head in 3D (yaw, pitch, roll), blinks and glances. It follows the pointer when it comes within three boxes, and a click makes it hop and turn right round.
- **AC-2** Busy (a new track, a task done, the timer changing) it hops, every third hop with a full turn, and laughs now and then. Asleep (23:00 to 06:00) it has its head down, breathes slowly and nods. A burst beats sleep.
- **AC-3** The face is the notch flavour's Mauve, the bow its Red (Pink when those match), the body its base. Changing the flavour recolours the cat.
- **AC-4** It draws only while Home is open, at 30 frames a second, and holds still under Reduce Motion.
- **AC-5** The idle cost is measured and noted on the ticket.

## Design

- `CatNotchCore/CompanionSim.swift`: `CompanionSim`, a value type with no clock (`update(dt)`), seeded, so a test runs a day in a blink. A line by line port of `BotAvatarSim` without the whirl and the tunable jump. `CompanionState.current(hour:bursting:)` is the mood rule.
- `CatNotchCore/CompanionDraw.swift`: `SVGPath` (`M L H V Q C Z`, absolute and relative; arcs return nil), `Shade` (HSL lightness), `CompanionLook` (colours from `Flavor`) and `CompanionRenderer`, which draws the outline as 17 shaded slices tilted by yaw, pitch and roll, then the eyes on the head's sphere, then the bow, all on a `CGContext`.
- `CatNotch/CompanionView.swift`: a `Canvas` in a 30 fps `TimelineView`, a driver that reads `NSEvent.mouseLocation` each frame (so it works while the panel is not key), and `CompanionTile`, which replaces the placeholder.

## Out of scope

(Characters, arcs, the photo and the Settings switches: done in 0029.)

The Electron Settings (character picker, coat, Look around, Sleep at night, React to events), the other characters, the photo and the collapsed Notch cat (#31). The plastic matcap shading: the `smooth` look the library falls back to is used. Arcs in the path parser: #31 needs them for the other outlines. The Zs while asleep.

## Idle cost

Measured by `idleFrameCost` in `CompanionTests`: see the ticket.
