# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# CatNotch

A notch style bar at the top of the screen (macOS only), a native Swift/SwiftUI app. Hover it and it opens into music, a focus timer, tasks, a file shelf, AI usage, a calendar and Claude Code prompts. Version is `MARKETING_VERSION` in the Xcode project; release details are in `README.md`.

## Run, build, test

Needs full Xcode. If `xcodebuild` complains about Command Line Tools, set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

- Build and run: open `CatNotch.xcodeproj` and run the `CatNotch` scheme.
- `scripts/build-adapter.sh`: build the vendored MediaRemote adapter into `build/mediaremote/` (needs `cmake`). The Xcode "Bundle mediaremote adapter" phase copies it into the app; without it the app still builds but now playing is off.
- Test: `xcodebuild test -project CatNotch.xcodeproj -scheme CatNotch -destination 'platform=macOS'` (Swift Testing). One test: `-only-testing:'CatNotchCoreTests/name()'` (the parentheses matter).
- `scripts/release-native.sh TAG`: stage a Release in `build/release/` (the dry run). `scripts/release-native.check.sh` self-checks it without Xcode.
- There is no lint script.

## Layout

- `CatNotch/`: the app target (AppKit window plumbing, SwiftUI views, `*Model.swift` observable models).
- `CatNotchCore/`: the library target. Pure logic that tests can reach: store, focus timer, tasks, layout, hover, Claude hooks and sessions, update, and so on.
- `CatNotchCoreTests/`: tests for `CatNotchCore`.
- `vendor/mediaremote-adapter/`: vendored MediaRemote adapter (perl script plus framework) used for now playing.
- `docs/specs/`: numbered build specs. Read the matching one before changing a feature. `docs/adr/` holds decisions.
- `packaging/homebrew/`: the cask template the release workflow fills in.
- `.github/workflows/`: `test-macos.yml` (tests on PRs and `main`) and `release-mac.yml` (tag release).

## Architecture

- **One panel per display.** `NotchController` and `NotchPanel` make a transparent, always on top panel per display (`DisplaySelection` decides which). `NotchHover` decides when the pointer is over the notch so the panel is click through elsewhere.
- **Persisted state.** One JSON file, `catnotch-store.json`, in `~/Library/Application Support/CatNotch` (`CatNotchStore`). On first launch it imports the old DeskNotch store once from `~/Library/Application Support/DeskNotch`. An unreadable store is moved aside, not overwritten.
- **Models in the app, logic in Core.** A feature is a `CatNotchCore/<Feature>.swift` with the testable logic, a `CatNotch/<Feature>Model.swift` that wires it to the system, and views. New Swift files must be added to `project.pbxproj` by hand (explicit file refs, no synced folders).

## Easy to miss

- Claude hook server (`ClaudeHooks.swift`, `ClaudeSettingsFile.swift`): it listens on a local port and writes hook entries into the user's `~/.claude/settings.json`. The entries must always match the live port, so they are re-synced on every launch. A stale port fails silently and no question reaches the notch. Do not launch the built app to try it unless you accept that it rewrites the real `~/.claude/settings.json`.
- A prompt is skipped when a terminal is in front (Claude's own prompt is already visible). VS Code is never skipped.
- `build/` is output. Do not edit it.
- CI runs `xcodebuild test` on a macOS arm64 runner. The app is Apple silicon only, macOS 14 or newer.
- Release: push a tag equal to `MARKETING_VERSION` with no `v` prefix (`2.0.0`); `release-mac.yml` builds and publishes. The 2.0.0 Release is the Bridge release: it keeps the old `CatNotch-VERSION-universal-mac.zip` and `latest-mac.yml` names so installed 1.0.x apps can update to it. The app is ad hoc signed, not notarized. Keep the bundle ID `com.thecharydev.catnotch` unchanged or updates install as a second app.
- Never touch the real `~/.claude` in tests. Point `CLAUDE_CONFIG_DIR` at a temp folder.
- Git flow: there is one long lived branch, `main`. There is no `master` and no `dev`.
  - Every change goes on a short branch off `main` (like `fix/something`). Never commit or push straight to `main`.
  - To ship, raise a pull request from that branch into `main`, then delete the branch.
  - Always confirm before each step: show the commit message and wait for a yes before `git commit`; wait for a yes before `git push`; wait for a yes before `gh pr create`. Approval for one step does not cover the next.
  - Do not run `git commit`, `git push` or `gh pr create` unless asked for that exact action (`.agents/rules/no_git_push.md`).

## Testing rules

- Framework is Swift Testing. Tests sit in `CatNotchCoreTests/`, one `<Feature>Tests.swift` per `CatNotchCore/<Feature>.swift`.
- Test the logic in `CatNotchCore`; keep views and AppKit glue thin.

## Specs

New work gets the next numbered file in `docs/specs/`. Keep specs small and name them `NNNN-short-name.md`.

## Agent skills

### Issue tracker

Issues live in GitHub Issues on `thecharydev/catnotch` (`origin`, via `gh`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-label vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
