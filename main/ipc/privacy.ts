/**
 * The status the closed notch shows at its edge: privacy dots (whether the
 * microphone or camera is in use), Wi-Fi, and Bluetooth. The native helper
 * reports each part when it changes, so an idle check costs nothing here.
 */
import { BrowserWindow, ipcMain } from 'electron'
import { requestLocation, watchHelper } from '../mac/helper'

export interface BluetoothDevice {
  name: string
  /** Percent, for devices that report it; null for the rest. */
  battery: number | null
}

export interface PrivacyState {
  mic: boolean
  camera: boolean
  /** The apps using each device, by the name they show under. */
  micApps: string[]
  cameraApps: string[]
  /** The Wi-Fi network, when connected. */
  wifi: { name: string; signal: number } | null
  /** Connected Bluetooth devices. */
  bluetooth: BluetoothDevice[]
}

let state: PrivacyState = { mic: false, camera: false, micApps: [], cameraApps: [], wifi: null, bluetooth: [] }

/** The helper reports each part of the state on its own; keep the latest of
 *  each and push the whole. The moment text carries no app name, since macOS
 *  says which device runs, not which app. */
let watching = false
const start = () => {
  if (watching) return
  watching = true
  const push = () => {
    for (const window of BrowserWindow.getAllWindows()) window.webContents.send('privacy:state', state)
  }
  watchHelper('watchStatus', ['mic', 'camera', 'wifi', 'bluetooth'], true, (line) => {
    if (line.t === 'mic') state = { ...state, mic: line.on, micApps: line.on ? ['Microphone'] : [] }
    else if (line.t === 'camera') state = { ...state, camera: line.on, cameraApps: line.on ? ['Camera'] : [] }
    else if (line.t === 'wifi') {
      // Without Location the name is hidden: still say there is a network.
      state = { ...state, wifi: line.connected ? { name: line.ssid ?? 'Wi-Fi', signal: line.signal } : null }
    } else state = { ...state, bluetooth: line.devices.map((d) => ({ name: d.name, battery: d.battery })) }
    push()
  })
  // The Wi-Fi moment is always on, so this is the moment to ask for Location.
  requestLocation()
}

export function registerPrivacyIpc() {
  // The first ask starts the watcher; the answer after that comes as events.
  ipcMain.handle('privacy:get', () => {
    start()
    return state
  })
}

export function stopPrivacyIpc() {
  watching = false
}
