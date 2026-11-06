import { afterEach, describe, expect, it, vi } from 'vitest';
import { PREPARED_EXAMPLES, prepareColdStartExample, ensureInternalDemoProject, DEMO_PROJECT_NAME } from './cold-start-examples';
afterEach(() => vi.unstubAllGlobals());
const reply = (body: unknown) => ({ ok: true, json: async () => body });
describe('prepared examples', () => {
  it('loads all three MG input files before returning the draft', async () => {
    const fetcher = vi.fn().mockImplementation(async () => ({ ok: true, blob: async () => new Blob(['sample,condition\na,HC'], { type: 'text/csv' }) }));
    vi.stubGlobal('fetch', fetcher);
    const result = await prepareColdStartExample(PREPARED_EXAMPLES[0].label);
    expect(result.files.map(file => file.name)).toEqual(['counts_matrix.csv', 'sample_metadata.csv', 'contrasts.csv']);
    expect(result.prompt).toContain('GSE227835');
    expect(fetcher).toHaveBeenCalledTimes(3);
  });
  it('rejects an HTML fallback instead of attaching it as sample data', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({ ok: true, blob: async () => new Blob(['<html>'], { type: 'text/html' }) }));
    await expect(prepareColdStartExample(PREPARED_EXAMPLES[0].label)).rejects.toThrow('unavailable');
  });
  it('leaves user-data examples as drafts without loading unrelated data', async () => {
    const fetcher = vi.fn(); vi.stubGlobal('fetch', fetcher);
    expect(await prepareColdStartExample('Analyze my own counts')).toEqual({ prompt: 'Analyze my own counts', files: [] });
    expect(fetcher).not.toHaveBeenCalled();
  });
  it('creates a real project and uploads its inputs', async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(reply({ projects: [] })).mockResolvedValueOnce(reply({ project: { id: 'demo' } })).mockResolvedValueOnce(reply({ files: [] })).mockResolvedValue(reply({ file: {} }));
    vi.stubGlobal('fetch', fetcher);
    const file = new File(['counts'], 'counts_matrix.csv');
    expect(await ensureInternalDemoProject([file])).toBe('demo');
    expect(JSON.parse(fetcher.mock.calls[1][1].body).name).toBe(DEMO_PROJECT_NAME);
    expect(fetcher.mock.calls[3][0]).toBe('/api/projects/demo/files/upload');
    expect(fetcher.mock.calls[3][1].body.get('file').name).toBe(file.name);
  });
  it('reuses the fixture and uploads only missing files after interruption', async () => {
    const fetcher = vi.fn().mockResolvedValueOnce(reply({ projects: [{ id: 'demo', name: DEMO_PROJECT_NAME }] })).mockResolvedValueOnce(reply({ files: [{ name: 'counts_matrix.csv' }] })).mockResolvedValue(reply({ file: {} }));
    vi.stubGlobal('fetch', fetcher);
    await ensureInternalDemoProject([new File(['a'], 'counts_matrix.csv'), new File(['b'], 'contrasts.csv')]);
    expect(fetcher).toHaveBeenCalledTimes(3);
    expect(fetcher.mock.calls[2][1].body.get('file').name).toBe('contrasts.csv');
  });
});
