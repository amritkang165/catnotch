/** The settings window: one at a time, opened by a global shortcut or from the notch. */
import path from 'path'
import { app, BrowserWindow, globalShortcut, ipcMain } from 'electron'

const isProd = process.env.NODE_ENV === 'production'
const SHORTCUT = 'CommandOrControl+Alt+,'

let win: BrowserWindow | null = null

/** The notches hold themselves open while Settings has focus, so changes show. */
const announce = (open: boolean) => {
  for (const window of BrowserWindow.getAllWindows()) if (window !== win) window.webContents.send('settings-window:state', open)
}

export function openSettingsWindow() {
  if (win && !win.isDestroyed()) {
    if (win.isMinimized()) win.restore()
    win.show()
    win.focus()
    app.focus({ steal: true })
    return
  }

  win = new BrowserWindow({
    width: 720,
    height: 520,
    resizable: false,
    fullscreenable: false,
    minimizable: true,
    // Not exactly "CatNotch": fullscreen.ts finds the notch by that title.
    title: 'CatNotch Settings',
    show: false,
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 16, y: 16 },
    vibrancy: 'sidebar',
    visualEffectState: 'active',
    transparent: true,
    webPreferences: { preload: path.join(import.meta.dirname, 'preload.js') },
  })
  const self = win

  // An accessory app has no Dock icon; show one while this window lives.
  void app.dock?.show()
  self.once('ready-to-show', () => {
    self.show()
    app.focus({ steal: true })
  })
  self.on('focus', () => announce(true))
  self.on('blur', () => announce(false))
  self.on('closed', () => {
    win = null
    announce(false)
    app.dock?.hide()
  })

  if (isProd) void self.loadURL('app://./settings')
  else void self.loadURL(`http://localhost:${process.argv[2]}/settings`)
}

export function registerSettingsWindow() {
  ipcMain.on('settings-window:open', openSettingsWindow)
  // Another app may own the shortcut; the notch's Claude link still opens the window.
  try {
    if (!globalShortcut.register(SHORTCUT, openSettingsWindow)) console.warn(`Settings shortcut ${SHORTCUT} is taken`)
  } catch (error) {
    console.warn(`Settings shortcut ${SHORTCUT} failed`, error)
  }
  app.on('will-quit', () => globalShortcut.unregisterAll())
}
