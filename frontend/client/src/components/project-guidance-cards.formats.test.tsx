import React from 'react';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';
import { render, screen, fireEvent, waitFor, within, cleanup } from '@testing-library/react';
import { ProjectInstructionsPage } from './project-guidance-cards';
import { EXAMPLE_OUTPUT_FORMATS, appendMissingOutputFormats } from '@/lib/output-requirements';
const original = { ...EXAMPLE_OUTPUT_FORMATS[0], on: true };
let stored: any[], requests: any[], rejectSave = false;
beforeEach(() => {
 stored = [{ ...original }]; requests = []; rejectSave = false;
 vi.stubGlobal('fetch', vi.fn(async (url: string, options?: RequestInit) => {
  if (options?.method === 'PATCH') {
   const body = JSON.parse(String(options.body)); requests.push(body);
   if (rejectSave) return { ok: false };
   stored = JSON.parse(body.outputRequirements); return { ok: true };
  }
  return { ok: true, json: async () => url.endsWith('instruction-settings') ? { settings: { skillPackIds: ['existing-skill'], outputRequirements: JSON.stringify(stored) } } : url === '/api/skills' ? { skills: [] } : { notes: [] } };
 }));
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
async function open() {
 render(<ProjectInstructionsPage projectId="p1" projectName="Project" canEdit instructions="" onInstructionsSaved={() => {}} />);
 await screen.findByRole('button', { name: 'Edit' });
}
describe('output format editor', () => {
 it('persists name, kind and requirements, preserving selected skills and enabled state', async () => {
  await open(); fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
  const editor = screen.getByRole('dialog', { name: 'Edit output format' });
  fireEvent.change(within(editor).getByLabelText('Name'), { target: { value: 'Study table' } });
  fireEvent.change(within(editor).getByLabelText('Kind'), { target: { value: 'table' } });
  fireEvent.change(within(editor).getByLabelText('Requirements'), { target: { value: 'Adjusted p-values' } });
  fireEvent.click(within(editor).getByRole('button', { name: 'Save' }));
  await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());
  expect(requests[0].skillPackIds).toEqual(['existing-skill']);
  expect(stored).toEqual([{ kind: 'table', name: 'Study table', detail: 'Adjusted p-values', on: true }]);
 });
 it('cancel leaves saved content unchanged and adding does not persist a placeholder', async () => {
  await open(); fireEvent.click(screen.getByRole('button', { name: '+ Add a format' }));
  const editor = screen.getByRole('dialog');
  expect(within(editor).getByRole('button', { name: 'Save' }).hasAttribute('disabled')).toBe(true);
  fireEvent.change(within(editor).getByLabelText('Name'), { target: { value: 'Discarded' } });
  fireEvent.click(within(editor).getByRole('button', { name: 'Cancel' }));
  expect(screen.queryByRole('dialog')).toBeNull();
  expect(requests).toEqual([]); expect(stored).toEqual([original]);
 });
 it('retains draft and saved content when persistence fails', async () => {
  await open(); rejectSave = true;
  fireEvent.click(screen.getByRole('button', { name: 'Edit' }));
  fireEvent.change(screen.getByLabelText('Name'), { target: { value: 'Unsaved name' } });
  fireEvent.click(screen.getByRole('button', { name: 'Save' }));
  const alert = await screen.findByRole('alert');
  expect(alert.textContent).toContain('Your changes have not been saved');
  expect(screen.getByRole('dialog')).toBeTruthy(); expect(stored).toEqual([original]);
 });
 it('shows actual template preview without fake errors or requests', async () => {
  await open(); fireEvent.click(screen.getByRole('button', { name: 'Preview' }));
  const preview = screen.getByRole('dialog', { name: 'Output format preview' });
  expect(within(preview).getByText(original.detail)).toBeTruthy();
  expect(within(preview).getByText(/not a generated run report/)).toBeTruthy();
  expect(screen.queryByRole('alert')).toBeNull(); expect(requests).toEqual([]);
  fireEvent.click(within(preview).getByRole('button', { name: 'Close preview' }));
  expect(screen.queryByRole('dialog')).toBeNull();
 });
 it('bulk insertion preserves an enabled existing template and prevents repeats', async () => {
  await open(); fireEvent.click(screen.getByRole('button', { name: 'Start from these examples' }));
  await waitFor(() => expect(stored).toHaveLength(4));
  await waitFor(() => expect(screen.getByRole('button', { name: 'Start from these examples' }).hasAttribute('disabled')).toBe(true));
  expect(stored[0]).toEqual(original);
 });
});
it('idempotent insertion preserves existing duplicates and deliberate user variants', () => {
 const variant = { ...original, detail: 'Different requirement' };
 const existing = [original, original, variant];
 const once = appendMissingOutputFormats(existing, EXAMPLE_OUTPUT_FORMATS);
 expect(once).toHaveLength(6);
 expect(appendMissingOutputFormats(once, EXAMPLE_OUTPUT_FORMATS)).toEqual(once);
 expect(once.slice(0, 3)).toEqual(existing);
});
