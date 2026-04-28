/**
 * Language detector tests.
 * Covers: normalisation, fallback, localStorage preference override.
 */

import { describe, it, expect } from 'vitest';
import { detectLanguage, normaliseLocale, SUPPORTED_LOCALES } from '../src/detector.js';

describe('normaliseLocale', () => {
  it('passes through exact supported codes', () => {
    expect(normaliseLocale('en')).toBe('en');
    expect(normaliseLocale('zh')).toBe('zh');
    expect(normaliseLocale('ja')).toBe('ja');
    expect(normaliseLocale('es')).toBe('es');
  });

  it('normalises zh variants to zh', () => {
    expect(normaliseLocale('zh-CN')).toBe('zh');
    expect(normaliseLocale('zh-TW')).toBe('zh');
    expect(normaliseLocale('zh-HK')).toBe('zh');
    expect(normaliseLocale('zh-SG')).toBe('zh');
  });

  it('normalises ja variant to ja', () => {
    expect(normaliseLocale('ja-JP')).toBe('ja');
  });

  it('normalises es variants to es', () => {
    expect(normaliseLocale('es-MX')).toBe('es');
    expect(normaliseLocale('es-AR')).toBe('es');
    expect(normaliseLocale('es-419')).toBe('es');
  });

  it('normalises en variants to en', () => {
    expect(normaliseLocale('en-US')).toBe('en');
    expect(normaliseLocale('en-GB')).toBe('en');
    expect(normaliseLocale('en-AU')).toBe('en');
  });

  it('returns en for unsupported locales', () => {
    expect(normaliseLocale('fr')).toBe('en');
    expect(normaliseLocale('de')).toBe('en');
    expect(normaliseLocale('ko')).toBe('en');
    expect(normaliseLocale('')).toBe('en');
    expect(normaliseLocale('xyz-UNKNOWN')).toBe('en');
  });

  it('is case-insensitive', () => {
    expect(normaliseLocale('ZH-CN')).toBe('zh');
    expect(normaliseLocale('JA')).toBe('ja');
    expect(normaliseLocale('EN-US')).toBe('en');
  });
});

describe('SUPPORTED_LOCALES', () => {
  it('contains the four initial languages', () => {
    expect(SUPPORTED_LOCALES).toContain('en');
    expect(SUPPORTED_LOCALES).toContain('zh');
    expect(SUPPORTED_LOCALES).toContain('ja');
    expect(SUPPORTED_LOCALES).toContain('es');
  });
});

describe('detectLanguage', () => {
  it('returns en when no preference or navigator supplied', () => {
    expect(detectLanguage({ storedPreference: null, navigatorLanguage: null })).toBe('en');
  });

  it('respects stored preference over navigator language', () => {
    expect(detectLanguage({ storedPreference: 'zh', navigatorLanguage: 'en-US' })).toBe('zh');
    expect(detectLanguage({ storedPreference: 'ja', navigatorLanguage: 'es' })).toBe('ja');
  });

  it('falls back to navigator language when no stored preference', () => {
    expect(detectLanguage({ storedPreference: null, navigatorLanguage: 'zh-CN' })).toBe('zh');
    expect(detectLanguage({ storedPreference: null, navigatorLanguage: 'ja-JP' })).toBe('ja');
    expect(detectLanguage({ storedPreference: null, navigatorLanguage: 'es-MX' })).toBe('es');
  });

  it('falls back to en when navigator language is unsupported', () => {
    expect(detectLanguage({ storedPreference: null, navigatorLanguage: 'fr-FR' })).toBe('en');
    expect(detectLanguage({ storedPreference: null, navigatorLanguage: 'de' })).toBe('en');
  });

  it('ignores invalid stored preference values', () => {
    // If user somehow has a garbage value in localStorage, fall back gracefully
    expect(detectLanguage({ storedPreference: 'invalid-lang', navigatorLanguage: 'ja' })).toBe('ja');
    expect(detectLanguage({ storedPreference: 'invalid-lang', navigatorLanguage: 'fr' })).toBe('en');
  });
});
