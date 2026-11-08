import { afterEach, expect, it, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import { TrainingRegistration } from './training-registration';
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });
it('registers with no client-supplied metrics and displays refreshed persisted versions', async () => {
 const version = { campaign_id: 'c', model_name: 'subtype', version: 2, status: 'candidate', gate: { passed: true, reason: 'Accuracy gate passed' } };
 const fetcher = vi.fn().mockResolvedValueOnce({ ok: true, json: async () => version }).mockResolvedValueOnce({ ok: true, json: async () => ({ versions: [version] }) }); vi.stubGlobal('fetch', fetcher);
 render(<TrainingRegistration runId="run1" eligible />); fireEvent.click(screen.getByText('Register training result'));
 expect(await screen.findByTestId('training-registered-version')).toHaveTextContent('subtype · v2 · candidate');
 expect(fetcher.mock.calls[0][0]).toBe('/api/model-training-activity/run1/register'); expect(fetcher.mock.calls[0][1].body).toBe('{}');
 expect(fetcher.mock.calls[1][0]).toBe('/api/model-training-activity/run1/versions');
});
it('does not advertise registration for historical runs and surfaces access failures', async () => {
 vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: false, json: async () => ({ error: 'Not your training run' }) }));
 render(<TrainingRegistration runId="old" />); expect(screen.queryByText('Register training result')).toBeNull();
 fireEvent.click(screen.getByText('Check registered versions')); expect(await screen.findByRole('alert')).toHaveTextContent('Not your training run');
});
