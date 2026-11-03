/** Pieces of the in-app Update that need no Electron; main/updater.ts does the rest. */
import { createHash } from 'node:crypto'
import { execFileSync } from 'node:child_process'
import { accessSync, constants, createReadStream, existsSync, renameSync, rmSync } from 'node:fs'
import { basename, dirname, join } from 'node:path'

export interface ReleaseFile {
  url: string
  sha512: string
}

/** Whether the file at `path` hashes to `expected` (base64 sha512, as in latest-mac.yml). */
export async function verifySha512(path: string, expected: string): Promise<boolean> {
  const hash = createHash('sha512')
  for await (const chunk of createReadStream(path)) hash.update(chunk)
  return hash.digest('base64') === expected
}

/** The universal zip of a release, from electron-updater's `update-available` info. */
export function pickZip(info: { files: ReleaseFile[] }): ReleaseFile | null {
  return info.files.find((file) => /-universal-mac\.zip$/.test(file.url)) ?? null
}

/** Whether the app can replace itself in `dir`: false on a read-only disk image. */
export function writable(dir: string): boolean {
  try {
    accessSync(dir, constants.W_OK)
    return true
  } catch {
    return false
  }
}

/**
 * Puts `next` in place of the installed app, which keeps running: macOS lets a
 * bundle be renamed under a live process. `next` must sit on the same volume
 * (the caller unpacks it beside the installed app). The old app is set aside
 * first and put back if anything fails, so the user is never left with none.
 */
export function swapApp(next: string, installed: string): 'ok' | 'unwritable' | 'failed' {
  const dir = dirname(installed)
  if (!writable(dir)) return 'unwritable'
  const old = join(dir, `.${basename(installed)}.old`)
  try {
    if (!existsSync(next)) return 'failed'
    // Unsigned build: macOS would block the first launch of a downloaded app.
    execFileSync('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', next])
    rmSync(old, { recursive: true, force: true })
    renameSync(installed, old)
    try {
      renameSync(next, installed)
    } catch (error) {
      renameSync(old, installed)
      throw error
    }
    rmSync(old, { recursive: true, force: true })
    return 'ok'
  } catch {
    return 'failed'
  }
}
