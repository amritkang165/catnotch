# 0032. Native dock lock

**Date**: 2026-11-08
**Status**: Accepted

## Summary

The Electron dock has a lock (`NotchChassis.tsx`, "Keep open" / "Unlock") that pins the Notch open. Native has the same button.

## Requirements

- **AC-1** The dock shows a lock after the view buttons, before Settings. Pressed, the Notch stays open with the pointer away, and the lock shows filled in a white circle ("Unlock"). Pressed again it unlocks and folds when the pointer is away.
- **AC-2** Locked, the dock steps away until the pointer is back on the Notch, so a locked Notch is just its content; hovering brings the dock and the lock back.
- **AC-3** A click in another app does not unlock (unlike the shortcut's open). Esc or the shortcut while open unlocks and closes. The lock is not saved: a relaunch starts unlocked.

## Design

`NotchModel.locked` and `pointerInside`; `NotchPanel.update` opens on `inside || waiting || pinned || locked` and records `pointerInside`; `ViewSwitcher` draws the button. No Core logic, so no new test: the behaviour is the panel's, checked by hand.
