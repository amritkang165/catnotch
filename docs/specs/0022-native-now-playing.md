# 0022. Native now playing

**Date**: 2026-11-05
**Status**: Accepted

## Summary

Issue #23 (native rewrite, ADR 0001). What is playing, from the vendored mediaremote-adapter (unchanged, run under `/usr/bin/perl`): album art with a pulse on the closed Notch, a card with controls on the Home view, tinted with the art's colour. Swift only reads the adapter's JSON stream.

## Requirements

- **AC-1** Track, artist, art and play state show for any player MediaRemote sees (Spotify, a browser tab). Nothing shows when nothing is playing.
- **AC-2** Play or pause, next and previous on the card act on the current player.
- **AC-3** While audio plays the closed Notch shows the art, pulsing. A paused track shows the art still.
- **AC-4** The card is laid out like the macOS Now Playing: the art on the left, beside it the title, artist, controls and a progress bar with the time played and left under it (`01:26`, `-03:13`). The bar moves while the track plays and dragging it seeks. A track with no length (a live stream) shows no bar.
- **AC-5** The card is tinted with the art's dominant colour.
- **AC-6** The adapter is copied into the app (`Contents/Resources/mediaremote`). A missing adapter, or one that keeps crashing, turns the feature off and nothing else.

## Design

- `CatNotchCore/NowPlaying.swift`: `NowPlayingStream` folds the adapter's `data` and `diff` lines into one `NowPlaying` (a key set to null has gone away), `position(at:)` moves a playing track on from the adapter's timestamp, `Transport` holds the key numbers for `send`, `DominantColor` weights pixels by how colourful they are, `fraction(at:)` and `TrackTime.text` feed the progress bar.
- `CatNotch/NowPlayingModel.swift`: an `@Observable` model shared by every display. It runs `perl mediaremote-adapter.pl <framework> stream --micros --debounce=100`, feeds the lines to the stream, restarts it after a crash (3 times, 1 s apart, then stays off), sends transport keys with `send` and `seek` with `seek <micros>` (moving the bar at once, the stream confirms). Art is shrunk to 256 px once per track and its colour read from a 16 px copy.
- `NotchBody.swift`: `ClosedArt` (right wing, or the right edge without a hardware notch) and `NowPlayingCard` and `TrackProgress` on Home. The card is neutral dark glass with a hint of the tint, and fits the 260 tall open Notch. The progress bar hover uses an `activeAlways` tracking area, because SwiftUI `onHover` waits for the panel to be key.
- The Xcode project copies `native/mac/build/mediaremote` (made by `npm run build:helper`) into the app with a build phase; if it was not built the phase copies nothing.

## Out of scope

The player-focus click, lyrics, the Electron app's art cache. The drawing and the adapter are platform behaviour, checked by hand against Spotify and a browser tab.
