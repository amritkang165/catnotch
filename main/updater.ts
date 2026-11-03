/**
 * Updates, from GitHub Releases (electron-builder.yml `publish`).
 *
 * The installed app reads `latest-mac.yml` beside the build and tells Settings
 * when a newer one exists. Nothing downloads until the user presses Update:
 * then the universal zip is fetched, its sha512 checked, swapped in place of
 * the app, and the app relaunches. A dev run never checks.
 *
 * ponytail: the build is not code-signed, so an update is trusted on GitHub's
 * HTTPS plus the sha512; sign the builds to have macOS keep its permission
 * grants (Calendar, Location) across updates.
 */
import { execFileSync } from 'node:child_process'
import { createWriteStream, mkdirSync, rmSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { Readable } from 'node:stream'
import { pipeline } from 'node:stream/promises'
import { app, BrowserWindow, ipcMain, net, shell } from 'electron'
import { pickZip, swapApp, verifySha512, writable, type ReleaseFile } from './updateInstall'
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
  /** A newer release exists; the Update button in Settings installs it. */
  | { status: 'available' | 'installing' | 'failed'; version: string; next: string }
  | { status: 'downloading'; version: string; next: string; percent: number }

/** How often a running app looks again. */
const EVERY = 6 * 60 * 60 * 1000
const RELEASES = 'https://github.com/thecharydev/catnotch/releases'
let files: ReleaseFile[] = []
let state: UpdateState = { status: app.isPackaged ? 'idle' : 'dev', version: app.getVersion() }

const publish = (next: UpdateState) => {
  state = next
  for (const window of BrowserWindow.getAllWindows()) window.webContents.send('update:state', state)
}

const busy = () => state.status === 'downloading' || state.status === 'installing'

const check = () => {
  if (!app.isPackaged || busy()) return
  void autoUpdater.checkForUpdates().catch(() => publish({ status: 'error', version: app.getVersion() }))
}

/** Download, check, swap in and relaunch. Only ever runs from the Update button. */
async function install() {
  if (state.status !== 'available' && state.status !== 'failed') return
  const { version, next } = state
  const fail = () => publish({ status: 'failed', version, next })
  const zip = pickZip({ files })
  // This app: .../CatNotch.app/Contents/MacOS/CatNotch
  const installed = dirname(dirname(dirname(app.getPath('exe'))))
  const work = join(dirname(installed), '.catnotch-update')
  // Run from a DMG or a read-only folder: it cannot replace itself, so say so
  // before downloading anything and point at the release page instead.
  if (!writable(dirname(installed))) {
    void shell.openExternal(`${RELEASES}/latest`)
    return fail()
  }
  // At once, so a second click cannot start a second install.
  publish({ status: 'downloading', version, next, percent: 0 })
  try {
    if (!zip) throw new Error('no zip in release')
    rmSync(work, { recursive: true, force: true })
    mkdirSync(work)
    const file = join(work, 'update.zip')
    const res = await net.fetch(`${RELEASES}/download/${next}/${zip.url}`)
    if (!res.ok || !res.body) throw new Error(`download ${res.status}`)
    const total = Number(res.headers.get('content-length')) || 0
    let done = 0
    let shown = 0
    const body = Readable.fromWeb(res.body as never)
    body.on('data', (chunk: Buffer) => {
      done += chunk.length
      const percent = total ? Math.floor((done / total) * 100) : 0
      if (percent !== shown) publish({ status: 'downloading', version, next, percent: (shown = percent) })
    })
    await pipeline(body, createWriteStream(file))
    if (!(await verifySha512(file, zip.sha512))) throw new Error('sha512 mismatch')
    publish({ status: 'installing', version, next })
    execFileSync('/usr/bin/ditto', ['-x', '-k', file, work])
    const result = swapApp(join(work, 'CatNotch.app'), installed)
    rmSync(work, { recursive: true, force: true })
    if (result !== 'ok') return fail()
    app.relaunch()
    app.exit(0)
  } catch {
    rmSync(work, { recursive: true, force: true })
    fail()
  }
}

export function startUpdater() {
  ipcMain.handle('update:get', () => state)
  ipcMain.handle('update:check', () => check())
  ipcMain.handle('update:install', () => install())

  if (!app.isPackaged) return
  const version = app.getVersion()
  // Never download by itself: only the Update button installs (see install).
  autoUpdater.autoDownload = false
  autoUpdater.autoInstallOnAppQuit = false
  const idle = (next: UpdateState) => busy() || publish(next)
  autoUpdater.on('checking-for-update', () => idle({ status: 'checking', version }))
  autoUpdater.on('update-not-available', () => idle({ status: 'none', version }))
  autoUpdater.on('update-available', (info) => {
    if (busy()) return
    files = info.files.map(({ url, sha512 }) => ({ url, sha512 }))
    publish({ status: 'available', version, next: info.version })
  })
  autoUpdater.on('error', () => idle({ status: 'error', version }))

  // Not at launch, with everything else starting: a minute in, then every six hours.
  setTimeout(check, 60_000)
  setInterval(check, EVERY)
}
