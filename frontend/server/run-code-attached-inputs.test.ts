import { afterEach, describe, expect, it, vi } from 'vitest';

// The model called run_code on an ad-hoc request WITHOUT input_datasets (eight times), read a guessed
// path, and gave up — INPUT_FILES was empty every try (dev, 2026-11-04). run_code now stages the
// datasets attached to this turn when the model lists none, and reads Galaxy with the user's key.
const runCode = vi.fn(async (req: any) => ({ stdout: '', stderr: '', exit_code: 0, output_files: [], duration_ms: 1, staged_inputs: {} }));
vi.mock('./code-runner', async () => ({
  ...(await vi.importActual<typeof import('./code-runner')>('./code-runner')),
  runCode: (req: any) => runCode(req),
}));
vi.mock('./routes', () => ({
  getUploadedFile: (id: string) => (id === 'uuid-1' ? { name: 'predicted_measured.csv', filePath: '/tmp/never-read' } : undefined),
}));

import { GalaxyAssistant, attachedDatasetsFromMessage, headLines, runCodeInputsNote } from './galaxy-assistant';
import { stagedInputPath } from './code-runner';

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

  it('reads the local copy of an upload via the attachment\'s dataset id, and Galaxy-only datasets with the user\'s key', async () => {
    const fetchSpy = vi.fn(async (url: string) => url.endsWith('/display') ? new Response('a,b\n') : Response.json({ state: 'ok' }));
    vi.stubGlobal('fetch', fetchSpy);
    await assistant()._toolRunCode({ language: 'python', code: 'x' }, { turnMessage: MESSAGE, galaxyAPIOverride: { apiKey: 'user-key' } });
    const { downloadDataset } = runCode.mock.calls[0][0];
    // The local copy's path is fake: ENOENT proves the galaxy-id -> dataset-id lookup chose it, without Galaxy.
    await expect(downloadDataset('gx1')).rejects.toThrow(/ENOENT/);
    expect(fetchSpy).not.toHaveBeenCalled();
    await downloadDataset('gx2'); // no local copy -> Galaxy
    const display = fetchSpy.mock.calls.find((c: any) => String(c[0]).endsWith('/api/datasets/gx2/display'))!;
    expect((display as any)[1].headers).toEqual({ 'x-api-key': 'user-key' });
  });
});

describe('runCodeInputsNote — exact paths before the first run_code call', () => {
  it('names each attached file at the path run_code stages it (prompt and runner agree)', async () => {
    const note = runCodeInputsNote(MESSAGE);
    const paths = JSON.parse(note.slice(note.indexOf('{'), note.lastIndexOf('}') + 1));
    expect(paths).toEqual({
      'predicted_measured.csv': '/work/input/gx1/predicted_measured.csv',
      'notes.md': '/work/input/gx2/notes.md',
    });
    // the same ids/filenames _toolRunCode stages -> the same container paths the runner reports
    await assistant()._toolRunCode({ language: 'python', code: 'x' }, { turnMessage: MESSAGE });
    const staged = runCode.mock.calls[0][0].input_datasets.map((r: any) => stagedInputPath(r.id, r.filename));
    expect(staged).toEqual(Object.values(paths));
  });

  it('is empty when nothing is attached', () => {
    expect(runCodeInputsNote('Correlate predicted and measured IC50.')).toBe('');
  });
});

describe('first lines of attached files — real column names before the first run_code call', () => {
  // dev 2026-11-04: [13]'s first call melted plate_layout.csv on a guessed "index" column (the file's
  // first column is "row") and failed with KeyError; the model had not seen the header.
  it('adds the heads of attached files only (never of names that are not attached)', () => {
    const note = runCodeInputsNote(MESSAGE, { 'predicted_measured.csv': ['compound_id,predicted,measured', 'C1,5.1,5.4'], 'other.csv': ['x'] });
    const heads = JSON.parse(note.slice(note.indexOf('{', note.indexOf('First lines')), note.lastIndexOf('}') + 1));
    expect(heads).toEqual({ 'predicted_measured.csv': ['compound_id,predicted,measured', 'C1,5.1,5.4'] });
    expect(runCodeInputsNote(MESSAGE, {})).not.toMatch(/First lines/);
  });

  it('headLines reads only the start of a stream and closes it', async () => {
    let closed = false, pulled = 0;
    async function* stream() {
      try {
        for (const c of ['row,01,02\nA,1', '0,20\nB,30,40\nC,5', '0,60\n', 'D,70,80\n']) { pulled++; yield Buffer.from(c); }
      } finally { closed = true; }
    }
    expect(await headLines(stream(), 3)).toEqual(['row,01,02', 'A,10,20', 'B,30,40']);
    expect(closed).toBe(true);
    expect(pulled).toBe(2); // three complete lines are buffered after the 2nd chunk
    async function* long() { yield Buffer.from('x'.repeat(1000) + '\nsecond'); }
    expect((await headLines(long(), 3, 4096, 300))[0]).toHaveLength(300);
  });

  it('reads the heads of attached text tables with the user\'s key and skips other files', async () => {
    const fetchSpy = vi.fn(async (url: string) => url.endsWith('/display')
      ? new Response('row,01,02\nA,10,20\nB,30,40\nC,50,60\n')
      : Response.json({ state: 'ok' }));
    vi.stubGlobal('fetch', fetchSpy);
    const remote = '[Uploaded datasets: plate.csv: dataset_id=uuid-9, galaxy_dataset_id=gx9; notes.md: dataset_id=uuid-8, galaxy_dataset_id=gx8]';
    const heads = await assistant()._attachedFileHeads(remote, { galaxyAPIOverride: { apiKey: 'user-key' } });
    expect(heads).toEqual({ 'plate.csv': ['row,01,02', 'A,10,20', 'B,30,40'] });
    const urls = fetchSpy.mock.calls.map((c: any) => c[0]);
    expect(urls.every((u: string) => u.includes('/api/datasets/gx9'))).toBe(true); // notes.md is not previewed
    expect((fetchSpy.mock.calls.find((c: any) => c[0].endsWith('/display')) as any)[1].headers).toEqual({ 'x-api-key': 'user-key' });
  });

  it('leaves out a file it cannot read', async () => {
    vi.stubGlobal('fetch', vi.fn().mockRejectedValue(new Error('down')));
    expect(await assistant()._attachedFileHeads(MESSAGE, {})).toEqual({});
  });
});

describe('_openDataset — never stages a Galaxy dataset whose upload job is still running', () => {
  // dev 2026-11-04: for ~19 s after upload Galaxy reports state=running while /display answers 200 with
  // 0 bytes (then a partial body); run_code staged an empty file -> pandas EmptyDataError.
  const galaxy = (states: string[], body = 'a,b\n1,2\n') => {
    let i = 0;
    return vi.fn(async (url: string) => url.endsWith('/display')
      ? new Response('')  // what Galaxy serves mid-upload — must never be used while state != ok
      : Response.json({ state: states[Math.min(i++, states.length - 1)] }));
  };
  const read = async (it: AsyncIterable<Buffer>) => { let t = ''; for await (const c of it) t += c.toString(); return t; };

  it('reads the local copy of an upload without asking Galaxy at all (no state race under load)', async () => {
    const f = galaxy(['running']);
    vi.stubGlobal('fetch', f);
    // uuid-1's local path is fake: ENOENT proves the local copy was chosen
    await expect(assistant()._openDataset('gx1', 'k', 'uuid-1')).rejects.toThrow(/ENOENT/);
    expect(f).not.toHaveBeenCalled();
  });

  it('waits for the job when there is no local copy, then reads Galaxy', async () => {
    vi.useFakeTimers();
    try {
      let i = 0;
      const f = vi.fn(async (url: string) => url.endsWith('/display')
        ? new Response('a,b\n1,2\n')
        : Response.json({ state: ['queued', 'running', 'ok'][Math.min(i++, 2)] }));
      vi.stubGlobal('fetch', f);
      const p = assistant()._openDataset('gx-remote', 'k');
      await vi.advanceTimersByTimeAsync(5000);
      expect(await read(await p)).toBe('a,b\n1,2\n');
      expect(f.mock.calls.filter((c: any) => !c[0].endsWith('/display'))).toHaveLength(3);
    } finally {
      vi.useRealTimers();
    }
  });

  it('fails loudly (not an empty file) when the job never finishes or errors', async () => {
    vi.stubGlobal('fetch', galaxy(['error']));
    await expect(assistant()._openDataset('gx-remote', 'k')).rejects.toThrow(/not ready in Galaxy \(state: error\)/);
    vi.stubGlobal('fetch', galaxy(['running']));
    await expect(assistant()._openDataset('gx-remote', 'k', undefined, 0)).rejects.toThrow(/state: running/);
  });
});

describe('run_code history — earlier successful Python cells of the same turn are replayed', () => {
  it('passes this turn\'s successful Python cells, not failed ones, not R, not another turn\'s', async () => {
    const a = assistant();
    const ctx: any = { turnMessage: MESSAGE };
    runCode.mockResolvedValueOnce({ stdout: '', stderr: '', exit_code: 0, output_files: [], duration_ms: 1, staged_inputs: {} });
    await a._toolRunCode({ language: 'python', code: 'df = load()' }, ctx);
    runCode.mockResolvedValueOnce({ stdout: '', stderr: 'boom', exit_code: 1, output_files: [], duration_ms: 1, staged_inputs: {} });
    await a._toolRunCode({ language: 'python', code: 'broken()' }, ctx);
    await a._toolRunCode({ language: 'python', code: 'df.describe()' }, ctx);
    await a._toolRunCode({ language: 'r', code: 'x <- 1' }, ctx);
    expect(runCode.mock.calls[0][0].prior_code).toBeUndefined();
    expect(runCode.mock.calls[2][0].prior_code).toEqual(['df = load()']);
    expect(runCode.mock.calls[3][0].prior_code).toBeUndefined();
    ctx.turnMessage = 'next question';
    await a._toolRunCode({ language: 'python', code: 'y = 1' }, ctx);
    expect(runCode.mock.calls[4][0].prior_code).toBeUndefined();
  });
});
