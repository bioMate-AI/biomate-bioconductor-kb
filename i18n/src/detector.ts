/**
 * Language detector for BioMate.
 *
 * Detection order:
 *   1. Stored preference in userSettingsService localStorage key
 *   2. navigator.language (browser default)
 *   3. 'en' (hard fallback)
 *
 * All locale codes are normalised to a 2-letter ISO 639-1 code
 * from the SUPPORTED_LOCALES set.
 */

export const SUPPORTED_LOCALES = ['en', 'zh', 'ja', 'es'] as const;
export type SupportedLocale = typeof SUPPORTED_LOCALES[number];

/** Map of language tag prefixes → supported locale */
const LOCALE_MAP: Record<string, SupportedLocale> = {
  en: 'en',
  zh: 'zh',
  ja: 'ja',
  es: 'es',
};

/**
 * Normalise any BCP 47 language tag to a supported locale code.
 * Returns 'en' for anything not in SUPPORTED_LOCALES.
 */
export function normaliseLocale(raw: string): SupportedLocale {
  if (!raw) return 'en';
  const lower = raw.toLowerCase();
  // Try exact match first
  if (SUPPORTED_LOCALES.includes(lower as SupportedLocale)) {
    return lower as SupportedLocale;
  }
  // Try prefix (e.g. 'zh-CN' → 'zh', 'en-US' → 'en')
  const prefix = lower.split('-')[0];
  if (prefix && prefix in LOCALE_MAP) {
    return LOCALE_MAP[prefix];
  }
  return 'en';
}

export interface DetectOptions {
  /** Value from localStorage userSettings.language — null if not set */
  storedPreference: string | null;
  /** navigator.language value — null in SSR/test environments */
  navigatorLanguage: string | null;
}

/**
 * Determine the active locale.
 * Stored preference wins over navigator language; both fall back to 'en'.
 */
export function detectLanguage({ storedPreference, navigatorLanguage }: DetectOptions): SupportedLocale {
  if (storedPreference) {
    const normalised = normaliseLocale(storedPreference);
    if (normalised !== 'en' || storedPreference.toLowerCase().startsWith('en')) {
      // Only trust the stored preference if it normalises to something meaningful
      if (SUPPORTED_LOCALES.includes(normalised)) {
        return normalised;
      }
    }
  }
  if (navigatorLanguage) {
    const normalised = normaliseLocale(navigatorLanguage);
    return normalised;
  }
  return 'en';
}

/**
 * Read the stored language preference from BioMate's userSettingsService localStorage key.
 * Safe to call in browser environments only.
 */
export function readStoredPreference(): string | null {
  try {
    const raw = typeof localStorage !== 'undefined'
      ? localStorage.getItem('biomate-user-settings')
      : null;
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return typeof parsed.language === 'string' ? parsed.language : null;
  } catch {
    return null;
  }
}

/**
 * Detect the active locale from the browser environment.
 * Use this in the frontend i18n bootstrap.
 */
export function detectBrowserLocale(): SupportedLocale {
  return detectLanguage({
    storedPreference: readStoredPreference(),
    navigatorLanguage: typeof navigator !== 'undefined' ? navigator.language : null,
  });
}
