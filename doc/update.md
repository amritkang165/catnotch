# What changed in this update

A walkthrough of the features added or fixed in this round of work that are still in CatNotch, so you can find each in the code and test it. Each section says **what** changed, **why**, **where** it lives, and anything to **watch out** for.

---

## Contents

1. [Hide in fullscreen hid on maximize](#1-hide-in-fullscreen-hid-on-maximize)
2. [Shrink over browsers](#2-shrink-over-browsers)
3. [Close button on the dock](#3-close-button-on-the-dock)
4. [Companion: Reminder mode (Tasks removed)](#4-companion-reminder-mode-tasks-removed)
5. [Typing in a card no longer toggles it](#5-typing-in-a-card-no-longer-toggles-it)
6. [Long tasks wrap](#6-long-tasks-wrap)
7. [Screenshot card: rename and Save to Shelf](#7-screenshot-card-rename-and-save-to-shelf)
8. [Look: shadows, border, Glass](#8-look-shadows-border-glass)
9. [Hide in screenshots](#9-hide-in-screenshots)
10. [Dock: icons, names, size, hiding when locked](#10-dock-icons-names-size-hiding-when-locked)
11. [Settings: simpler, fewer sections, new defaults](#11-settings-simpler-fewer-sections-new-defaults)
12. [Closed notch: task count removed](#12-closed-notch-task-count-removed)
13. [Update check](#13-update-check)
14. [Top bar no longer locks, GitHub link](#14-top-bar-no-longer-locks-github-link)

---

## 1. Hide in fullscreen hid on maximize

**What.** With Hide in fullscreen on, the notch also hid when you **maximized** a window. It should only hide for **real fullscreen**: a video's fullscreen button, a browser's fullscreen, games.

**Fix.** Only a window that covers the whole display, menu bar included, counts as fullscreen. A maximized window stops below the menu bar. It hides only on the monitor where the fullscreen window is.

**Where.** `main/fullscreen.ts`, fed by the native helper in `native/mac`.

---

## 2. Shrink over browsers

**What.** A setting, off by default: Settings → General → System → **Shrink over browsers**. While Safari, Chrome, Edge, Firefox, Brave, Arc, Opera or Vivaldi is the front app, the closed notch shrinks to a thin 6 px strip at the top edge, so it doesn't cover tabs. Hover the strip and the full notch opens as usual.

**Where.**
- `main/fullscreen.ts`: the same watcher also reports which app is in front, and tells each notch window `notch:tucked` true/false.
- `renderer/components/notch/NotchChassis.tsx`: the `tucked` prop shrinks the closed bar.

**Watch out.** If a fullscreen video is playing, hiding wins over shrinking.

---

## 3. Close button on the dock

**What.** A **power** button sits right of the lock on the dock (bottom or side). It quits CatNotch until you open it again.

**Where.** `renderer/components/notch/NotchChassis.tsx` (`QuitButton`), `main/ipc/settings.ts` (`app:quit`).

---

## 4. Companion: Reminder mode (Tasks removed)

**What.** The companion's **Tasks** mode is gone (tasks still live on the Home card and in the Focus & tasks tab). In its place is **Reminder**:

- **Folded card**: the next reminder's time, large, its message, and how long until it rings ("in 12 min").
- **Tap to open**: your reminders on the left (hover one for its × to remove it), and a **New reminder** form on the right: a time picker, an optional message, quick **10 min / 30 min / 1 hour** buttons, then **Set**.
- **When one is due**: the notch opens on its own, whatever it was showing. The companion rings (ripples pulse out, a bell swings on its shoulder) and the message sits beside it, centred, with **Got it** and **Snooze 5 min**. It stays open for a minute, longer while you hover.
- **Missed while closed**: a reminder whose time passed while CatNotch was not running rings as soon as it starts.

Anyone who had Tasks mode saved is moved to Reminder automatically.

**Where.**
- `renderer/hooks/useReminders.ts`: the list, saved in the store under `reminders` and synced across displays; wakes exactly when the next one is due (no polling).
- `renderer/components/widgets/CompanionTile.tsx`: `ReminderMode` and `ReminderForm`.
- `renderer/components/widgets/ReminderView.tsx`: the ringing card.
- `renderer/pages/home.tsx`: opens the notch when one comes due.
- `main/store.ts`: adds `reminders` to the saved data.

**Watch out.**
- You pick a **time**, not a date, so a reminder is always within the next 24 hours. A time that has already passed today means tomorrow.
- If you ignore a ring, it stays in the list marked "Now" but does not pop up again until the app restarts.

**Also renamed** in Settings → Companion → Mode: **Timer, Reminder, Clock** (they were Focus, Tasks, Time, which sounded too alike). **Sleep** now reads **11 PM – 6 AM**. The companion starts in **Clock** mode on a fresh install. The old AI mode was removed; AI usage is still its own Home card and on the closed notch.

---

## 5. Typing in a card no longer toggles it

**What was wrong.** In the companion, typing a task with spaces made the card open or close by itself, and the text you had typed disappeared.

**Why.** The card was an HTML `<button>` with a text field inside it. In Chrome, pressing **Space** (or Enter) in a field that sits inside a button counts as a click on the button. So every space toggled the card, which rebuilt the field and lost the text.

**Fix.** Cards are no longer real buttons; they behave like one only when the card itself has keyboard focus. This fixes every clickable card, not just the companion.

**Where.** `renderer/components/ui/tile.tsx`.

---

## 6. Long tasks wrap

**What.** A long task used to be cut off with "…". Now it wraps into a paragraph, both in the list and while you type it:

- Home **Tasks** card and the **Focus & tasks** tab: the text wraps; ticked tasks are struck through on every line.
- The add-task field grows line by line as you type (up to a few lines, then scrolls). **Enter** still adds the task.

**Where.** `renderer/components/widgets/QuickAdd.tsx` (a `<textarea>` that sizes itself with CSS `field-sizing: content`), `GlanceTiles.tsx`, `DeskView.tsx`.

---

## 7. Screenshot card: rename and Save to Shelf

**What.** When you take a screenshot, the card that pops up:

- shows the **file name** with a **pencil** icon. Click the pencil to get a proper text box with a ✓ button. Enter or ✓ saves, Esc cancels. The `.png` / `.jpg` ending is kept; an empty name or one that already exists is refused.
- says **"Save it to the Shelf to use later"** under the name ("Saved. Find it anytime on the Shelf" after saving).
- has **Save to Shelf**, **Open** and **Discard** (Discard moves it to the Trash).

**Where.** `renderer/components/widgets/CaptureView.tsx`; the rename itself in `main/ipc/screenshots.ts` (`screenshot:rename`). It only touches images inside your screenshot folder, the same safety rule as Discard.

The setting is called **Open on screenshot**, on by default.

---

## 8. Look: shadows, border, Glass

- **Shadows removed** from the notch, the dock and the apps bar.
- **The white line removed**: the notch had a thin white border and a white inner highlight, which showed as a line against the screen edge.
- Only **Default** and **Glass** remain.
- **Glass is easier to see.** It has a darker smoky tint, the background behind it is not brightened, and a thin light edge runs along the sides and bottom (none on top, so no line against the screen edge).

**Where.** `renderer/components/notch/NotchChassis.tsx`, `renderer/components/notch/Backdrop.tsx`.

---

## 9. Hide in screenshots

**What.** Settings → General → System → **Hide in screenshots**, off by default. Leaves the notch out of screenshots, screen recordings and screen sharing, using the window's "exclude from capture" setting.

**Glass always hides.** With Glass on, the switch shows as on, locked, with "Always on with Glass". Switch to Default to appear in screenshots.

**Where.** `main/ipc/system.ts` (`applyContentProtection`), applied when settings change and when a notch window is created.

---

## 10. Dock: icons, names, size, hiding when locked

- **Clearer names and icons**: Home (grid), **Focus & tasks** (checklist), **Files** (folder), Settings (**gear**). The **lock** stays as it was.
- **Tabs size**: Settings → Layout → Tabs → **Size**: Default, Large (1.25×), Larger (1.5×). Makes the dock buttons and icons bigger. The label text keeps its size.
- **Hidden while locked**: when the notch is locked open, the dock and the apps bar disappear until your cursor is back on the notch. Hover to bring them back (including the lock, to unlock).

**Where.** `renderer/pages/home.tsx`, `renderer/components/notch/ViewSwitcher.tsx`, `renderer/components/notch/NotchChassis.tsx` (`showChrome`, the `--dock-btn` / `--dock-icon` CSS variables).

---

## 11. Settings: simpler, fewer sections, new defaults

- **7 sections became 4**: **Notch** (Home cards, Closed notch), **Companion**, **Layout** (Tabs, Apps bar), **General** (Appearance, System).
- **Plain wording**: each row is a label and one control, like System Settings. A short note stays only where the label alone would not say enough.
- **Renamed**: Next task → Tasks, Right now → Status, Sleeps → Sleep, Catch screenshots → Open on screenshot, Ambient glow → Music glow, Album tint → Album colours, Tuck behind browsers → Shrink over browsers, Hide on Fullscreen → Hide in fullscreen.
- **A thin scrollbar** shows when a section is longer than the panel.
- **New-install defaults**: the Home cards are only **Companion** (in Clock mode), **Now playing** and **AI usage**. Tasks and Status start off. Existing users keep their own choices.

**Where.** `renderer/components/widgets/SettingsPanel.tsx`.

---

## 12. Closed notch: task count removed

The small dot and number on the closed notch was the count of open tasks. It has been removed.

**Where.** `renderer/components/notch/CollapsedStatus.tsx`.

---

## 13. Update check

**What.** The installed app looks at **GitHub Releases** a minute after starting, then every 6 hours. The build is not code-signed, so it cannot install itself: Settings → General → System shows the version, **Check for updates**, and when a newer one exists, the line `brew upgrade --cask desknotch`. In `npm run dev` it never checks; the row says "Updates run in the installed app".

**Where.** `main/updater.ts` (package `electron-updater`), `electron-builder.yml` (`publish`), the Updates row in `SettingsPanel.tsx`.

**Watch out.** Never change `appId` in `electron-builder.yml`, or an update installs as a second, separate app. The updater is loaded as a namespace import in `main/updater.ts` because the packaged app and dev load the package in different ways; keep it that way. Launch the packaged app before publishing, since dev passing is not enough.

---

## 14. Top bar no longer locks, GitHub link

- Clicking the notch's top bar used to lock it open by surprise. Now only the **lock button on the dock** locks it. Dropping a file on the notch still keeps it open until you unlock it. (`renderer/components/notch/NotchChassis.tsx`)
- A **GitHub** item sits at the bottom of the Settings sidebar, in every section. It opens the project's repo from the main process (`app:open-repo`), so the settings page cannot open any other address.

---

## Not done yet

- **Reminders with a date**, repeating reminders, and a reminder that keeps nagging when ignored.
- **Code signing and notarizing the build**, which would remove the first-open block and let the updater install by itself.
