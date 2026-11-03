# 0019. Native Notch chassis and styles

**Date**: 2026-11-03
**Status**: Accepted

## Summary

Issue #20 (native rewrite, ADR 0001). The Notch body: a closed 12-hour clock, a view switcher, and the Black, Transparent and Glass styles with the three Catppuccin flavours.

## Requirements

- **AC-1** The closed Notch shows a 12-hour clock. On a hardware notch it sits in the left wing; otherwise it centres in the closed Notch.
- **AC-2** The open Notch has a switcher (Home, Focus & tasks, Files) that moves between views.
- **AC-3** The style (`notchStyle`: black, transparent, glass) and flavour (`notchFlavor`: mocha, macchiato, frappe) are set in Settings, saved in the store under the Electron keys and followed live by every display. Old `translucent` reads as glass, `mica` and unknown as black.
- **AC-4** Glass uses Liquid Glass on macOS 26 and a material before that, tinted with the flavour's base colour. The hardware cutout stays black in every style.
- **AC-5** Looks right on a notched and a non-notched display.

## Design

- `CatNotchCore/NotchLook.swift`: `NotchStyle`, `Flavor`, `NotchPage`, `WallClock.text` and the store accessors. `NotchSize.closedWithWings` adds a wing either side of a hardware notch (so it stays centred on it and the hover rect matches what is drawn) and reports the cutout width.
- `CatNotch/NotchBody.swift`: the SwiftUI body (fill, clock, switcher). The clock redraws on the minute with `TimelineView`.
- Each view's page is only a title for now; features fill them as they land. Only the switcher state is per display and not saved.

## Out of scope

Opacity, blur, custom colour and accent (the Electron extras), the cat companion, wings for status items other than the clock. The look on screen is checked by hand: it is a platform draw.
