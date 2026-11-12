import React from 'react';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ProjectInstructionsPage } from './project-guidance-cards';
let notes: any[], rejectDelete = false, rejectRule = false, saved = '';
beforeEach(() => {
 notes = [{ id: 12, content: 'Keep private until promoted' }]; saved = ''; rejectDelete = false; rejectRule = false;
 vi.stubGlobal('fetch', vi.fn(async (url: string, options?: RequestInit) => {
  if (options?.method === 'DELETE') { if (rejectDelete) return { ok: false }; notes = []; return { ok: true }; }
  if (options?.method === 'PATCH') { if (rejectRule) return { ok: false }; saved = JSON.parse(String(options.body)).researchGoal; return { ok: true }; }
  return { ok: true, json: async () => url.endsWith('instruction-settings') ? { settings: {} } : url === '/api/skills' ? { skills: [] } : { notes } };
 }));
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
const open = () => render(<ProjectInstructionsPage projectId="p" projectName="Project" canEdit instructions={saved} onInstructionsSaved={() => {}} />);
it('deletes notes durably and keeps the note visible when deletion fails', async () => {
 const view = open(); await screen.findByText('Keep private until promoted');
 expect(screen.queryByRole('switch', { name: 'Remember from chats' })).toBeNull();
 rejectDelete = true; fireEvent.click(screen.getByRole('button', { name: 'Forget' }));
 await screen.findByRole('alert'); expect(notes).toHaveLength(1); expect(screen.getByText('Keep private until promoted')).toBeTruthy();
 rejectDelete = false; fireEvent.click(screen.getByRole('button', { name: 'Forget' }));
 await waitFor(() => expect(screen.queryByText('Keep private until promoted')).toBeNull());
 view.unmount(); open(); await screen.findByText(/No notes yet/); expect(notes).toEqual([]);
});
it('promotes only after successful rule persistence and preserves the original note on reload', async () => {
 const view = open(); await screen.findByText('Keep private until promoted');
 rejectRule = true; fireEvent.click(screen.getByRole('button', { name: 'Make a rule' }));
 await screen.findByRole('alert'); expect(saved).toBe(''); expect(notes).toHaveLength(1);
 expect(screen.getByTestId('instructions-rules').textContent).not.toContain('Keep private until promoted');
 rejectRule = false; fireEvent.click(screen.getByRole('button', { name: 'Make a rule' }));
 await waitFor(() => expect(saved).toBe('Keep private until promoted'));
 view.unmount(); open(); await waitFor(() => expect(screen.getAllByText('Keep private until promoted')).toHaveLength(2));
 expect(notes).toHaveLength(1);
});
