# 0015. Native Notch panel: hover opens, click-through

**Date**: 2026-11-03
**Status**: Accepted

## Summary

A throwaway prototype of the native window model (ADR 0001, issue #16). One transparent, always-on-top `NSPanel` sits at the top centre of the main display. A closed Notch is drawn in it; hovering opens it, and the pointer leaving folds it back. Everywhere outside the Notch, clicks reach the app underneath. No timer polls the cursor.

## Context

Electron today uses a full-width 500px strip and polls the cursor every 60ms to toggle `setIgnoreMouseEvents`. The native app drops both. Code lives in `macos/` only; Electron is untouched.

## Requirements

- **AC-1** Hovering the closed Notch opens it. The pointer leaving the open Notch closes it.
- **AC-2** Outside the Notch, the panel ignores mouse events, so clicks reach the app beneath. Inside the open Notch, the panel takes them.
- **AC-3** No periodic timer reads the cursor. Input comes only from `NSEvent` monitors (global for other apps, local for ours) and one tracking area.
- **AC-4** Hit testing is inclusive of the screen's top edge: a pointer at the very top of the display counts as inside the closed Notch.

## Design

- One panel sized to the largest open state, pinned to the top centre of the primary display. Borderless, non-activating, transparent, level `.statusBar`, joins all Spaces and fullscreen spaces.
- Panel state is one bit: open or closed. `ignoresMouseEvents = !open`. Every pointer event (global monitor, local monitor, tracking area) calls the same update with `NSEvent.mouseLocation`.
- Hit rule (`NotchHover` in `CatNotchCore`, pure, tested): closed hit rect is the closed Notch; open hit rect is the open Notch. Hysteresis comes from the two sizes, no delay needed.
- The SwiftUI view animates between the closed and open size, anchored to the top centre.
- The panel overrides `constrainFrameRect` and the view ignores the safe area, so the drawn Notch and the hit rect agree even on a Mac with a hardware notch.
- Sizes are constants for now: closed 200x32, open 520x200. Hardware notch size is a later issue.

## Out of scope

Multiple displays, fullscreen hiding, real content, hardware notch sizing, glass styles. The prototype is checked by hand: hover opens and closes, a click beside the Notch reaches the window underneath.
