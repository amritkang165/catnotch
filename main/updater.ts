/**
 * Updates over the air, from GitHub Releases (electron-builder.yml `publish`).
 *
 * A build published with `--publish always` puts `latest.yml` beside the
 * installer; the installed app reads it, downloads a newer installer in the
 * background, and installs it by itself: once the PC has been left alone for
 * a minute (so the notch never restarts under someone's hand), or when the
 * app quits, whichever comes first. A dev run never checks.
 *
 * ponytail: the installer is not code-signed, so an update is trusted on
 * GitHub's HTTPS alone; sign the builds and set `publisherName` to have
 * electron-updater verify them too.
 */
import { app, BrowserWindow, ipcMain } from 'electron'
// A namespace import, read both ways, because the two builds load this
// CommonJS package differently and each broke on one form:
// - packaged (real ES module import): its exports sit under `default`, and a
//   named `autoUpdater` import is a SyntaxError that stops the app launching;
// - dev (webpack's CommonJS interop): there is no `default`, the exports are
//   the namespace itself.
import * as electronUpdater from 'electron-updater'

type Updater = typeof import('electron-updater')
const { autoUpdater } = ((electronUpdater as unknown as { default?: Updater }).default ?? electronUpdater) as Updater

export type UpdateState =
  | { status: 'dev' | 'idle' | 'checking' | 'none' | 'error'; version: string }
  /** A newer release exists; it cannot install itself, so Settings shows the brew line. */
  | { status: 'available'; version: string; next: string }

/** How often a running app looks again. */
const EVERY = 6 * 60 * 60 * 1000
let state: UpdateState = { status: app.isPackaged ? 'idle' : 'dev', version: app.getVersion() }

const publish = (next: UpdateState) => {
  state = next
  for (const window of BrowserWindow.getAllWindows()) window.webContents.send('update:state', state)
}

const check = () => {
  if (!app.isPackaged) return
  void autoUpdater.checkForUpdates().catch(() => publish({ status: 'error', version: app.getVersion() }))
}

export function startUpdater() {
  ipcMain.handle('update:get', () => state)
  ipcMain.handle('update:check', () => check())

  if (!app.isPackaged) return
  const version = app.getVersion()
  // The build is unsigned, so an update cannot install itself: only tell.
  autoUpdater.autoDownload = false
  autoUpdater.autoInstallOnAppQuit = false
  autoUpdater.on('checking-for-update', () => publish({ status: 'checking', version }))
  autoUpdater.on('update-not-available', () => publish({ status: 'none', version }))
  autoUpdater.on('update-available', (info) => publish({ status: 'available', version, next: info.version }))
  autoUpdater.on('error', () => publish({ status: 'error', version }))

  // Not at launch, with everything else starting: a minute in, then every six hours.
  setTimeout(check, 60_000)
  setInterval(check, EVERY)
}
