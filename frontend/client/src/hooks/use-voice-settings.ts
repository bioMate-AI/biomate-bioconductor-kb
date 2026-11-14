import { useCallback, useEffect, useState } from 'react';
import { userSettingsService } from '@/lib/user-settings';

const STORAGE_KEY = 'biomate-user-settings';
const CHANGE_EVENT = 'biomate-voice-settings-changed';

export type VoiceSettings = {
  voiceEnabled: boolean;
  voiceHandsFree: boolean;
};

function readVoiceSettings(): VoiceSettings {
  const s = userSettingsService.getChatSettings();
  return {
    voiceEnabled: s.voiceEnabled === true,
    voiceHandsFree: s.voiceHandsFree === true,
  };
}

/** Notify open chat composers when Settings flips voice toggles in the same tab. */
export function notifyVoiceSettingsChanged() {
  window.dispatchEvent(new Event(CHANGE_EVENT));
}

/** Voice chrome is opt-in via Settings → Voice. Default off so the composer stays clean. */
export function useVoiceSettings(): VoiceSettings {
  const [settings, setSettings] = useState<VoiceSettings>(readVoiceSettings);
  const refresh = useCallback(() => setSettings(readVoiceSettings()), []);
  useEffect(() => {
    const onStorage = (e: StorageEvent) => {
      if (e.key === STORAGE_KEY || e.key === null) refresh();
    };
    window.addEventListener('storage', onStorage);
    window.addEventListener(CHANGE_EVENT, refresh);
    return () => {
      window.removeEventListener('storage', onStorage);
      window.removeEventListener(CHANGE_EVENT, refresh);
    };
  }, [refresh]);
  return settings;
}
