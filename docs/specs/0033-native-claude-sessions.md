# 0033. Native Claude sessions

**Date**: 2026-11-09
**Status**: Accepted

## Summary

GitHub issue #36 for the native app. The Electron Notch lists every Claude Code session (specs 0005, 0007) and the native one never did: it answers permissions and questions only, and cleans the `SessionEnd`, `UserPromptSubmit` and `Stop` hooks away. This brings the sessions over, with the issue's additions. Same hook protocol as Electron, so the entries and the port rule do not change.

## Requirements

- **AC-1** Sessions. Claude's `<config dir>/sessions/*.json` (one file per running session: pid, id, folder) is the list of live ones; a file whose process is gone is not one. Hook events say what each is doing: any event is `working`, `Stop` is `idle`, a request waiting on a click is `waiting`. A session with no news for 10 minutes goes `idle` (the last resort).
- **AC-2** Esc sends no `Stop`. A `working` session with no request waiting, whose transcript changed since the last look, is `idle` when the last `user` or `assistant` entry in the last 4 KB is the user message `[Request interrupted by user` (also `… for tool use]`) and is not older than the last hook event. A quiet transcript alone means nothing: long builds write nothing for minutes.
- **AC-3** Compacting. `PreCompact` is `compacting`, `PostCompact` is `working`, except `trigger` `manual` (a `/compact` typed by hand, which is a turn of its own) which is `idle`.
- **AC-4** A Claude page in the dock (terminal icon) while Claude Code is on, listing the sessions: project, `You:` and your last message (one line, 120 characters), CLI or VS Code, and the state (`Needs your input` for `waiting`).
- **AC-5** Hide. An × on each row hides the session until it has new activity (archived at or after its last activity). Kept in the store, forgotten after 30 days.
- **AC-6** Jump. A button on each row opens the app that owns the session: from its process, up the parents (`ps -axo pid=,ppid=,comm=`) to the first inside an `.app`. No window picking, no tmux, no Accessibility.
- **AC-7** Dropped: the closed Notch showed a spinner while a session worked. It was removed; the closed Notch stays quiet.
- **AC-8** Sound. Settings picks a system sound from a fixed list (None by default). It plays when a turn ends (`Stop` on a `working` session) and when a new request is queued. A name outside the list is never played, and no path is ever accepted. Already built (Allow always and the sound for requests): the "Allow always" pill and `updatedPermissions`.

## Design

`CatNotchCore/ClaudeSessions.swift`: `ClaudeSessions` (state, scan, interrupt, last message), `ClaudeArchive`, `ClaudeFocus.appPath(pid:ps:)`, `ClaudeSounds`. `ClaudeHooks` owns a `ClaudeSessions`, feeds it the reporting events and the requests, and scans every 5 s while running. `ClaudeSettingsFile` writes the five reporting hooks again (replied to at once, 5 s timeout). `ClaudeModel` holds the shown sessions, the archive and the sound; `NotchPage.claude` is in `pagesOff` while Claude Code is off.

## Not doing

The session chat (spec 0007), a Settings switch for the Claude page, and the Electron `claude:sound` preview of the Stop sound.
