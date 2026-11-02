# DeskNotch — design notes

Notes on the decisions that shape this codebase, written down so they don't
have to be re-derived later. How each feature talks to macOS is in
[HowItWorks.md](HowItWorks.md).

---

## 1. Why the notch lives in the renderer, not the main process

_Why the notch is a `<div>` inside a full-width invisible window instead of a small `BrowserWindow`, and what that costs._

### The change

The window used to *be* the notch: a 240×30 `BrowserWindow`, positioned at the
centre of the screen's top edge.

Now the window is an invisible strip spanning the full screen width, 500px tall,
and the notch is a `<div>` drawn inside it.

```
Before:                        After:
┌────┐  window = notch         ┌──────────────────────────┐ window (invisible)
│▓▓▓▓│  240×30                 │         ┌────┐           │ full width × 500
└────┘                         │         │▓▓▓▓│           │ notch = div
                               │         └────┘           │
                               └──────────────────────────┘
```

### Why

**Smooth expansion is otherwise impossible.** `setBounds` resizes a window in
discrete steps on the compositor's schedule — no easing, and it tears against a
transparent window. There is no version of window-resizing that looks like the
Apple notch. A CSS transition runs on the GPU with real easing. This is the
reason that matters; the rest are bonuses.

**The main process can't hot-reload.** A `BrowserWindow` is constructed once
with its options; editing the source doesn't change a live window, so every
tweak costs a full Electron restart. CSS hot-reloads. Since the notch's size,
shape and animation are now CSS, they hot-reload too — `main.ts` is set once and
then left alone.

**A renderer crash doesn't kill the app.** Main-process errors take the whole
process down. Keeping the frequently-edited, experimental code in the renderer
means a mistake costs one window, not the app.

### What goes where now

| Thing | Where | Restart needed? |
|---|---|---|
| Notch width, height, radius | `NotchChassis.tsx` | No |
| Expand size and animation | `NotchChassis.tsx` | No |
| Centering | `home.tsx` | No |
| Strip height (`STRIP_HEIGHT`) | `main.ts` | Yes |
| Click-through, always-on-top | `main.ts` | Yes |

**The one constraint:** the notch can only animate *within* the strip. It is
500px tall, and it has to hold the tallest view (Settings) plus the dock and the
apps bar floating under it, and their hover labels. Raising that limit is the
one visual change that still needs a `main.ts` edit.

### The cost

An invisible full-width window sitting over the top of the screen would swallow
every click meant for the windows underneath. `setIgnoreMouseEvents(true,
{ forward: true })` makes it click-through; the renderer then tells the main
process when the cursor is actually over the notch, and clicks are handed back
for as long as it stays there.

`forward: true` is load-bearing. It keeps delivering mouse-move events to the
renderer while click-through is on, which is what lets `onMouseEnter` fire at
all. Without it the notch is permanently dead.

---

## 2. `setAlwaysOnTop(flag, level)`

_The window-level ladder Electron exposes, and why `screen-saver` is used._

### The levels

Lowest to highest:

| Level | What it means |
|---|---|
| `normal` | Not on top — ordinary stacking. The default when `flag` is false. |
| `floating` | Above normal windows. What a plain `alwaysOnTop: true` gives you. |
| `torn-off-menu` | Above floating — for menus dragged off a menu bar. |
| `modal-panel` | Above torn-off menus — for modal dialogs. |
| `main-menu` | Above modal panels — the level of the system menu bar. |
| `status` | Above the main menu — status-bar items. |
| `pop-up-menu` | Above status items — open dropdown menus. |
| `screen-saver` | The top of the stack. What DeskNotch uses. |

A third argument, `relativeLevel`, shifts a window N levels above the one named.
macOS only.

### Why `screen-saver`, and the other two calls

These are real macOS window levels. `screen-saver` is the top of the stack, so
the notch stays above ordinary windows, the menu bar and the Dock.

Two more calls go with it in `main.ts`:

- `setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })` keeps the
  notch over a full screen Space as well. Without it the level alone does not
  reach there.
- `type: 'panel'` makes the window a panel, so it floats over other apps
  without making CatNotch the active app.

Whether the notch should show over a full screen app is a setting (Hide in
fullscreen). `main/fullscreen.ts` hides the window when the helper reports a
full screen app on the same display, and shows it again when that ends.

---

## 3. Main, renderer, and talking between them

_How the two Electron processes are split, what `main/preload.ts` is, where `window.bridge` comes from, and the three messaging patterns every hook in the renderer uses._

### Two processes

Electron runs two separate OS processes, and most confusion here comes from
forgetting which one a piece of code is in.

```
MAIN PROCESS                    RENDERER PROCESS
Node.js                         Chromium (a browser tab)

fs, os, child_process           React, DOM, CSS
BrowserWindow, Tray, Menu       window, document

no DOM                          no fs, no os

main/main.ts                    renderer/**
```

**Main** is Node: files, OS access, and window management. It has no DOM.
**Renderer** is a browser tab: React runs here. It has no Node APIs.

They share no memory. The only way across is a message.

The split is for security — the renderer runs web content, so handing it `fs`
would let any script loaded there read the disk.

### The preload bridge

`main/preload.ts` is the only file that can see both sides. It runs in the
renderer's process but before the page loads, so it has access to `ipcRenderer`
(a Node API) while the page itself does not.

It uses `contextBridge.exposeInMainWorld` to put a controlled object on
`window.bridge`:

```ts
// main/preload.ts
import { contextBridge, ipcRenderer, webUtils } from 'electron'

const handler = {
  send<T>(channel: string, value?: T) {
    ipcRenderer.send(channel, value)
  },
  invoke<T>(channel: string, ...args: unknown[]): Promise<T> {
    return ipcRenderer.invoke(channel, ...args)
  },
  on<T>(channel: string, callback: (...args: T[]) => void) {
    const subscription = (_event, ...args: T[]) => callback(...args)
    ipcRenderer.on(channel, subscription)
    return () => ipcRenderer.removeListener(channel, subscription)
  },
  pathOf(file: File) {
    return webUtils.getPathForFile(file)
  },
}

contextBridge.exposeInMainWorld('bridge', handler)
```

This puts `window.bridge` in the renderer. The renderer gets exactly these
four methods and nothing else — no raw `ipcRenderer`, no `fs`:

| Method | Direction | Use |
|---|---|---|
| `window.bridge.send(channel, value)` | renderer → main | fire-and-forget |
| `window.bridge.invoke(channel, ...args)` | renderer → main | ask, wait for answer |
| `window.bridge.on(channel, fn)` | main → renderer | subscribe to pushes; **returns an unsubscribe function** |
| `window.bridge.pathOf(file)` | renderer only | real disk path of a dropped `File` |

`window.bridge` is typed via `renderer/preload.d.ts`, so TypeScript knows its
shape everywhere in the renderer without importing anything.

### One-way: `send`

Fire a message, expect nothing back. The hover handling works this way —
the renderer cannot call `setIgnoreMouseEvents` itself, because that is a
window API and windows live in main.

```ts
// renderer — NotchChassis.tsx
window.bridge?.send('notch:hover', over)

// main — main.ts
ipcMain.on('notch:hover', (_event, isOver: boolean) => {
  mainWindow.setIgnoreMouseEvents(!isOver, { forward: true })
})
```

`'notch:hover'` is just a channel name. It only has to match on both sides.

### Two-way: `invoke` / `handle`

When the renderer needs an answer, `invoke` returns a promise and `handle`'s
return value resolves it.

```ts
// renderer
const battery = await window.bridge.invoke('battery:get')

// main — main/ipc/battery.ts
ipcMain.handle('battery:get', async () => {
  return { level: 80, charging: true }
})
```

### Main pushes to the renderer: `webContents.send` + `bridge.on`

Main can also push data without being asked. The renderer subscribes with
`window.bridge.on` and main fires with `webContents.send`. This is how live
state — mic/camera activity, battery changes, now-playing — reaches the page
without polling.

```ts
// main — fire whenever something changes
mainWindow.webContents.send('privacy:state', newState)

// renderer — subscribe once, stay in sync
window.bridge.on('privacy:state', (state) => setState(state))
```

### End-to-end example: `usePrivacy`

`renderer/hooks/usePrivacy.ts` uses both patterns in one hook and is a good
template for any feature that has live state:

```ts
export function usePrivacy() {
  const [state, setState] = useState<PrivacyState>({ ... })

  useEffect(() => {
    // 1. Subscribe to future pushes (main/ipc/privacy.ts → webContents.send → bridge.on)
    const unsubscribe = window.bridge?.on<PrivacyState>('privacy:state', setState)

    // 2. Ask for the current state right now (bridge.invoke → ipcMain.handle)
    window.bridge
      ?.invoke<PrivacyState>('privacy:get')
      .then(setState)
      .catch(() => {})

    return () => unsubscribe?.()  // ← clean up the ipcRenderer listener on unmount
  }, [])

  return state
}
```

**Step 1** (`bridge.on`) wires up a listener so the hook re-renders whenever
`main/ipc/privacy.ts` calls `webContents.send('privacy:state', …)` — for
example, each time the Swift helper reports a mic or camera change.

**Step 2** (`bridge.invoke`) fetches the current snapshot immediately so the
hook does not show empty state until the first push arrives. The two together
are the standard pattern for any hook that mirrors live main-process data.

The `unsubscribe` returned by `bridge.on` must be called on unmount. Skipping
it leaks an `ipcRenderer` listener every time the component remounts.

### Which one to reach for

| Need | Pattern |
|---|---|
| Tell main to do something | `bridge.send` / `ipcMain.on` |
| Ask main for a value | `bridge.invoke` / `ipcMain.handle` |
| Main pushes an update to the renderer | `webContents.send` / `bridge.on` |
| Subscribe + initial fetch (most hooks) | `bridge.on` + `bridge.invoke` together |

---

## 4. Why now playing runs in a child process

_Why the now-playing reader is a separate process, and how its lines become one state._

Reading what is playing needs Apple's private MediaRemote, which only Apple's
own `/usr/bin/perl` is still allowed to use. CatNotch ships the
`mediaremote-adapter` (in `native/mac/mediaremote-adapter`) and runs it under that
perl. It is a child process, so it cannot block main, which owns the windows and
relays every IPC message.

```
CHILD PROCESS            MAIN PROCESS              RENDERER
perl + adapter           main/mac/nowplaying.ts    useNowPlaying.ts

stream, JSON lines       keeps the current state   useState
                         webContents.send          listens
```

The same rule applies to every other slow native feature: if it can block, it
belongs in a child process.

### Lines carry only what changed

The adapter prints one JSON line per change. A line marked `diff` holds only the
keys that changed, and a key set to `null` has gone away. `nowplaying.ts` merges
each line into one state object, drops the nulls, and turns the whole state into
a track. Every line goes through the same merge, so the state cannot drift.

### The position is worked out in main

The adapter says where the track was at a timestamp. Main adds the time since
then while the track is playing, so the renderer gets where it is now.

### Album art is shrunk once per track

Art arrives as base64 in the line. Players can hand over a huge cover, and
decoding it every time a card showing it appeared stalled the notch's animation.
Main shrinks anything over 256 px to 256 px once, and keeps the result until the
track changes.

### Controlling playback

Play, pause, next and previous go through the adapter's `send` command, one short
`perl` call per click. Opening the player is `open -b <bundle id>`, after the id
passes a plain-characters check.

### Restarts

If the adapter exits, main clears the state (the media card goes away) and starts
it again after a second, up to 3 crashes.

---

## 5. Hit testing, because the window is not the notch

_Why click-through can't just be toggled on hover, how the cursor is polled against the notch's rectangle every 60ms, and why closing on `mouseleave` was unreliable._

The strip spans the whole width of the screen, so what it does with clicks
matters more than it would for an ordinary window.

`setIgnoreMouseEvents(false)` hands clicks to the **entire window**, not to
whatever is currently drawn. Toggling it on hover therefore made the full
strip swallow clicks meant for the title bars and menus underneath — a bug
that only shows up once the notch is pinned open and the user tries to click
somewhere else.

So the window now stays click-through permanently. The renderer reports the
notch's rectangle with a `ResizeObserver` — the shell springs between sizes, so
its bounds are only final once the animation settles — and the main process
polls the cursor against it every 60ms, taking clicks only while the pointer is
actually over the notch.

60ms is under the threshold where a click feels like it missed, and cheap
enough to leave running.

### More than one rectangle

The notch is no longer the only thing that takes clicks: the dock of views sits
beside or under it, and the apps bar floats under it. The renderer reports all
of them as a list, and the cursor counts as inside if it is in any.

### Closing by intent, with the real cursor

Closing on `mouseleave` failed in two ways. The notch changes size under a still
pointer (switch to the smaller Shelf and its edge jumps away), and past the edge
the window stops taking the mouse, so the page is told the pointer left the moment
it crosses. So leaving only starts watching: the main process, which polls the
cursor anyway, sends its real position whenever it moves (`notch:cursor`), and the
notch closes once the pointer is more than 48px away and still heading away.
Browser mouse events cannot be trusted for this: while the notch resizes, Chromium
sends moves for a pointer that never moved.

### Keyboard focus follows the pin, not the hover

The window has to be focusable for text fields inside it to accept typing.
Focusing on hover would then steal focus from whatever the user was typing in
elsewhere, so focus is taken only when the notch is pinned — which is also the
only time there is anything to type into.

---

## 6. Views

_How Glance, Desk, Shelf and Settings are structured, how the dock sits around the notch, and how temporary "peek" moments (screenshot, focus done) borrow the notch without a full view switch._

Everything cannot share one row. Music, tasks, a photo and settings would each
be a sliver.

The notch holds several views instead (Glance, Desk, Shelf, and Settings), and
each view sets the shell size it needs. There is no bar across the top when it
is open: the notch is all content. The views, settings and the lock are circles
on a small **dock** of their own, right against the notch, on the left, right or
bottom (a setting). Under it, the dock is centred and the notch grows about its
centre, so the button just pressed stays under the pointer as the view changes
size.

Settings sits after the views, separated from them: it opens a panel, it is not a
place to be, and grouping it with the views would say otherwise. The lock is last.

Some moments borrow the notch for a few seconds (a screenshot, a finished focus
session): a view of their own, the dock hidden, and the previous view back once
the notch folds away (`peek` in `home.tsx`).

### What the glance row shows is a setting

The zones are built from a list rather than fixed grid columns, so switching
one off closes its column and the shell shrinks to fit. A hidden panel leaves
no gap.

### One list, one copy

Tasks appear in both the glance row and the Tasks view. Both read and write the
same `useTasks` hook — two components each loading their own copy drift apart
the moment either changes.

---

## 6b. Around the notch: the dock and the apps tray

_The one-side-each rule that keeps the dock and the apps bar from colliding, and how both surfaces are included in hit testing._

Two things can sit outside the notch: the dock of tabs and the apps tray. One
rule keeps it tidy: **they never share a side.** Under the notch they stack in
one column, the tray against the notch and the dock below it; beside it they
hang from the screen's edge like small islands, the dock nearest. Settings greys
out a side the other one has, and Auto picks a free side (the right when the
dock is below, otherwise under the notch). The tray shows four apps under the
notch and two beside it, and scrolls for the rest; its + stays outside the
scroll so adding is always one click.

Both, and any popover of theirs (the favourites picker), are part of the notch
for hit testing and for "has the pointer left?", through the `data-notch-part`
attribute and a re-check every 250 ms while open.

## 6c. Materials

_Why the two styles (Default, Glass) are drawn the way they are, and what Glass costs._

The window is transparent, but the page itself cannot blur what is behind it (CSS
`backdrop-filter` only sees our own page). So Glass has two routes:

- **Native blur.** A small native addon (`main/mac/vibrancy.ts`,
  `native/mac/vibrancy/`) adds a macOS blur view to the window and cuts it to
  the shapes the renderer reports (the notch, the dock, the apps tray).
- **Capture fallback.** If the addon cannot load, the renderer shows a live screen
  capture, blurred, positioned per surface. One capture is shared by every
  surface (reference-counted), at 15 fps, while Glass is on.

Glass needs the Screen Recording permission. The window is excluded from capture
(`setContentProtection`), so a capture shows what is behind it. The cost: the
notch vanishes from screenshots and screen shares while Glass is on.

Only the background changes with the style; readings, tints and accents keep
their own colours.

## 7. Where main-process code lives

_A map of every file in `main/` and `main/ipc/`, what each one owns, and the rule for adding a new handler._

```
main/
  main.ts           window, hit testing, the cursor feed, lifecycle
  preload.ts        the renderer's bridge
  store.ts          the JSON file, and nothing else
  display.ts        one notch window per display
  fullscreen.ts     hide in fullscreen, tuck for browsers, terminal check
  settingsWindow.ts the Settings window
  updater.ts        looks for a newer release, reports it
  mac/
    helper.ts       the Swift helper: events, watches, questions
    nowplaying.ts   the now-playing adapter, media keys, focus the player
    spotlight.ts    recent files, screenshot folder (mdfind, mdls, defaults)
    apps.ts         most used and installed apps, icons, launch
    vibrancy.ts     the native Glass blur
  ipc/
    index.ts        registers every handler
    store.ts        get/set
    photo.ts        the file picker
    system.ts       Glass permission and capture source, hide in screenshots
    settings.ts     start at login
    limits.ts       AI plan limits (Claude, Codex), cached and backed off
    media.ts        media keys, opening the player
    files.ts        the shelf: describe, thumbnails, open, reveal, drag out
    screenshots.ts  the screenshot folder watch, discard, rename
    privacy.ts      mic/camera in use, Wi-Fi, Bluetooth (from the helper)
    battery.ts      charge and charging, from pmset
    usage.ts        CPU, GPU and memory
    calendar.ts     calendar events and join links (from the helper)
    claude.ts       the Claude Code hook server and prompts
    display.ts      the list of displays
native/mac/         the Swift helper, the adapter and the blur addon
```

`store.ts` had grown to hold the file, a photo picker, system stats and a login
item — four unrelated things behind one name. It now owns only the file, and
exports `readStore`/`writeStore` for features that happen to persist something.

A new handler means a new file in `ipc/` and one line in its index. Nothing
else is touched, and no file grows because a feature had nowhere else to go.

---

## Quick reference

_Where to find the code for the most common edits, and two known gotchas._

- **Notch appearance and animation** → `renderer/components/notch/NotchChassis.tsx`, hot-reloads.
- **Now playing** → `main/mac/nowplaying.ts` (main),
  `renderer/hooks/useNowPlaying.ts` (renderer).
- **A new IPC handler** → a file in `main/ipc/`, plus one line in its index.
- **Corner radius** → the tokens at the top of `renderer/styles/globals.css`.
- **Materials (Default, Glass)** → `Backdrop.tsx` in `renderer/components/notch/`, used by the notch, the dock and the apps tray; the Default colour is `CORNER_FILLS` in `NotchChassis.tsx`.
- **Strip height, always-on-top, click-through** → `main/main.ts`, needs a restart.
- **Padding inside the open notch** → `PAD` in `NotchChassis.tsx`; every view sizes itself from it.
- **A moment that opens the notch by itself** → `peek(view, ms)` in `renderer/pages/home.tsx`.
- **`npm run dev:norestart`** → rebuilds `main/` on save without relaunching Electron.
- **App won't start, `Cannot read properties of undefined (reading 'whenReady')`** →
  `ELECTRON_RUN_AS_NODE=1` is set in the environment. It makes Electron run as
  plain Node, so `require('electron')` returns a path string instead of the API.
  Unset it.
