import React from 'react';
import { afterEach, expect, it, vi } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import zh from '@/locales/zh/common.json';
vi.mock('@/lib/i18n', () => ({ locale: 'zh', t: (key: string, vars?: Record<string, unknown>) => {
 const value = key.split('.').reduce((v: any, part) => v?.[part], zh);
 if (typeof value !== 'string') throw new Error(`Missing Chinese key: ${key}`);
 return value.replace(/\{\{(\w+)\}\}/g, (_, k) => String(vars?.[k] ?? ''));
},
 // tOr mirrors the real helper: use the zh value when the key exists, otherwise the
 // provided English fallback (new keys like project_instructions.rules_seed_hint are
 // not in common.json yet, so they resolve to the fallback here).
 tOr: (key: string, fallback: string, vars?: Record<string, unknown>) => {
  const value = key.split('.').reduce((v: any, part) => v?.[part], zh);
  const str = typeof value === 'string' ? value : fallback;
  return str.replace(/\{\{(\w+)\}\}/g, (_, k) => String(vars?.[k] ?? ''));
} }));
import { ProjectInstructionsPage } from './project-guidance-cards';
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
it('renders Instructions controls in Chinese and preserves stored rules and formats', async () => {
 vi.stubGlobal('fetch', vi.fn(async (url: string) => ({ ok: true, json: async () => url.endsWith('instruction-settings') ? { settings: { skillPackIds: [], outputRequirements: JSON.stringify([{ kind: 'report', name: 'Hospital memo', detail: 'Preserve this user requirement', on: true }]) } } : url === '/api/skills' ? { skills: [] } : { notes: [] } })));
 render(<ProjectInstructionsPage projectId="p" projectName="Hospital" canEdit instructions="Use GRCh38" onInstructionsSaved={() => {}} />);
 expect(await screen.findByText('输出格式')).toBeTruthy();
 for (const title of ['规则', '输出格式', '技能与专家', '笔记']) expect(screen.getByText(title)).toBeTruthy();
 expect(screen.getByText('1 条规则 · 1 个格式已启用')).toBeTruthy();
 for (const text of ['Hospital memo', 'Preserve this user requirement', 'Use GRCh38']) expect(screen.getByText(text)).toBeTruthy();
 expect(screen.getByPlaceholderText('添加规则，例如“除非对话另有说明，否则使用 GRCh38”')).toBeTruthy();
 expect(screen.getByRole('button', { name: '+ 添加格式' })).toBeTruthy();
});
