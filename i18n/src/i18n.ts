/**
 * i18next instance factory for BioMate.
 *
 * Returns a fully initialised i18next instance for a given locale.
 * Each locale gets its own instance so tests can run in parallel without
 * shared state.
 *
 * In the browser, a singleton is used (see bottom of file).
 */

import i18next, { type i18n } from 'i18next';
import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import type { SupportedLocale } from './detector.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const LOCALES_DIR = resolve(__dirname, '../locales');
const SUPPORTED = ['en', 'zh', 'ja', 'es'] as const;

function loadResources(): Record<string, { common: Record<string, unknown> }> {
  const resources: Record<string, { common: Record<string, unknown> }> = {};
  for (const locale of SUPPORTED) {
    const path = resolve(LOCALES_DIR, locale, 'common.json');
    resources[locale] = { common: JSON.parse(readFileSync(path, 'utf-8')) };
  }
  return resources;
}

/**
 * Create and initialise a fresh i18next instance for `locale`.
 * Used in tests (each test gets an isolated instance).
 */
export async function createI18nInstance(locale: string): Promise<i18n> {
  const instance = i18next.createInstance();
  const resources = loadResources();

  await instance.init({
    lng: locale,
    fallbackLng: 'en',
    defaultNS: 'common',
    ns: ['common'],
    resources,
    interpolation: {
      escapeValue: false, // React already escapes
    },
    // In production, return key path on missing; in dev also log a warning
    saveMissing: false,
    missingKeyHandler: (_lngs, _ns, key) => {
      if (process.env.NODE_ENV !== 'production') {
        console.warn(`[i18n] Missing key: "${key}"`);
      }
    },
  });

  return instance;
}

/**
 * Browser singleton — call once in main.tsx before mounting the app.
 *
 * Usage:
 *   import { initI18n } from '@/lib/i18n';
 *   import { detectBrowserLocale } from '@/lib/i18n-detector';
 *   await initI18n(detectBrowserLocale());
 */
let _singleton: i18n | null = null;

export async function initI18n(locale: SupportedLocale = 'en'): Promise<i18n> {
  if (_singleton?.isInitialized) {
    await _singleton.changeLanguage(locale);
    return _singleton;
  }
  _singleton = await createI18nInstance(locale);
  return _singleton;
}

export function getI18n(): i18n {
  if (!_singleton?.isInitialized) {
    throw new Error('i18n not initialised — call initI18n() before getI18n()');
  }
  return _singleton;
}

export default { createI18nInstance, initI18n, getI18n };
