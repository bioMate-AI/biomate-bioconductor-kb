/**
 * Hover hints — coverage + behaviour.
 *
 * 1. Every `hint.*` key the source references exists, non-empty, in BOTH zh and
 *    en, and the two bundles carry the same hint keys.
 * 2. Templated keys (`hint.afterrun.${id}`, `hint.models.${track}`,
 *    `hint.chat_status.${status}`) resolve for every value the code can pass.
 * 3. A hint says more than its label (never just repeats it).
 * 4. Keyboard focus on a sidebar item opens its hint tooltip (not a native title).
 * 5. A hinted Radix tab keeps data-state="active" (the tooltip must not
 *    overwrite it — the selected tab would lose its styling).
 */
import React from 'react';
import fs from 'fs';
import path from 'path';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import zh from '@/locales/zh/common.json';
import en from '@/locales/en/common.json';
import { MODELS_TRACKS } from '@/components/models/models-panel';
import { Tabs, TabsList } from '@/components/ui/tabs';
import { HintTabsTrigger } from '@/components/ui/hint-tip';

const SRC = path.resolve(__dirname, '../..');

function leaves(o: any, p = ''): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(o || {})) {
    const key = p ? `${p}.${k}` : k;
    if (v && typeof v === 'object') Object.assign(out, leaves(v, key));
    else out[key] = String(v);
  }
  return out;
}
const get = (bundle: any, key: string) => key.split('.').reduce((o, k) => (o == null ? o : o[k]), bundle);

function sourceFiles(dir: string): string[] {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) return e.name === 'locales' || e.name === 'node_modules' ? [] : sourceFiles(p);
    return /\.tsx?$/.test(e.name) && !/\.test\.tsx?$/.test(e.name) ? [p] : [];
  });
}

describe('hint keys', () => {
  const zhHints = leaves((zh as any).hint, 'hint');
  const enHints = leaves((en as any).hint, 'hint');

  it('zh and en carry the same hint keys, all non-empty', () => {
    expect(Object.keys(zhHints).sort()).toEqual(Object.keys(enHints).sort());
    for (const [k, v] of [...Object.entries(zhHints), ...Object.entries(enHints)]) {
      expect(v.trim(), k).not.toBe('');
    }
  });

  it('every literal hint key referenced in the source exists in both locales', () => {
    const used = new Set<string>();
    for (const f of sourceFiles(SRC)) {
      const s = fs.readFileSync(f, 'utf8');
      for (const m of s.matchAll(/['"`](hint\.[a-z_]+\.[a-z_]+)['"`]/g)) used.add(m[1]);
    }
    expect(used.size).toBeGreaterThan(15);
    for (const k of used) {
      expect(zhHints[k], `zh ${k}`).toBeTruthy();
      expect(enHints[k], `en ${k}`).toBeTruthy();
    }
  });

  it('templated hint keys resolve for every value the code passes', () => {
    const afterRun = fs.readFileSync(path.join(SRC, 'v2/AfterRunReport.tsx'), 'utf8');
    const tabIds = [...afterRun.matchAll(/\["([a-z]+)", tOr\('afterrun\.tab\./g)].map((m) => m[1]);
    expect(tabIds).toEqual(['summary', 'outputs', 'report']);
    const keys = [
      ...tabIds.map((id) => `hint.afterrun.${id}`),
      ...MODELS_TRACKS.map((t) => `hint.models.${t}`),
      ...['running', 'completed', 'failed', 'cancelled', 'idle'].map((s) => `hint.chat_status.${s}`),
    ];
    for (const k of keys) {
      expect(zhHints[k], `zh ${k}`).toBeTruthy();
      expect(enHints[k], `en ${k}`).toBeTruthy();
    }
  });

  it('a hint is not just its label repeated', () => {
    const pairs: Array<[string, string]> = [
      ['hint.nav.data', 'nav.data'],
      ['hint.nav.workflows', 'nav.workflows'],
      ['hint.nav.models', 'nav.models'],
      ['hint.nav.projects', 'nav.projects'],
      ['hint.nav.settings', 'settings.title'],
      ['hint.afterrun.summary', 'afterrun.tab.summary'],
      ['hint.afterrun.outputs', 'afterrun.tab.outputs'],
      ['hint.models.train', 'models.tab_train'],
      ['hint.models.library', 'models.tab_library'],
    ];
    for (const bundle of [zh, en]) {
      for (const [h, l] of pairs) {
        const hint = get(bundle, h) as string;
        const label = get(bundle, l) as string;
        expect(hint, h).toBeTruthy();
        expect(hint.length, h).toBeGreaterThan((label || '').length + 6);
      }
    }
  });
});

vi.mock('wouter', () => ({ useLocation: () => ['/', vi.fn()] }));
vi.mock('@/contexts/auth-context', () => ({
  useAuth: () => ({ user: { id: 1, email: 'lifeifei163361@163.com' }, logout: vi.fn() }),
}));
vi.mock('@/contexts/active-project-context', () => ({
  useActiveProject: () => ({ activeProjectId: null, setActiveProjectId: vi.fn() }),
}));
vi.mock('@/components/settings-dialog', () => ({ SettingsDialog: () => null }));
vi.mock('@/components/workflow-history-dialog', () => ({ WorkflowHistoryDialog: () => null }));
vi.mock('@/components/workflows-library-dialog', () => ({ WorkflowsLibraryDialog: () => null }));

import { AppSidebar } from '@/components/app-sidebar';

describe('sidebar hints', () => {
  beforeEach(() => {
    global.fetch = vi.fn(async () => ({
      ok: true, status: 200, json: async () => ({ projects: [], total: 0 }), text: async () => '[]',
    })) as any;
  });

  it('keyboard focus on a nav item shows its hint; no native title remains', async () => {
    render(<AppSidebar chatSessions={[] as any} />);
    const data = screen.getByTestId('button-data-nav');
    expect(data.getAttribute('title')).toBeNull();
    fireEvent.focus(data);
    const tip = await screen.findByRole('tooltip');
    expect(tip.textContent).toBe((en as any).hint.nav.data);
    for (const id of ['button-sidebar-toggle', 'button-logout', 'button-workflows-nav', 'button-models-nav',
      'button-projects-section', 'button-new-project', 'button-settings-sidebar']) {
      expect(screen.getByTestId(id).getAttribute('title'), id).toBeNull();
    }
  });
});

describe('HintTabsTrigger', () => {
  it('keeps the tab state attributes and shows its hint on focus', async () => {
    render(
      <Tabs defaultValue="a">
        <TabsList>
          <HintTabsTrigger value="a" hint="Hint A" data-testid="ta">A</HintTabsTrigger>
          <HintTabsTrigger value="b" hint="Hint B" data-testid="tb">B</HintTabsTrigger>
        </TabsList>
      </Tabs>,
    );
    const a = screen.getByTestId('ta');
    const b = screen.getByTestId('tb');
    expect(a.getAttribute('data-state')).toBe('active');
    expect(b.getAttribute('data-state')).toBe('inactive');
    expect(a.getAttribute('role')).toBe('tab');
    fireEvent.focus(b);
    expect((await screen.findByRole('tooltip')).textContent).toBe('Hint B');
    // Radix tabs activate on focus: with the tooltip open, the tab — not the
    // tooltip — still owns data-state.
    await waitFor(() => expect(b.getAttribute('data-state')).toBe('active'));
    expect(a.getAttribute('data-state')).toBe('inactive');
  });
});
