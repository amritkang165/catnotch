import { BrowserWindow, screen } from 'electron'
import { readStore } from './store'
import { notchWindows } from './display'
import { watchHelper } from './mac/helper'

let lastRawResult = ''
/** A Claude Code request is waiting: the notch shows even over a fullscreen app. */
let claudeWaiting = false
/** Per notch window id: whether it is tucked up out of a browser's way. */
const tucked = new Map<number, boolean>()

/** Browsers, by bundle id: their tabs and address bar sit right under the notch. */
const BROWSERS = new Set([
  'com.apple.Safari', 'com.google.Chrome', 'com.microsoft.edgemac', 'org.mozilla.firefox', 'com.brave.Browser',
  'company.thebrowser.Browser', 'com.operasoftware.Opera', 'com.vivaldi.Vivaldi',
])

/** The helper reports the frontmost app; turn it into one line,
 *  "fullscreen,left,top,right,bottom,bundle", with the display's own bounds. */
const watchMac = (on: boolean) =>
  watchHelper(
    'watchForeground',
    ['foreground'],
    on,
    (line) => {
      if ('self' in line) return handleFullscreenChange('self')
      const display = screen.getAllDisplays().find((d) => d.id === line.display) ?? screen.getPrimaryDisplay()
      const { x, y, width, height } = display.bounds
      handleFullscreenChange(`${line.fullscreen ? 1 : 0},${x},${y},${x + width},${y + height},${line.bundle}`)
    },
  )

export const startFullscreenWatch = () => watchMac(true)

export const stopFullscreenWatch = () => watchMac(false)

/** Starts the watcher when a setting needs it and stops it when none does:
 *  the helper's foreground events are not worth keeping for nothing. */
export function checkAndApplyFullscreenState() {
  const settings = (readStore().settings ?? {}) as Record<string, unknown>
  // Claude's popups need to know what is in front, so its switch keeps the watcher going.
  const claudeOn = readStore().claudeHooks?.enabled === true
  if (settings.hideOnFullscreen === false && settings.tuckForBrowsers !== true && !claudeOn) {
    stopFullscreenWatch()
    lastRawResult = ''
    // Nothing in front on any monitor: every notch shown and untucked.
    handleFullscreenChange('0,0,0,0,0,')
    return
  }
  startFullscreenWatch()
  handleFullscreenChange(lastRawResult)
}

/** Shows the notch over a fullscreen app while a Claude request waits, and hides it again after. */
export function setClaudeWaiting(waiting: boolean) {
  if (claudeWaiting === waiting) return
  claudeWaiting = waiting
  if (lastRawResult) handleFullscreenChange(lastRawResult)
}

/** The terminals a CLI session runs in, by bundle id (lower case). */
const TERMINALS = new Set([
  'com.apple.terminal', 'com.googlecode.iterm2', 'dev.warp.warp-stable', 'com.mitchellh.ghostty', 'net.kovidgoyal.kitty', 'org.alacritty', 'com.github.wez.wezterm',
])

/** Whether a terminal is in front, where a CLI session is already asking. VS Code never counts:
 *  the extension's prompt sits in a side panel and is easy to miss, so its questions show on the notch. */
export const isTerminalInFront = (raw: string, source: 'cli' | 'vscode' | 'unknown') =>
  source !== 'vscode' && TERMINALS.has((raw.split(',')[5] ?? '').toLowerCase())

export const claudeIsInFront = (source: 'cli' | 'vscode' | 'unknown') => isTerminalInFront(lastRawResult, source)

/** Whether this notch is tucked right now, for a renderer that just loaded. */
export const isTucked = (windowId: number) => tucked.get(windowId) ?? false

function handleFullscreenChange(rawResult: string) {
  // deskNotch itself in front (being hovered or clicked): leave everything as it was.
  if (rawResult === 'self') return
  const [flag, l, t, r, b, exe = ''] = rawResult.split(',')
  const monitor = [l, t, r, b].map(Number)
  // A half-written line leaves the notches as they are.
  if ((flag !== '0' && flag !== '1') || monitor.some(isNaN)) return
  lastRawResult = rawResult

  const settings = (readStore().settings ?? {}) as Record<string, unknown>
  const hideOnFullscreen = settings.hideOnFullscreen !== false
  const tuckForBrowsers = settings.tuckForBrowsers === true
  const browser = BROWSERS.has(exe)

  const displays = screen.getAllDisplays()
  for (const [id, window] of notchWindows()) {
    const display = displays.find((d) => String(d.id) === id)
    // Only the notch on the foreground window's monitor reacts to it.
    let onDisplay = false
    if (display) {
      const { x, y, width, height } = display.bounds
      onDisplay = monitor[0] < x + width && monitor[2] > x && monitor[1] < y + height && monitor[3] > y
    }
    const hide = hideOnFullscreen && flag === '1' && onDisplay && !claudeWaiting
    if (hide && window.isVisible()) window.hide()
    else if (!hide && !window.isVisible()) restoreWindow(window)

    const tuck = tuckForBrowsers && browser && onDisplay && !hide
    if (isTucked(window.id) !== tuck) {
      tucked.set(window.id, tuck)
      window.webContents.send('notch:tucked', tuck)
    }
  }
}
function restoreWindow(window: BrowserWindow) {
  window.showInactive()
  window.setAlwaysOnTop(true, 'screen-saver')
  window.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: true })
}