import hospitalProvenance from '../../public/demo/sysucc_synthetic/provenance.json';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { PREPARED_EXAMPLES, prepareColdStartExample, ensureInternalDemoProject, DEMO_PROJECT_NAME, HOSPITAL_EXAMPLES, HOSPITAL_DEMO_PROJECT_NAME, prepareColdStartSelection } from './cold-start-examples';
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
    const fetcher = vi.fn().mockResolvedValueOnce(reply({ projects: [{ id: 'demo', name: DEMO_PROJECT_NAME, HOSPITAL_EXAMPLES, HOSPITAL_DEMO_PROJECT_NAME, prepareColdStartSelection }] })).mockResolvedValueOnce(reply({ files: [{ name: 'counts_matrix.csv' }] })).mockResolvedValue(reply({ file: {} }));
    vi.stubGlobal('fetch', fetcher);
    await ensureInternalDemoProject([new File(['a'], 'counts_matrix.csv'), new File(['b'], 'contrasts.csv')]);
    expect(fetcher).toHaveBeenCalledTimes(3);
    expect(fetcher.mock.calls[2][1].body.get('file').name).toBe('contrasts.csv');
  });
});

 describe('hospital synthetic case preparation', () => {
  it('loads the preserved cohort files and creates a dedicated project without launching a workflow', async () => {
    const fetcher = vi.fn(async (url: string, init?: RequestInit) => {
      if (url.startsWith('/demo/')) return { ok: true, blob: async () => new Blob(['synthetic'], { type: 'text/plain' }) };
      if (url === '/api/projects' && !init?.method) return reply({ projects: [] });
      if (url === '/api/projects') return reply({ project: { id: 'hospital-demo' } });
      if (url.endsWith('/files')) return reply({ files: [] });
      return reply({ file: {} });
    });
    vi.stubGlobal('fetch', fetcher);
    const result = await prepareColdStartSelection(HOSPITAL_EXAMPLES[0].label);
    expect(result.projectId).toBe('hospital-demo');
    expect(result.files.map(file => file.name)).toContain('rna.csv');
    expect(result.prompt).toContain('synthetic');
    expect(result.prompt).toContain('Stop for confirmation');
    expect(result.prompt).not.toContain('ARI 0.978');
    const create = fetcher.mock.calls.find(([url, init]) => url === '/api/projects' && init?.method === 'POST');
    expect(JSON.parse(String(create?.[1]?.body)).name).toBe(HOSPITAL_DEMO_PROJECT_NAME);
    expect(fetcher.mock.calls.some(([url]) => /execute|generate_workflow|chat\/stream/.test(url))).toBe(false);
  });
  it('keeps the supervised label and ID exclusions explicit', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => ({ ok: true, blob: async () => new Blob(['synthetic']) })));
    const result = await prepareColdStartExample(HOSPITAL_EXAMPLES[1].label);
    expect(result.files.map(file => file.name)).toEqual(['mo_feature_matrix.csv', 'README.md', 'provenance.json']);
    expect(result.prompt).toContain('label_column=subtype');
    expect(result.prompt).toContain('Exclude sample_id');
    expect(result.prompt).toContain('cv_folds=5');
  });
 });

it('does not overwrite changed historical hospital inputs on resuming setup', async () => {
  const fetcher = vi.fn().mockResolvedValueOnce(reply({ projects: [{ id: 'demo', name: HOSPITAL_DEMO_PROJECT_NAME, description: 'Preserved synthetic multi-omics validation inputs for repeatable hospital demonstrations; no patient data.' }] })).mockResolvedValueOnce(reply({ files: [{ name: 'rna.csv', content_hash: 'changed-by-user' }] }));
  vi.stubGlobal('fetch', fetcher);
  await expect(ensureInternalDemoProject([new File(['fixture'], 'rna.csv')], true)).rejects.toThrow('It was not overwritten');
  expect(fetcher).toHaveBeenCalledTimes(2);
});

it('does not reuse an unrelated project with the same display name', async () => {
  const fetcher = vi.fn().mockResolvedValueOnce(reply({ projects: [{ id: 'unrelated', name: HOSPITAL_DEMO_PROJECT_NAME, description: 'User research' }] })).mockResolvedValueOnce(reply({ project: { id: 'new-demo' } })).mockResolvedValueOnce(reply({ files: [] })).mockResolvedValue(reply({ file: {} }));
  vi.stubGlobal('fetch', fetcher);
  expect(await ensureInternalDemoProject([new File(['a'], 'rna.csv')], true)).toBe('new-demo');
  expect(fetcher.mock.calls[3][0]).toBe('/api/projects/new-demo/files/upload');
});

it('reuses verified hospital bytes and resumes only missing uploads', async () => {
  const fetcher = vi.fn().mockResolvedValueOnce(reply({ projects: [{ id: 'demo', name: HOSPITAL_DEMO_PROJECT_NAME, description: 'Preserved synthetic multi-omics validation inputs for repeatable hospital demonstrations; no patient data.' }] })).mockResolvedValueOnce(reply({ files: [{ name: 'rna.csv', content_hash: hospitalProvenance.files['rna.csv'].sha256 }] })).mockResolvedValue(reply({ file: {} }));
  vi.stubGlobal('fetch', fetcher);
  expect(await ensureInternalDemoProject([new File(['fixture'], 'rna.csv'), new File(['fixture'], 'protein.csv')], true)).toBe('demo');
  expect(fetcher).toHaveBeenCalledTimes(3);
  expect(fetcher.mock.calls[2][1].body.get('file').name).toBe('protein.csv');
});
