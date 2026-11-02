/**
 * Now playing on macOS, from the vendored mediaremote-adapter (native/mac/
 * mediaremote-adapter). It runs under Apple's own /usr/bin/perl, the only
 * thing still allowed to read MediaRemote.
 */
import { app, BrowserWindow, ipcMain, nativeImage } from 'electron'
import { execFile, spawn, type ChildProcess } from 'child_process'
import { existsSync } from 'fs'
import path from 'path'

export interface NowPlaying {
  sourceAppId: string
  title: string
  artist: string
  album: string
  isPlaying: boolean
  position: number
  duration: number
  /** Album art as a data URL, or null when the player publishes none. */
  thumbnailUrl: string | null
}

let current: NowPlaying | null = null

/** Album art is never shown larger than this, so bigger art is shrunk to it,
 *  once per track: players can hand over a 4K cover, which took ~140ms to
 *  decode every time a card holding it appeared, stalling the notch's spring. */
const ART = 256
let art: { from: string; to: string } | null = null
const smallArt = (url: string | null) => {
  if (!url) return null
  if (art?.from === url) return art.to
  const image = nativeImage.createFromDataURL(url)
  const { width, height } = image.getSize()
  const to =
    Math.min(width, height) <= ART
      ? url
      : `data:image/jpeg;base64,${(width > height ? image.resize({ height: ART }) : image.resize({ width: ART })).toJPEG(88).toString('base64')}`
  art = { from: url, to }
  return to
}

/** Sets what is playing and tells every window. */
const setNowPlaying = (next: NowPlaying | null) => {
  current = next && { ...next, thumbnailUrl: smallArt(next.thumbnailUrl) }
  for (const window of BrowserWindow.getAllWindows()) window.webContents.send('nowplaying:changed', current)
}

const COMMANDS = { play: 0, pause: 1, 'play-pause': 2, next: 4, previous: 5 } as const
export type TransportKey = keyof typeof COMMANDS

const dir = () => (app.isPackaged ? process.resourcesPath : path.join(process.cwd(), 'native', 'mac', 'build'))
const script = () => path.join(dir(), 'mediaremote', 'mediaremote-adapter.pl')
const framework = () => path.join(dir(), 'mediaremote', 'MediaRemoteAdapter.framework')
const adapterArgs = (...rest: string[]) => [script(), framework(), ...rest]

let child: ChildProcess | null = null
let stopped = false
let crashes = 0
let state: Record<string, any> = {}

const toNowPlaying = (s: Record<string, any>): NowPlaying | null => {
  if (!s.title || !s.bundleIdentifier) return null
  const playing = s.playing === true
  const seen = Number(s.elapsedTimeMicros ?? 0) / 1e6
  const at = Number(s.timestampEpochMicros ?? 0) / 1e3
  return {
    sourceAppId: s.bundleIdentifier,
    title: s.title,
    artist: s.artist ?? '',
    album: s.album ?? '',
    isPlaying: playing,
    // The adapter reports where the track was at `timestamp`; the renderer
    // wants where it is now.
    position: playing && at ? seen + (Date.now() - at) / 1000 : seen,
    duration: Number(s.durationMicros ?? 0) / 1e6,
    thumbnailUrl: s.artworkData ? `data:${s.artworkMimeType || 'image/jpeg'};base64,${s.artworkData}` : null,
  }
}

const handle = (line: string) => {
  const message = JSON.parse(line)
  if (message.type !== 'data') return
  const payload = message.payload ?? {}
  // A diff only carries what changed; a key set to null has gone away.
  state = message.diff ? { ...state, ...payload } : { ...payload }
  for (const key of Object.keys(state)) if (state[key] === null) delete state[key]
  setNowPlaying(toNowPlaying(state))
}

const start = () => {
  if (stopped || !existsSync(script())) return
  const proc = spawn('/usr/bin/perl', adapterArgs('stream', '--micros', '--debounce=100'), { stdio: ['ignore', 'pipe', 'ignore'] })
  child = proc
  proc.on('error', () => {})
  let buffer = ''
  proc.stdout?.on('data', (chunk: Buffer) => {
    buffer += chunk.toString()
    const lines = buffer.split('\n')
    buffer = lines.pop() ?? ''
    for (const line of lines) {
      try {
        handle(line)
      } catch {}
    }
  })
  proc.on('exit', () => {
    child = null
    state = {}
    setNowPlaying(null)
    if (!stopped && ++crashes <= 3) setTimeout(start, 1000)
  })
}

export function startMacNowPlaying() {
  // The renderer asks once on mount; after that it listens.
  ipcMain.handle('nowplaying:get', () => current)
  start()
}

export function stopMacNowPlaying() {
  stopped = true
  child?.kill()
}

/** Play, pause, next or previous on whatever is playing. */
export const sendTransport = (key: TransportKey) =>
  execFile('/usr/bin/perl', adapterArgs('send', String(COMMANDS[key])), () => {})

/** Brings the player forward. The id is checked first: it is a bundle id from
 *  the adapter, but the page passes it back to us. */
export const focusPlayer = (bundleId: string) => {
  if (!/^[\w.-]+$/.test(bundleId)) return
  execFile('open', ['-b', bundleId], () => {})
}
