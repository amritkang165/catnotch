# 0025. Native system glance tiles

**Date**: 2026-11-05
**Status**: Accepted

## Summary

Issue #26 (native rewrite, ADR 0001). Battery, Wi-Fi, Bluetooth, headphones, microphone and camera, and the most used apps, on the Notch. All of it is system notifications: no timer runs.

## Requirements

- **AC-1** Each tile reflects real state and updates live: battery on a charge step or power change, Wi-Fi on a link, power or network change, mic and camera when a device starts or stops, Bluetooth when the Notch opens or an audio output comes or goes.
- **AC-2** Battery parsing (`pmset -g batt`) lives in `CatNotchCore` and passes the tests ported from `main/ipc/battery.test.ts`.
- **AC-3** The closed Notch shows an orange dot while the microphone is in use and a green one while the camera is. The Home strip shows a chip for each.
- **AC-4** Headphones that connect replace the clock on the closed Notch for 1.4 s, with their name. Outputs already connected at launch are not news.
- **AC-5** A missing capability turns only that tile off: no battery (desktop Mac), no Wi-Fi hardware, no connected Bluetooth devices, no Spotlight launch counts. Without Location the Wi-Fi tile says "Wi-Fi" instead of the network name.
- **AC-6** The most used apps (Spotlight launch count, top 8, this app left out) sit on the strip; a click opens one.

## Design

- `CatNotchCore/Glance.swift`: `BatteryState(pmset:)` and `isLow`, `Headphones` (worn names, tidy name, `arrival`), `TopApps` (`rank`, `counts` from `mdls`), `Wifi.signal`, `BluetoothDevice.connected(profiler:)` (from `system_profiler -json`).
- `CatNotch/SystemModel.swift`: an `@Observable` model shared by every display. IOKit power source notification, CoreAudio and CoreMediaIO property listeners, CoreWLAN events, and one-shot `pmset`, `system_profiler`, `mdls` runs off the main thread. Bluetooth is read when the Notch opens (at most every 10 s) and on an audio output change; apps at most every 30 minutes.
- `CatNotch/GlanceViews.swift`: `GlanceRow` under the Home cards, `PrivacyDots` and `ClosedHeadphones` on the closed Notch. The open Notch grows to 700 x 300.
- Location is asked for once at launch (the Wi-Fi name needs it); the Xcode project carries the usage strings.

## Out of scope

Which app uses the mic or camera (macOS only says which device runs), the Electron favourites picker, the CPU, GPU and memory usage tile. The listeners and drawing are platform behaviour, checked by hand.
