import { afterEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { OwnedTrainingRegistry } from './owned-training-registry';
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
it('reads scoped persisted versions and exposes actual evidence without inference controls', async () => {
 const fetcher = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ versions: [{ model_name: 'Tumor subtype', version: 3, status: 'candidate', artifact_sha256: 'abc', gate: { metric: 'accuracy', value: 0.8, threshold: 0.7 }, spec: { sourceRunId: 'run1' } }] }) }); vi.stubGlobal('fetch', fetcher);
 render(<OwnedTrainingRegistry project="project/1" />);
 expect(await screen.findByText('Tumor subtype · v3 · candidate')).toBeVisible();
 expect(fetcher.mock.calls[0][0]).toBe('/api/model-training-versions?project=project%2F1');
 fireEvent.click(screen.getByText('Tumor subtype · v3 · candidate'));
 expect(screen.getByText('Source run: run1')).toBeVisible(); expect(screen.queryByText('Run inference')).toBeNull();
});
it('shows registry access failure rather than an empty success', async () => {
 vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, json: async () => ({ error: 'Project access denied' }) }));
 render(<OwnedTrainingRegistry project="foreign" />);
 expect(await screen.findByRole('alert')).toHaveTextContent('Project access denied');
 expect(screen.queryByText('No training artifacts have been registered in this scope.')).toBeNull();
});
