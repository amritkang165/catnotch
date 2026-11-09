# 0034. Release plumbing and Bridge release

**Date**: 2026-11-09
**Status**: Accepted

## Summary

Issue #33 (native rewrite, ADR 0001). The tag workflow builds the native app with `xcodebuild` on a macOS arm64 runner and publishes a Release that installed 1.0.x apps can update to.

## Requirements

- **AC-1** The tag must equal the Xcode `MARKETING_VERSION` (no `v` prefix). A mismatch fails the workflow before anything is built or published.
- **AC-2** The build stages `CatNotch-VERSION-universal-mac.zip` (the legacy name; arm64 content, `CatNotch.app` at the zip root), `CatNotch.dmg` and `latest-mac.yml`.
- **AC-3** `latest-mac.yml` is in electron-builder's format: `version`, `files` (`url`, `sha512` as base64, `size`), `path`, `sha512`, `releaseDate`. The sha512 is the zip's.
- **AC-4** The workflow uploads the three files, marks the Release latest, and bumps the Homebrew cask (skipped without `HOMEBREW_TAP_TOKEN`). The cask has `depends_on arch: :arm64` and downloads `CatNotch.dmg`.

## Design

- `scripts/release-native.sh TAG` does AC-1 to AC-3 into `build/release/`, so running it locally is the dry run. `APP=` skips the build.
- `scripts/release-native.check.sh` checks a mismatched tag fails and a fake app stages the right names and sha512. Run by `test-macos.yml` and the release workflow.
- `.github/workflows/release-mac.yml` runs the check, `xcodebuild test`, the script, then publishes with `gh`.

## Manual check

A real 1.0.8 install finding and installing the Bridge release on a test tag is checked by hand. Not done in this change.

## Out of scope

Notarization, Sparkle, retiring `latest-mac.yml` (kept while 1.0.x installs exist).
