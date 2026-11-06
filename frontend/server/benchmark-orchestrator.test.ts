import { describe, expect, it } from 'vitest';
import { ari, nmi, registerBenchmarkOrchestrator, scoreBenchmark, withFailedMethodRows, type BenchmarkDeps } from './benchmark-orchestrator';
const labels = new Map([['s1', 'a'], ['s2', 'a'], ['s3', 'b'], ['s4', 'b']]);
const mixed = new Map([['s1', 'a'], ['s2', 'b'], ['s3', 'a'], ['s4', 'b']]);
describe('benchmark evidence and ranking', () => {
  it('selects the better ground truth match', () => {
    const score = scoreBenchmark({ matching: labels, mixed }, labels);
    expect(score.winner).toBe('matching');
    expect(score.report[0]).toMatchObject({ ARI: 1, NMI: 1, rank: 1, n: 4 });
    expect(score.report[1].ARI).toBeCloseTo(-0.5);
  });
  it('requires at least two methods', () => {
    for (const methods of [{}, { only: labels }]) {
      expect(scoreBenchmark(methods, labels)).toMatchObject({ winner: null, reason: 'insufficient_methods' });
      expect(scoreBenchmark(methods).winner).toBeNull();
    }
  });
  it('rejects nonoverlapping and one-sample cohorts', () => {
    for (const second of [new Map([['x', 'a']]), new Map([['s1', 'a']])]) {
      const score = scoreBenchmark({ first: labels, second }, labels);
      expect(score).toMatchObject({ winner: null, reason: 'insufficient_common_samples' });
      expect(score.report.every(row => row.ARI === null && row.rank === null)).toBe(true);
    }
  });
  it('compares methods on one shared sample set', () => {
    const score = scoreBenchmark({ full: labels, subset: new Map([['s1', 'x'], ['s3', 'y']]) }, labels);
    expect(score.common_samples).toEqual(['s1', 's3']);
    expect(score.report.map(row => row.n)).toEqual([2, 2]);
    expect(score).toMatchObject({ winner: null, reason: 'tied' });
  });
  it('does not replace empty labels with agreement', () => {
    expect(scoreBenchmark({ first: labels, second: mixed }, new Map())).toMatchObject({
      mode: 'ground_truth', winner: null, reason: 'insufficient_common_samples',
    });
  });
  it('treats two-way agreement as a tie', () => {
    const score = scoreBenchmark({ first: labels, second: mixed });
    expect(score).toMatchObject({ winner: null, reason: 'tied' });
    expect(score.report.map(row => row.rank)).toEqual([1, 1]);
  });
  it('uses one cohort for all agreement pairs and null for unavailable values', () => {
    const score = scoreBenchmark({ first: labels, second: mixed, missing: new Map([['other', 'a']]) });
    expect(score.winner).toBeNull();
    expect(score.report.every(row => row.mean_agreement === null)).toBe(true);
  });
  it('excludes missing cluster values', () => {
    const bad = new Map(labels); bad.set('s1', ''); bad.set('s2', 'NA');
    expect(scoreBenchmark({ good: labels, bad }, labels).common_samples).toEqual(['s3', 's4']);
  });
  it('handles equivalent degenerate partitions and unequal vector lengths', () => {
    expect(ari(['a', 'a'], ['x', 'x'])).toBe(1);
    expect(nmi(['a', 'a'], ['x', 'x'])).toBe(1);
    expect(ari(['a', 'b'], ['x', 'y'])).toBe(1);
    expect(Number.isNaN(ari(['a', 'b'], ['a']))).toBe(true);
    expect(Number.isNaN(nmi(['a', 'b'], ['a']))).toBe(true);
  });
});

// Registered route with injected job/file I/O; not deployed scientific execution.
async function status(overrides: Partial<BenchmarkDeps> = {}) {
  let handler: any;
  registerBenchmarkOrchestrator({ post() {}, get(_path: string, fn: any) { handler = fn; } } as any, {
    submitRun: async () => 'unused', getRun: async () => ({ status: 'completed' }),
    getOutputFiles: async id => [{ name: `${id}_clusters.csv`, s3_uri: `s3://fixture/${id}_clusters.csv` }],
    readS3Text: async uri => uri.includes('intnmf')
      ? 'sample,cluster\ns1,a\ns2,b\ns3,a\ns4,b' : 'sample,cluster\ns1,a\ns2,a\ns3,b\ns4,b',
    ...overrides,
  });
  let body: any;
  const response = { status() { return this; }, json(value: any) { body = value; return this; } };
  await handler({ headers: { authorization: 'Bearer fixture-only' }, params: { benchmarkId: 'fixture' }, query: {
    runs: 'snf:snf,intnmf:intnmf', labels: 's3://fixture/labels.csv',
  } }, response);
  return body;
}
describe('benchmark status coverage', () => {
  it('reports complete valid comparison', async () => {
    expect(await status()).toMatchObject({ status: 'completed', winner: 'snf', coverage: { expected: 2, observed: 2 } });
  });
  it.each(['failed', 'cancelled', 'blocked'])('reports terminal %s children as partial', async failure => {
    const body = await status({ getRun: async id => ({ status: id === 'intnmf' ? failure : 'completed' }) });
    expect(body).toMatchObject({ status: 'partial', winner: null, reason: 'incomplete_method_coverage',
      coverage: { expected: 2, observed: 1, missing_methods: ['intnmf'] } });
    expect(body.children).toHaveLength(2);
  });
  it('keeps missing outputs in the denominator', async () => {
    expect(await status({ getOutputFiles: async id => id === 'intnmf' ? [] : [{ s3_uri: 's3://fixture/snf_clusters.csv' }] }))
      .toMatchObject({ status: 'partial', winner: null, coverage: { observed: 1, expected: 2 } });
  });
  it('does not switch metrics when requested labels are unreadable', async () => {
    expect(await status({ readS3Text: async uri => { if (uri.includes('labels')) throw Error('unavailable'); return 'sample,cluster\ns1,a\ns2,b'; } }))
      .toMatchObject({ status: 'failed', error: 'labels_unavailable', winner: null });
  });
  it('does not score while children run', async () => {
    expect(await status({ getRun: async () => ({ status: 'running' }), readS3Text: async () => { throw Error('must not read'); } }))
      .toMatchObject({ status: 'running' });
  });
});
it('fails explicitly when every cluster file is empty', async () => {
  expect(await status({ readS3Text: async uri => uri.includes('labels') ? 'sample,label\ns1,a\ns2,b' : 'sample,cluster' }))
    .toMatchObject({ status: 'failed', winner: null, coverage: { expected: 2, observed: 0 } });
});
it('rejects duplicate method submissions before launching jobs', async () => {
  let handler: any; let submitted = 0; let code = 200;
  registerBenchmarkOrchestrator({ post(_path: string, fn: any) { handler = fn; }, get() {} } as any, {
    submitRun: async () => { submitted++; return 'unexpected'; },
    getRun: async () => null, getOutputFiles: async () => [], readS3Text: async () => '',
  });
  await handler({ body: { omics: ['a', 'b'], methods: ['snf', 'SNF'] } }, { status(value: number) { code = value; return this; }, json() {} });
  expect(code).toBe(400); expect(submitted).toBe(0);
});

it('passes the requesting session to protected output collection', async () => {
  const headers: unknown[] = [];
  await status({ getOutputFiles: async (_id, req) => { headers.push(req.headers.authorization); return []; } });
  expect(headers).toEqual(['Bearer fixture-only', 'Bearer fixture-only']);
});

describe('withFailedMethodRows (partial comparisons surface the failed method)', () => {
  const labels = new Map([['s1', 'a'], ['s2', 'a'], ['s3', 'b'], ['s4', 'b']]);
  const mixedTwo = new Map([['s1', 'a'], ['s2', 'b'], ['s3', 'a'], ['s4', 'b']]);

  it('appends an explicit failed row per missing method; scored rows + ranking are untouched', () => {
    const score = scoreBenchmark({ snf: labels, mfa: mixedTwo }, labels);
    const rows = withFailedMethodRows(score, ['missing_method']);
    const scored = rows.filter(r => r.status === 'scored');
    const failed = rows.filter(r => r.status === 'failed');
    expect(scored.map(r => r.method).sort()).toEqual(['mfa', 'snf']);
    expect(failed).toHaveLength(1);
    const miss = failed[0];
    expect(miss.method).toBe('missing_method');
    expect(miss.rank).toBeNull();
    expect(miss.n).toBe(0);
    expect(miss.available_n).toBe(0);
    expect(miss.ARI).toBeNull();                 // ground-truth mode → null metric, never ranked
    // the scored rows keep their original ranking/winner
    expect(scored.some(r => r.rank === 1)).toBe(true);
  });

  it('is a no-op (only scored rows) when nothing is missing', () => {
    const score = scoreBenchmark({ a: labels, b: mixedTwo }, labels);
    const rows = withFailedMethodRows(score, []);
    expect(rows).toHaveLength(score.report.length);
    expect(rows.every(r => r.status === 'scored')).toBe(true);
  });
});
