# 0027. Native Files page polish and drag to open

**Date**: 2026-11-07
**Status**: Accepted

## Summary

Follow-up to spec 0024. The Files view takes the Electron shelf's look, the Notch opens a little before the pointer reaches it, and a file dragged toward the Notch opens it on Files.

## Requirements

- **AC-1** The closed Notch opens when the pointer is within 8pt of it (`NotchHover.approach`), not only on it.
- **AC-2** While a file is being dragged, the Notch opens when the pointer is within 48pt of it (`NotchHover.dragReach`), and shows Files at once, wherever the page was. Only a drag that carries file URLs counts; a window drag or a text selection does not.
- **AC-3** An open Notch gets no extra reach: it closes when the pointer leaves it, as before.
- **AC-4** The shelf is a dashed well. Empty it says "Drop files here"; while a file is dragged toward or over the Notch it lights in the accent colour and says "Drop to keep it here".
- **AC-5** Shelf files show as chips (thumbnail or icon, middle-truncated name). A cross on the corner appears on hover, grows when pointed at, and removes the file. With two or more files a clear-all button and a count sit beside the row. The row scrolls to the newest file.
- **AC-6** Screenshots sit on their own card beside the shelf.

## Design

- `CatNotchCore/NotchHover.swift`: `isOpen(cursor:in:wasOpen:dragging:)` widens the closed rect by `approach`, or `dragReach` when `dragging`.
- `CatNotchCore/Shelf.swift`: `clearShelf`.
- `NotchController`: a global `leftMouseDown` monitor records the drag pasteboard's `changeCount`. A `leftMouseDragged` is a file drag when the count has changed since the press and the pasteboard holds file URLs (the pasteboard alone still holds the last drag's files).
- `NotchPanel.update(fileDrag:)` opens, switches `model.page` to `.files` and sets `model.fileDrag`, which `FilesPage` shows as lit.
- `FilesViews.swift`: `ShelfWell`, `ScreenshotsCard`, `FileTile` with the hover cross.

## Out of scope

"Drag all" (the Electron handle): SwiftUI's `onDrag` carries one item, so several files at once need an AppKit dragging session. A drag-out taking the file off the shelf (SwiftUI has no completion). Pointer and drag behaviour is platform behaviour, checked by hand.
