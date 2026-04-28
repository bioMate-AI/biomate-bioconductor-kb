/**
 * Locale completeness tests.
 * Every key present in en/common.json must exist in every other locale.
 * A missing key means the UI will silently fall back to English — acceptable,
 * but tracked here so we know the translation debt.
 */

import { readFileSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import { describe, it, expect } from 'vitest';

const __dirname = dirname(fileURLToPath(import.meta.url));
const localesDir = resolve(__dirname, '../locales');

const LOCALES = ['zh', 'ja', 'es'] as const;
const SOURCE_LOCALE = 'en';

function loadLocale(locale: string): Record<string, unknown> {
  const path = resolve(localesDir, locale, 'common.json');
  return JSON.parse(readFileSync(path, 'utf-8'));
}

/** Flatten a nested object into dot-separated key paths */
function flattenKeys(obj: Record<string, unknown>, prefix = ''): string[] {
  return Object.entries(obj).flatMap(([k, v]) => {
    const key = prefix ? `${prefix}.${k}` : k;
    if (v !== null && typeof v === 'object' && !Array.isArray(v)) {
      return flattenKeys(v as Record<string, unknown>, key);
    }
    return [key];
  });
}

/** Retrieve value at dot-path in nested object */
function getNestedValue(obj: Record<string, unknown>, path: string): unknown {
  return path.split('.').reduce<unknown>((acc, k) => {
    if (acc && typeof acc === 'object') return (acc as Record<string, unknown>)[k];
    return undefined;
  }, obj);
}

const sourceLocale = loadLocale(SOURCE_LOCALE);
const sourceKeys = flattenKeys(sourceLocale);

describe('Locale completeness', () => {
  for (const locale of LOCALES) {
    const targetLocale = loadLocale(locale);
    const targetKeys = new Set(flattenKeys(targetLocale));

    describe(`${locale}/common.json`, () => {
      it('has no extra keys not in source EN', () => {
        const extraKeys = [...targetKeys].filter(k => !sourceKeys.includes(k));
        expect(
          extraKeys,
          `${locale} has keys not in EN (orphaned translations): ${extraKeys.join(', ')}`
        ).toHaveLength(0);
      });

      it('contains all EN keys', () => {
        const missingKeys = sourceKeys.filter(k => !targetKeys.has(k));
        expect(
          missingKeys,
          `${locale} is missing ${missingKeys.length} keys: ${missingKeys.join(', ')}`
        ).toHaveLength(0);
      });

      it('has no empty string values', () => {
        const emptyKeys = sourceKeys.filter(k => {
          const val = getNestedValue(targetLocale, k);
          return val === '';
        });
        expect(
          emptyKeys,
          `${locale} has empty string values at: ${emptyKeys.join(', ')}`
        ).toHaveLength(0);
      });

      it('has no values identical to EN for non-shared terms', () => {
        // Languages that borrow English words (brand names, scientific terms) are fine,
        // but core UI words like "Loading..." should be translated.
        const MUST_TRANSLATE = [
          'actions.run', 'actions.cancel', 'actions.save',
          'common.loading', 'common.no_data',
          'chat.placeholder', 'chat.send',
          'errors.generic', 'errors.network',
          'nav.dashboard', 'nav.settings',
          'auth.sign_in', 'auth.sign_up',
        ];
        if (locale === 'en') return;
        const untranslated = MUST_TRANSLATE.filter(k => {
          const src = getNestedValue(sourceLocale, k);
          const tgt = getNestedValue(targetLocale, k);
          return src === tgt;
        });
        expect(
          untranslated,
          `${locale} has untranslated core UI keys: ${untranslated.join(', ')}`
        ).toHaveLength(0);
      });
    });
  }
});

describe('Source locale (en)', () => {
  it('has no empty string values', () => {
    const emptyKeys = sourceKeys.filter(k => getNestedValue(sourceLocale, k) === '');
    expect(emptyKeys, `EN has empty values at: ${emptyKeys.join(', ')}`).toHaveLength(0);
  });

  it('has expected top-level namespaces', () => {
    const topLevel = Object.keys(sourceLocale);
    expect(topLevel).toContain('nav');
    expect(topLevel).toContain('actions');
    expect(topLevel).toContain('workflow');
    expect(topLevel).toContain('chat');
    expect(topLevel).toContain('errors');
    expect(topLevel).toContain('common');
    expect(topLevel).toContain('settings');
    expect(topLevel).toContain('languages');
  });
});
