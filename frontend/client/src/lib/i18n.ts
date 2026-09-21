/**
 * Lightweight, dependency-free i18n for the BioMate frontend.
 *
 * Ports the detection logic from the standalone i18n side-project
 * (`i18n/src/detector.ts`) without pulling in i18next at runtime.
 *
 * Active locale is resolved ONCE at module load:
 *   1. Stored user preference (userSettingsService localStorage key
 *      `biomate-user-settings`, field `language` — values like
 *      "english"/"chinese"/"spanish"…).
 *   2. navigator.language (e.g. "zh-CN" → "zh").
 *   3. "en" (hard fallback).
 *
 * A manual language change (Settings → Language) persists the preference
 * and triggers a full page reload; the reload re-runs this module and the
 * new locale takes effect. (Acceptable for v1 — no live re-render.)
 */

import enCommon from '@/locales/en/common.json';
import zhCommon from '@/locales/zh/common.json';

export const SUPPORTED_LOCALES = ['en', 'zh', 'ja', 'es'] as const;
export type SupportedLocale = (typeof SUPPORTED_LOCALES)[number];

/** Only the locales we actually ship translation bundles for. */
const RESOURCES: Partial<Record<SupportedLocale, Record<string, unknown>>> = {
  en: enCommon as Record<string, unknown>,
  zh: zhCommon as Record<string, unknown>,
};

const LOCALE_STORAGE_KEY = 'biomate-user-settings';

/**
 * Map the userSettings `language` enum values
 * (english/spanish/french/german/chinese) to ISO 639-1 codes.
 * Anything unknown falls through to normaliseLocale (BCP-47 handling).
 */
const SETTINGS_LANG_MAP: Record<string, SupportedLocale> = {
  english: 'en',
  chinese: 'zh',
  spanish: 'es',
  japanese: 'ja',
  // french / german have no bundle yet → will fall back to 'en' below.
};

/** Normalise any BCP-47 tag (or bare code) to a supported locale, else 'en'. */
export function normaliseLocale(raw: string): SupportedLocale {
  if (!raw) return 'en';
  const lower = raw.toLowerCase();
  if ((SUPPORTED_LOCALES as readonly string[]).includes(lower)) {
    return lower as SupportedLocale;
  }
  const prefix = lower.split('-')[0];
  if ((SUPPORTED_LOCALES as readonly string[]).includes(prefix)) {
    return prefix as SupportedLocale;
  }
  return 'en';
}

/** Read the stored language preference (raw settings value) — browser only. */
export function readStoredLanguage(): string | null {
  try {
    const raw =
      typeof localStorage !== 'undefined'
        ? localStorage.getItem(LOCALE_STORAGE_KEY)
        : null;
    if (!raw) return null;
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return typeof parsed.language === 'string' ? parsed.language : null;
  } catch {
    return null;
  }
}

/**
 * Resolve the active locale from the browser environment.
 * Stored preference wins over navigator language; both fall back to 'en'.
 */
export function detectLocale(): SupportedLocale {
  const stored = readStoredLanguage();
  if (stored) {
    const mapped = SETTINGS_LANG_MAP[stored.toLowerCase()] ?? normaliseLocale(stored);
    // Only honour the stored preference if we have a bundle for it;
    // otherwise fall through to navigator/en so text stays coherent.
    if (RESOURCES[mapped]) return mapped;
    return 'en';
  }
  if (typeof navigator !== 'undefined' && navigator.language) {
    const nav = normaliseLocale(navigator.language);
    return RESOURCES[nav] ? nav : 'en';
  }
  return 'en';
}

/** The locale resolved for this page load. Stable for the session. */
export const locale: SupportedLocale = detectLocale();

const activeBundle = RESOURCES[locale] ?? enCommon;
const enBundle = enCommon as Record<string, unknown>;

/** Dot-path lookup into a nested resource object; returns undefined on miss. */
function lookup(bundle: Record<string, unknown>, key: string): string | undefined {
  let node: unknown = bundle;
  for (const part of key.split('.')) {
    if (node && typeof node === 'object' && part in (node as Record<string, unknown>)) {
      node = (node as Record<string, unknown>)[part];
    } else {
      return undefined;
    }
  }
  return typeof node === 'string' ? node : undefined;
}

/**
 * Translate a dot-path key (e.g. "nav.dashboard", "workflow.status.running").
 * Falls back to the English value, then to the key itself.
 */
export function t(key: string): string {
  return lookup(activeBundle, key) ?? lookup(enBundle, key) ?? key;
}

/**
 * Persist a language preference (writes the userSettings localStorage key)
 * and, when it differs from the current one, reload so the new locale applies.
 * `value` is the raw settings enum (e.g. "english", "chinese").
 */
export function setLanguagePreference(value: string): void {
  try {
    const raw =
      typeof localStorage !== 'undefined'
        ? localStorage.getItem(LOCALE_STORAGE_KEY)
        : null;
    const parsed = raw ? (JSON.parse(raw) as Record<string, unknown>) : {};
    const previous = typeof parsed.language === 'string' ? parsed.language : null;
    parsed.language = value;
    localStorage.setItem(LOCALE_STORAGE_KEY, JSON.stringify(parsed));
    if (previous !== value && typeof window !== 'undefined') {
      window.location.reload();
    }
  } catch {
    /* localStorage unavailable — ignore; nothing to persist. */
  }
}

/** Map a workflow run status to its translated label (falls back to raw). */
export function tStatus(status: string): string {
  const known = ['running', 'completed', 'failed', 'queued', 'cancelled', 'pending', 'unknown'];
  return known.includes(status) ? t(`workflow.status.${status}`) : t('workflow.status.unknown');
}
