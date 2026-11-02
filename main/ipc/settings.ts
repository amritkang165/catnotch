/** Settings that have to be applied to the OS, not just remembered. */
import { app, ipcMain, shell } from 'electron'

export function registerSettingsIpc() {
  // A dev run is bare Electron plus a dev server: registered at login, it would
  // show Electron's default app instead of the notch. So only the installed app
  // registers, and a dev run clears any entry an earlier dev run left behind.
  if (!app.isPackaged) app.setLoginItemSettings({ openAtLogin: false })

  // A fixed address, not one from the page: the renderer can only open this.
  ipcMain.handle('app:open-repo', () => shell.openExternal('https://github.com/thecharydev/catnotch'))

  ipcMain.handle('settings:start-on-boot', (_event, enabled?: unknown) => {
    if (!app.isPackaged) return false
    if (typeof enabled === 'boolean') {
      app.setLoginItemSettings({ openAtLogin: enabled, path: process.execPath })
    }
    return app.getLoginItemSettings({ path: process.execPath }).openAtLogin
  })

  /** Close CatNotch until the user opens it again. */
  ipcMain.on('app:quit', () => app.quit())
}
