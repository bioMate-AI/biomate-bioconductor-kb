import { afterEach, describe, expect, it, vi } from 'vitest';

// The model called run_code on an ad-hoc request WITHOUT input_datasets (eight times), read a guessed
// path, and gave up — INPUT_FILES was empty every try (dev, 2026-11-04). run_code now stages the
// datasets attached to this turn when the model lists none, and reads Galaxy with the user's key.
const runCode = vi.fn(async (req: any) => ({ stdout: '', stderr: '', exit_code: 0, output_files: [], duration_ms: 1, staged_inputs: {} }));
vi.mock('./code-runner', () => ({ runCode: (req: any) => runCode(req) }));
vi.mock('./routes', () => ({
  getUploadedFile: (id: string) => (id === 'uuid-1' ? { name: 'predicted_measured.csv', filePath: '/tmp/never-read' } : undefined),
}));

import { GalaxyAssistant, attachedDatasetsFromMessage } from './galaxy-assistant';

const MESSAGE = 'Correlate predicted and measured IC50 for these compounds.\n\n[Attached files: predicted_measured.csv, notes.md]\n'
  + '[Uploaded datasets: predicted_measured.csv: dataset_id=uuid-1, galaxy_dataset_id=gx1, s3_uri=s3://b/u/predicted_measured.csv; '
  + 'notes.md: dataset_id=uuid-2, galaxy_dataset_id=gx2, s3_uri=s3://b/u/notes.md]';
const assistant = () => Object.create(GalaxyAssistant.prototype) as any;
afterEach(() => { runCode.mockClear(); vi.unstubAllGlobals(); });

describe('attachedDatasetsFromMessage', () => {
  it('parses the composer block (dataset_id is not read out of galaxy_dataset_id)', () => {
    expect(attachedDatasetsFromMessage(MESSAGE)).toEqual([
      { name: 'predicted_measured.csv', datasetId: 'uuid-1', galaxyId: 'gx1' },
      { name: 'notes.md', datasetId: 'uuid-2', galaxyId: 'gx2' },
    ]);
    expect(attachedDatasetsFromMessage('a.csv: dataset_id=n/a')).toEqual([]);
    expect(attachedDatasetsFromMessage('[Uploaded datasets: a.csv: dataset_id=n/a, galaxy_dataset_id=g9]'))
      .toEqual([{ name: 'a.csv', datasetId: undefined, galaxyId: 'g9' }]);
    expect(attachedDatasetsFromMessage('no attachments here')).toEqual([]);
  });
});

describe('run_code inputs', () => {
  it('stages this turn\'s attachments under their real names when the model lists none', async () => {
    const out: any = await assistant()._toolRunCode({ language: 'python', code: 'print(1)' }, { turnMessage: MESSAGE });
    expect(runCode.mock.calls[0][0].input_datasets).toEqual([
      { id: 'gx1', filename: 'predicted_measured.csv' },
      { id: 'gx2', filename: 'notes.md' },
    ]);
    expect(out.note).toMatch(/staged the datasets attached/);
  });

  it('keeps the model\'s own input_datasets unchanged', async () => {
    const out: any = await assistant()._toolRunCode({ language: 'python', code: 'x', input_datasets: ['uuid-1'] }, { turnMessage: MESSAGE });
    expect(runCode.mock.calls[0][0].input_datasets).toEqual([{ id: 'uuid-1', filename: 'predicted_measured.csv' }]);
    expect(out.note).toBeUndefined();
  });

  it('reads Galaxy with the user\'s key, and falls back to the local copy by the attachment\'s dataset id', async () => {
    const fetchSpy = vi.fn().mockResolvedValue({ ok: false, status: 403 });
    vi.stubGlobal('fetch', fetchSpy);
    await assistant()._toolRunCode({ language: 'python', code: 'x' }, { turnMessage: MESSAGE, galaxyAPIOverride: { apiKey: 'user-key' } });
    const { downloadDataset } = runCode.mock.calls[0][0];
    // The local copy's path is fake: an ENOENT from readFile proves the galaxy-id -> dataset-id fallback found it.
    await expect(downloadDataset('gx1')).rejects.toThrow(/ENOENT/);
    expect(fetchSpy.mock.calls[0][0]).toContain('/api/datasets/gx1/display');
    expect(fetchSpy.mock.calls[0][1].headers).toEqual({ 'x-api-key': 'user-key' });
    await expect(downloadDataset('gx-unknown')).rejects.toThrow(/not accessible/);
  });
});
