# 0021. Native tasks

**Date**: 2026-11-03
**Status**: Accepted

## Summary

Issue #22 (native rewrite, ADR 0001). The task list on the Focus & tasks view: quick add, tick, remove, and the done tasks folded away.

## Requirements

- **AC-1** A task can be added, completed (and un-completed) and removed. Blank text adds nothing; text is trimmed, kept to 200 characters, and newlines become spaces.
- **AC-2** Tasks survive a relaunch (`tasks` in the store, saved on every change).
- **AC-3** Tasks in the old DeskNotch store (`todos`, with their `due` day) appear after the one-time import and keep their `due`.
- **AC-4** The view shows the open tasks under a line to type on; done tasks fold under "N done" (show, hide) and "Clear" removes them.

## Design

- `CatNotchCore/Tasks.swift`: `StoreData.addTask`, `toggleTask`, `removeTask`, `clearDoneTasks`, `openTasks`, `doneTasks`, and the matching `CatNotchStore` calls that save and notify.
- `CatNotch/TaskModel.swift`: an `@Observable` mirror of the store shared by every display's Notch, as `FocusModel` is.
- `NotchBody.swift`: `TasksList` and `TaskRow` beside the focus tile. The open Notch grows to 700 x 260 to fit them, and the panel can become key so the add field takes typing (it still does not activate the app).

## Out of scope

Due days and the calendar link (spec 0008 is Electron), the companion's task link, the glance row on Home. The drawing and typing are platform behaviour, checked by hand.
