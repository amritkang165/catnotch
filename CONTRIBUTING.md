# Contributing to CatNotch

Thanks for helping. CatNotch is a small native macOS app (Swift, SwiftUI). Bug reports, fixes, tests and docs are all welcome. By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md), and your contributions are licensed under the project's [MIT license](LICENSE).

## Before you start

- **Bug or small fix:** go ahead and open a pull request.
- **New feature or a big change:** open an issue first so we agree on the idea before you spend time on it. Issues labelled `ready-for-agent` or `ready-for-human` are the ones with a clear scope.
- **Security problem:** do not open an issue. See [SECURITY.md](SECURITY.md).

## Development environment

- A Mac on **Apple silicon** running **macOS 14** or newer. The app is arm64 only.
- **Xcode 26** or newer. CI uses Xcode 26.6.
- **cmake** (`brew install cmake`), only to build the now playing adapter.
- If `xcodebuild` complains about Command Line Tools, run it with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- There are no Swift packages to resolve. The only vendored code is `vendor/mediaremote-adapter/` (BSD-3).

## Build, run and test

```bash
scripts/build-adapter.sh      # once, or when the adapter changes. Without it the app builds but now playing is off.
open CatNotch.xcodeproj       # run the CatNotch scheme
xcodebuild test -project CatNotch.xcodeproj -scheme CatNotch -destination 'platform=macOS'
```

Run one test (the parentheses matter):

```bash
xcodebuild test -project CatNotch.xcodeproj -scheme CatNotch -destination 'platform=macOS' \
  -only-testing:'CatNotchCoreTests/startRunsDownAndFinishesOnce()'
```

**Be careful with Claude Code.** A normal launch of the app rewrites your real `~/.claude/settings.json` so its hook entries match the hook server's port (it saves a backup the first time). It only does this if you turned on Claude Code on the notch in Settings; leave that off while developing if you do not want it. Tests must never touch the real `~/.claude`: point `CLAUDE_CONFIG_DIR` at a temp folder.

## How the code is laid out

- `CatNotchCore/`: pure logic that tests can reach (store, focus timer, tasks, layout, hover, Claude hooks and sessions, update).
- `CatNotch/`: the app. AppKit window plumbing, SwiftUI views and `*Model.swift` observable models that wire Core to the system.
- `CatNotchCoreTests/`: Swift Testing tests, one file per feature.
- `docs/specs/`: small numbered build specs. Read the matching one before changing a feature. `docs/adr/` holds decisions, `GLOSSARY.md` the vocabulary.

A feature is a `CatNotchCore/<Feature>.swift` with the testable logic, a `CatNotch/<Feature>Model.swift` that wires it up, and views. Keep views and AppKit glue thin and test the logic in Core.

**New Swift files must be added to `CatNotch.xcodeproj/project.pbxproj` by hand.** The project uses explicit file references, not synced folders. A file that is not in the project is silently not built.

## Branches

There is one long lived branch, `main`. Branch off it and keep the name short, with a prefix:

`fix/hover-flicker`, `feat/keyboard-nav`, `docs/readme-install`, `chore/…`, `ci/…`

Never push straight to `main`. Open a pull request into it.

## Commits

Use a short imperative message with a type prefix, as in the history:

```
fix: wrap Binding setters in closures to avoid a compiler crash
feat: add native tasks with quick add and persistence
docs: README permissions and upgrade note
```

Types in use: `feat`, `fix`, `docs`, `test`, `ci`, `chore`. One logical change per commit.

## Pull requests

A pull request is ready for review when:

- The tests pass locally and in CI (`Tests (native)`).
- New or changed logic in `CatNotchCore` has a test. Bug fixes come with a test that fails without the fix.
- A new feature adds the next numbered spec in `docs/specs/` (`NNNN-short-name.md`, kept small).
- UI changes include a screenshot or recording.
- It does one thing. Unrelated cleanups go in their own pull request.
- The template checklist is filled in.

Do not commit anything under `build/`. Keep the bundle ID `com.thecharydev.catnotch` unchanged, or updates install as a second app.

## Review

CatNotch has one maintainer, so reviews are best effort and can take a few days. Expect a review on correctness, tests, and fit with the existing structure, and small requests to simplify. Feel free to ping the pull request after a week. Smaller, focused pull requests get merged faster.
