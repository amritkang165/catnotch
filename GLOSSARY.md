# CatNotch

A notch-style bar at the top of the Mac screen that opens into music, a focus timer, tasks, a file shelf, AI usage, a calendar and Claude Code prompts.

## Language

**Supported platform**:
macOS, the only platform CatNotch is built, tested and released for.
_Avoid_: cross-platform, Windows support

**Notch**:
The bar at the top of the screen, closed by default and opened by hovering it.
_Avoid_: island, pill, bar (alone)

**Release**:
A version tag on `thecharydev/catnotch` that publishes the universal macOS build.
_Avoid_: Windows release, Store release

**Update**:
Replacing the installed CatNotch with a newer Release when the user asks for it in Settings. Never happens without the user pressing the button.
_Avoid_: auto-update, upgrade
