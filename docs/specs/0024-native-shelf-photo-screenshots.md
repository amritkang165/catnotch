# 0024. Native shelf, photo and screenshots

**Date**: 2026-11-05
**Status**: Accepted

## Summary

Issue #25 (native rewrite, ADR 0001). The Files view: a shelf that takes dropped files and drags them back out, the recent screenshots, and a photo chosen in Settings.

## Requirements

- **AC-1** Dropping files on the open Notch puts them on the shelf (and shows the Files view). A shelf file drags out into another app, opens on click, and shows in Finder or leaves the shelf from its menu. A file already on the shelf is not added twice.
- **AC-2** A shelf file that was moved or renamed is still found: each item keeps a bookmark beside its path, and the bookmark wins. An item whose file is gone (or in the Trash) shows dimmed and does nothing. Shelf paths from the old DeskNotch store get a bookmark the first time their file is found.
- **AC-3** A photo picked in Settings is kept across relaunches, by bookmark, and can be removed. A photo from the old store (a data URL) is written to `photo.<ext>` beside the store on import.
- **AC-4** The Files view lists the newest screenshots from the folder macOS saves them to (the `com.apple.screencapture` `location`, else the Desktop). A new capture shows up after macOS saves it. Only files macOS flags as screenshots count, whatever the system language.

## Design

- `CatNotchCore/Shelf.swift`: `FileRef` (path plus bookmark; decodes a bare path string, so old stores still read), `StoreData.shelf` / `photo`, `addToShelf`, `removeFromShelf`, `FileRef.resolve()`. Plain bookmarks, not security scoped: the app is unsandboxed, so they already do what the shelf needs.
- `CatNotchCore/Screenshots.swift`: `Screenshots.folder(location:home:)` and `Screenshots.newest(in:limit:isCapture:)`, pure so tests need no Spotlight.
- `CatNotchStore`: the one-time import also carries the old photo.
- `CatNotch/ShelfModel.swift`, `ScreenshotModel.swift`: `@Observable` mirrors shared by every display. The screenshot model watches the folder with a `DispatchSource` (no polling) and reads the screenshot extended attribute macOS writes (`com.apple.metadata:kMDItemIsScreenCapture`; Spotlight can lag or skip it), looking again a few times because the flag can land after the file.
- `CatNotch/FilesViews.swift`: the Files page (shelf row, screenshots row), a QuickLook thumbnail with the file icon as fallback.
- `NotchView` takes the drop; `NotchController` also listens for `leftMouseDragged`, so a file dragged to the Notch opens it.
- Settings: a Photo section (Choose, Remove).

## Out of scope

The Notch opening by itself on a screenshot, "drag all", a drag-out taking the file off the shelf (SwiftUI has no completion), the companion showing the photo (a later issue), a screenshot copied to the clipboard only. Drop, drag, thumbnails and the folder watch are platform behaviour, checked by hand.
