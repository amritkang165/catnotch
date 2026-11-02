/**
 * The machine's load, for the Right now card's Usage page: CPU, GPU and
 * memory. Nothing here runs unless that page is showing.
 *
 * - CPU: Node's own `os`, the share of busy time since the previous request,
 *   so the first reading is a guess.
 * - GPU and memory: asked of the native helper.
 */
import { ipcMain } from 'electron'
import os from 'os'
import { askHelper } from '../mac/helper'

export interface Usage {
  /** Shares, 0–1. */
  cpu: number
  memory: number
  /** Percent, or null when the helper has no reading. */
  gpu: number | null
}

/** Busy share of every core since the last call. */
let lastTimes = os.cpus().map((core) => core.times)
const cpu = () => {
  const now = os.cpus().map((core) => core.times)
  let busy = 0
  let total = 0
  now.forEach((times, i) => {
    const before = lastTimes[i]
    if (!before) return
    for (const key of Object.keys(times) as (keyof typeof times)[]) total += times[key] - before[key]
    busy += times.idle - before.idle
  })
  lastTimes = now
  return total > 0 ? 1 - busy / total : 0
}

export function registerUsageIpc() {
  ipcMain.handle('usage:get', async (): Promise<Usage> => {
    const reply = await askHelper<{ gpu: number | null; memory: number }>('usage')
    return { cpu: cpu(), memory: reply?.memory ?? 1 - os.freemem() / os.totalmem(), gpu: reply?.gpu ?? null }
  })
}
