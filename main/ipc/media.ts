/** Media: sending the transport keys, and jumping to whatever is playing. */
import { ipcMain } from 'electron'
import { focusPlayer, sendTransport, type TransportKey } from '../mac/nowplaying'

const KEYS: TransportKey[] = ['play-pause', 'next', 'previous']

export function registerMediaIpc() {
  ipcMain.handle('media:key', (_event, key: TransportKey) => {
    if (KEYS.includes(key)) sendTransport(key)
  })

  ipcMain.handle('media:focus', (_event, sourceAppId: string) => {
    if (typeof sourceAppId !== 'string' || !/^[\w.!-]+$/.test(sourceAppId)) return
    return focusPlayer(sourceAppId)
  })
}
