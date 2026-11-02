// @vitest-environment node
import { describe, expect, it, vi } from 'vitest'

vi.mock('electron', () => ({ BrowserWindow: class {}, ipcMain: {}, powerMonitor: {} }))

import { parsePmset } from './battery'

describe('parsePmset', () => {
  it('reads a discharging laptop', () => {
    expect(parsePmset(" -InternalBattery-0 (id=1)\t42%; discharging; 3:20 remaining present: true")).toEqual({ level: 0.42, charging: false, supported: true })
  })
  it.each(['charging', 'AC attached', 'finishing charge'])('counts "%s" as charging', (status) => {
    expect(parsePmset(` -InternalBattery-0 (id=1)\t80%; ${status}; 0:30 remaining`).charging).toBe(true)
  })
  it('is unsupported with no battery line', () => {
    expect(parsePmset("Now drawing from 'AC Power'\n").supported).toBe(false)
    expect(parsePmset('').supported).toBe(false)
  })
})
