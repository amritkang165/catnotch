# 0028. Native in-app Update

**Date**: 2026-11-08
**Status**: Accepted

## Summary

Issue #32 (native rewrite, ADR 0001). The Update button in Settings: look up the latest Release, download its zip, check the checksum, swap the installed app in place and relaunch. Nothing downloads or installs until the button is pressed.

## Requirements

- **AC-1** The feed is the Release's `latest-mac.yml` (`version`, and per file `url` and base64 `sha512`). The arm64 zip (`-arm64-mac.zip`) is picked, else the Bridge release's `-universal-mac.zip`. A feed with no zip is an error.
- **AC-2** A release is offered only when its version is newer than the running one, compared number by number (`2.0.10` > `2.0.9`).
- **AC-3** A zip whose sha512 does not match is rejected before anything is unpacked, and the installed app is untouched.
- **AC-4** The swap sets the old app aside, moves the new one in, clears the quarantine flag and removes the old one. If the new app is missing or the move fails, the old app is put back.
- **AC-5** An app in a read-only folder or disk image reports `unwritable`, touching nothing; Settings says so before downloading and opens the Release page.
- **AC-6** Checking only reports; `install` runs only from the button. After a good swap the app relaunches itself. Any failure shows "Update failed" and leaves the old app in place.

## Design

- `CatNotchCore/Update.swift`: `UpdateFeed.parse`, `UpdateFeed.isNewer`, `UpdateInstall.sha512(of:)`, `.writable`, `.swap`, and `.install(zip:sha512:installed:)` (writable check, verify, unpack with `ditto`, swap, clean up), plus the `UpdateState` Settings shows.
- `CatNotch/UpdateModel.swift`: `@Observable`; downloads with `URLSession` (progress), calls `UpdateInstall.install`, relaunches via a detached `open`. Installing runs off the main actor; relaunch waits for this process to exit. A failed install can be retried; a failed check is shown separately. Debug builds never install.
- `SettingsWindow.swift`: an Update section with one button (Check, then Update to X).

## Out of scope

Automatic or background checks, signing, the Bridge release workflow (`latest-mac.yml` generation). The download and relaunch are platform behaviour, checked by hand.
