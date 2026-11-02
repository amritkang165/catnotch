import { useEffect, useRef, useState } from 'react'
import { DEFAULT_SETTINGS, type Settings } from '../components/widgets/SettingsPanel'
import type { CompanionMode } from '../components/widgets/CompanionTile'
import { onStoreChange } from '../lib/store'

/** The saved settings, loaded once, kept in step with other windows, and saved
 *  on every change. Shared by the notch and the settings window. */
export function useSettingsStore() {
  const [settings, setSettings] = useState<Settings>(DEFAULT_SETTINGS)
  const settingsLoaded = useRef(false)

  useEffect(() => {
    window.bridge
      ?.invoke<Partial<Settings>>('store:get', 'settings')
      .then(async (stored) => {
        const loadedSettings: Settings = {
          ...DEFAULT_SETTINGS,
          ...stored,
          // Translucent became Glass, now a real blur; Mica is gone, so it is Default.
          notchStyle:
            (stored?.notchStyle as string) === 'translucent'
              ? 'glass'
              : (stored?.notchStyle as string) === 'mica'
                ? 'black'
                : (stored?.notchStyle ?? DEFAULT_SETTINGS.notchStyle),
          // Screen time is gone: the clock stands in.
          collapsedRight: (stored?.collapsedRight as string) === 'screen' ? 'time' : (stored?.collapsedRight ?? DEFAULT_SETTINGS.collapsedRight),
          // Focus lives in the companion now; the glance card is retired.
          showFocus: false,
          // Older settings kept a list of topics under another name; the first
          // one becomes the mode.
          // Retired modes ('ai', and 'screen' from the removed Screen time) are the timer; Tasks became Reminder.
          companionMode:
            (['ai', 'screen'].includes(stored?.companionMode as string)
              ? 'focus'
              : (stored?.companionMode as string) === 'tasks'
                ? 'reminder'
                : stored?.companionMode) ??
            (Array.isArray((stored as any)?.companionSays) ? ((stored as any).companionSays[0] as CompanionMode | undefined) : undefined) ??
            DEFAULT_SETTINGS.companionMode,
        }

        try {
          const actualStartOnBoot = await window.bridge?.invoke<boolean>(
            'settings:start-on-boot',
            stored?.startOnBoot ?? DEFAULT_SETTINGS.startOnBoot,
          )
          if (typeof actualStartOnBoot === 'boolean') {
            loadedSettings.startOnBoot = actualStartOnBoot
          }
        } catch {}

        setSettings(loadedSettings)
      })
      .catch(() => setSettings(DEFAULT_SETTINGS))
      .finally(() => {
        settingsLoaded.current = true
      })
  }, [])

  useEffect(() => onStoreChange<Settings>('settings', setSettings), [])

  useEffect(() => {
    if (!settingsLoaded.current) return
    void window.bridge?.invoke('store:set', 'settings', settings)
    void window.bridge?.invoke('settings:start-on-boot', settings.startOnBoot)
  }, [settings])

  return [settings, setSettings] as const
}
