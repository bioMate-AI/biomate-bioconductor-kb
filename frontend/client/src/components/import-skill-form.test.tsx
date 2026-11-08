import { afterEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { ImportSkillForm } from './import-skill-form';
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
it('imports original Markdown through the validated endpoint and refreshes the list', async () => {
 const content = '---\nname: oncology-review\ndescription: Review\n---\nCheck citations.';
 const fetcher = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ success: true }) }); vi.stubGlobal('fetch', fetcher);
 const refresh = vi.fn(); render(<ImportSkillForm onImported={refresh} />);
 fireEvent.change(screen.getByLabelText('Import a skill file (.md)'), { target: { files: [{ name: 'oncology.md', text: async () => content }] } });
 await waitFor(() => expect(refresh).toHaveBeenCalledOnce());
 expect(fetcher.mock.calls[0][0]).toBe('/api/skills/upload');
 expect(JSON.parse(fetcher.mock.calls[0][1].body)).toEqual({ content, filename: 'oncology.md' });
});
it('surfaces access or validation errors and preserves the existing library', async () => {
 const fetcher = vi.fn().mockResolvedValue({ ok: false, json: async () => ({ error: 'Personal Galaxy access is required.' }) }); vi.stubGlobal('fetch', fetcher);
 const refresh = vi.fn(); render(<ImportSkillForm onImported={refresh} />);
 fireEvent.change(screen.getByLabelText('Import a skill file (.md)'), { target: { files: [{ name: 'expert.md', text: async () => 'bad' }] } });
 expect(await screen.findByRole('alert')).toHaveTextContent('Personal Galaxy access'); expect(refresh).not.toHaveBeenCalled();
});
