import { chmodSync, existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { pickZip, swapApp, verifySha512 } from './updateInstall'

describe('pickZip', () => {
  it('picks the universal zip, not the dmg or another arch', () => {
    const files = [
      { url: 'CatNotch-1.0.8-universal.dmg', sha512: 'dmg' },
      { url: 'CatNotch-1.0.8-arm64-mac.zip', sha512: 'arm' },
      { url: 'CatNotch-1.0.8-universal-mac.zip', sha512: 'uni' },
    ]
    expect(pickZip({ files })).toEqual({ url: 'CatNotch-1.0.8-universal-mac.zip', sha512: 'uni' })
  })

  it('returns null when the release has no zip', () => {
    expect(pickZip({ files: [{ url: 'CatNotch.dmg', sha512: 'x' }] })).toBeNull()
  })
})

describe('verifySha512', () => {
  const HELLO = 'm3HSJL1i83hdltRq0+o9czGb+8KJDKra4t/3JRlnPKcjI8PZm6XBHXx6zG4UuMXaDEZjR1wuXDre9G9zvN7AQw=='
  const file = (text: string) => {
    const path = join(mkdtempSync(join(tmpdir(), 'catnotch-')), 'a.zip')
    writeFileSync(path, text)
    return path
  }

  it('accepts a file whose digest matches', async () => {
    expect(await verifySha512(file('hello'), HELLO)).toBe(true)
  })

  it('rejects a truncated or corrupted file', async () => {
    expect(await verifySha512(file('hell'), HELLO)).toBe(false)
  })
})

describe('swapApp', () => {
  const app = (dir: string, name: string, marker: string) => {
    const path = join(dir, name)
    mkdirSync(join(path, 'Contents'), { recursive: true })
    writeFileSync(join(path, 'Contents', 'marker'), marker)
    return path
  }
  const marker = (path: string) => readFileSync(join(path, 'Contents', 'marker'), 'utf8')

  it('replaces the installed app and clears the quarantine flag', () => {
    const dir = mkdtempSync(join(tmpdir(), 'catnotch-'))
    const installed = app(dir, 'CatNotch.app', 'old')
    const next = app(dir, 'CatNotch-new.app', 'new')
    execFileSync('xattr', ['-w', 'com.apple.quarantine', '0081;0;x;', next])

    expect(swapApp(next, installed)).toBe('ok')
    expect(marker(installed)).toBe('new')
    expect(execFileSync('xattr', [installed]).toString()).not.toContain('quarantine')
    expect(existsSync(next)).toBe(false)
  })

  it('keeps the old app when the new one is missing', () => {
    const dir = mkdtempSync(join(tmpdir(), 'catnotch-'))
    const installed = app(dir, 'CatNotch.app', 'old')

    expect(swapApp(join(dir, 'nope.app'), installed)).toBe('failed')
    expect(marker(installed)).toBe('old')
  })

  it('reports an unwritable folder without touching anything', () => {
    const dir = mkdtempSync(join(tmpdir(), 'catnotch-'))
    const locked = join(dir, 'locked')
    mkdirSync(locked)
    const installed = app(locked, 'CatNotch.app', 'old')
    const next = app(dir, 'CatNotch-new.app', 'new')
    chmodSync(locked, 0o555)

    try {
      expect(swapApp(next, installed)).toBe('unwritable')
      expect(marker(installed)).toBe('old')
    } finally {
      chmodSync(locked, 0o755)
    }
  })
})
