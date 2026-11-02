/** Every IPC handler the app registers, in one call. */
import { registerStoreIpc } from './store'
import { registerPhotoIpc } from './photo'
import { registerSystemIpc } from './system'
import { registerSettingsIpc } from './settings'
import { registerLimitsIpc } from './limits'
import { registerMediaIpc } from './media'
import { registerFilesIpc } from './files'
import { registerPrivacyIpc } from './privacy'
import { registerMacAppsIpc } from '../mac/apps'
import { registerUsageIpc } from './usage'
import { registerBatteryIpc } from './battery'
import { registerDisplayIpc } from './display'
import { registerClaudeIpc } from './claude'
import { registerCalendarIpc } from './calendar'

export function registerIpc() {
  registerStoreIpc()
  registerPhotoIpc()
  registerSystemIpc()
  registerSettingsIpc()
  registerLimitsIpc()
  registerMediaIpc()
  registerFilesIpc()
  registerPrivacyIpc()
  registerMacAppsIpc()
  registerUsageIpc()
  registerBatteryIpc()
  registerDisplayIpc()
  registerClaudeIpc()
  registerCalendarIpc()
}

