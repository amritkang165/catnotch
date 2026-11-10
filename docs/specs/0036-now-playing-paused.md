# 0036 Now playing stays while paused

Issue #38. A paused song stays on the Notch with a Play button instead of vanishing. Builds on [0022](0022-native-now-playing.md).

## Requirements

- **AC-1** While a track is loaded but paused, the Home card still shows it (art, title, artist, progress) and its button reads Play and resumes it. Playing is unchanged: pulse, Pause.
- **AC-2** The closed Notch shows the paused track's art, still: no pulse, no ambient video. The clock moves over as it does while playing.
- **AC-3** A paused track stays for 30 minutes, then the card and the art go (a song paused for hours is stale). Playing again, or a new track, starts the 30 minutes again. When the player quits or has no track the card goes at once, as before.
- **AC-4** The Home layout is the same width as while playing (`NotchLayout.musicWidth`). Settings "show music" off still hides the card.

## Design

- `NowPlayingModel.hasTrack`: a track is loaded and not stale. `expired` is set by a 30 minute task started when the stream turns paused and cancelled when it plays or the track goes.
- `NotchBody.swift`: the card, the Home width and the closed art follow `hasTrack`; the ambient video still follows `isPlaying`. `PulsingArt` takes `playing` and stops its clock and glow when paused.
- The adapter keeps reporting a paused track (`playing: false` in a diff, title kept): `NowPlayingTests.diffMergesAndNullRemoves`. Checked by hand against Spotify, Apple Music and a browser tab.

## Out of scope

A Play button on the closed Notch itself; a different pause timeout in Settings.
