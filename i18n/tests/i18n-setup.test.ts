/**
 * i18next instance tests.
 * Verifies: init, key resolution, interpolation, fallback to EN on missing key.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import i18next from 'i18next';
import { createI18nInstance } from '../src/i18n.js';

let i18n: typeof i18next;

beforeAll(async () => {
  i18n = await createI18nInstance('en');
});

describe('i18next — English', () => {
  it('initialises without error', () => {
    expect(i18n.isInitialized).toBe(true);
  });

  it('resolves nav keys', () => {
    expect(i18n.t('nav.dashboard')).toBe('Dashboard');
    expect(i18n.t('nav.settings')).toBe('Settings');
    expect(i18n.t('nav.logout')).toBe('Log out');
  });

  it('resolves action keys', () => {
    expect(i18n.t('actions.run')).toBe('Run');
    expect(i18n.t('actions.cancel')).toBe('Cancel');
    expect(i18n.t('actions.download')).toBe('Download');
  });

  it('resolves workflow status keys', () => {
    expect(i18n.t('workflow.status.running')).toBe('Running');
    expect(i18n.t('workflow.status.completed')).toBe('Completed');
    expect(i18n.t('workflow.status.failed')).toBe('Failed');
  });

  it('resolves error keys', () => {
    expect(i18n.t('errors.generic')).toBe('Something went wrong. Please try again.');
    expect(i18n.t('errors.network')).toBe('Network error. Check your connection.');
  });

  it('handles interpolation in workflow messages', async () => {
    expect(i18n.t('workflow.messages.running_phase', { phase: '3' })).toBe('Running phase 3');
  });

  it('falls back to key path for completely missing keys', () => {
    // i18next returns the key itself when nothing found — never crashes
    const result = i18n.t('nonexistent.deeply.nested.key');
    expect(result).toBe('nonexistent.deeply.nested.key');
  });
});

describe('i18next — Chinese (zh)', () => {
  let i18nZh: typeof i18next;

  beforeAll(async () => {
    i18nZh = await createI18nInstance('zh');
  });

  it('resolves nav.dashboard to Chinese', () => {
    expect(i18nZh.t('nav.dashboard')).toBe('仪表盘');
  });

  it('resolves actions.run to Chinese', () => {
    expect(i18nZh.t('actions.run')).toBe('运行');
  });

  it('resolves workflow.status.running to Chinese', () => {
    expect(i18nZh.t('workflow.status.running')).toBe('运行中');
  });

  it('resolves chat.placeholder to Chinese', () => {
    expect(i18nZh.t('chat.placeholder')).toContain('BioMate');
  });

  it('handles interpolation in Chinese', () => {
    expect(i18nZh.t('workflow.messages.running_phase', { phase: '2' })).toContain('2');
  });
});

describe('i18next — Japanese (ja)', () => {
  let i18nJa: typeof i18next;

  beforeAll(async () => {
    i18nJa = await createI18nInstance('ja');
  });

  it('resolves nav.dashboard to Japanese', () => {
    expect(i18nJa.t('nav.dashboard')).toBe('ダッシュボード');
  });

  it('resolves actions.run to Japanese', () => {
    expect(i18nJa.t('actions.run')).toBe('実行');
  });

  it('resolves workflow.status.completed to Japanese', () => {
    expect(i18nJa.t('workflow.status.completed')).toBe('完了');
  });
});

describe('i18next — Spanish (es)', () => {
  let i18nEs: typeof i18next;

  beforeAll(async () => {
    i18nEs = await createI18nInstance('es');
  });

  it('resolves nav.dashboard to Spanish', () => {
    expect(i18nEs.t('nav.dashboard')).toBe('Panel');
  });

  it('resolves actions.cancel to Spanish', () => {
    expect(i18nEs.t('actions.cancel')).toBe('Cancelar');
  });

  it('resolves errors.generic to Spanish', () => {
    expect(i18nEs.t('errors.generic')).toContain('Algo salió mal');
  });
});

describe('i18next — Fallback behaviour', () => {
  it('falls back to EN when locale is unknown', async () => {
    const i18nUnknown = await createI18nInstance('fr'); // French not supported
    // Should get English values since fr falls back to en
    expect(i18nUnknown.t('actions.run')).toBe('Run');
    expect(i18nUnknown.t('nav.dashboard')).toBe('Dashboard');
  });

  it('falls back to EN for keys missing in a locale', async () => {
    // This tests the i18next fallbackLng behaviour.
    // If a key somehow exists in EN but not in zh, zh should serve the EN value.
    const i18nZh = await createI18nInstance('zh');
    // All keys are present in zh (completeness.test.ts ensures this),
    // but verify the fallback mechanism is configured.
    expect(i18nZh.options.fallbackLng).toBeDefined();
    const fallback = i18nZh.options.fallbackLng;
    const fallbacks = Array.isArray(fallback) ? fallback : [fallback];
    expect(fallbacks).toContain('en');
  });
});
