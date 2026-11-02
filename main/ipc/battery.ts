/**
 * Battery: Chromium restricts navigator.getBattery() in non-HTTPS Electron
 * apps, so the charge is read from `pmset` and re-read when the power source
 * changes.
 */
import { BrowserWindow, ipcMain, powerMonitor } from 'electron'
import { execFile } from 'child_process'

export interface BatteryState {
  level: number
  charging: boolean
  supported: boolean
}

const NONE: BatteryState = { level: 1, charging: true, supported: false }

/** "-InternalBattery-0 (id=1)\t80%; charging; 1:02 remaining" → the state. No such line: a desktop Mac. */
export const parsePmset = (out: string): BatteryState => {
  const match = /(\d+)%;\s*([^;]+)/.exec(out)
  if (!match) return NONE
  return { level: Math.min(1, Number(match[1]) / 100), charging: !/^discharging/.test(match[2].trim()), supported: true }
}

const queryBattery = (): Promise<BatteryState> =>
  new Promise((resolve) => execFile('pmset', ['-g', 'batt'], (_error, stdout) => resolve(parsePmset(stdout ?? ''))))

const broadcastState = async () => {
  const state = await queryBattery()
  for (const window of BrowserWindow.getAllWindows()) window.webContents.send('battery:state', state)
}

export function registerBatteryIpc() {
  ipcMain.handle('battery:get', () => queryBattery())
  powerMonitor.on('on-battery', () => void broadcastState())
  powerMonitor.on('on-ac', () => void broadcastState())
}
