import { beforeEach, describe, expect, it, vi } from 'vitest';
import { translateLabels, needsTranslation, _resetLabelCache } from './label-translation';

beforeEach(() => _resetLabelCache());

describe('needsTranslation — prose labels only', () => {
  it.each(['Input Download', 'Differential Abundance', 'Samplesheet', 'Run DESeq2 per contrast'])('translates %s', s => {
    expect(needsTranslation(s)).toBe(true);
  });
  it.each(['差异丰度分析', 'counts_matrix.csv', 'nf-core/rnaseq', 'GRCh38', 'hg19', 'DESeq2', '0.05', 'MAX_CPUS', ''])('skips %s', s => {
    expect(needsTranslation(s)).toBe(false);
  });
});

describe('translateLabels', () => {
  it('one batched call; maps every input; caches real translations', async () => {
    const llm = vi.fn(async () => JSON.stringify({ t: { 'Input Download': '读取输入数据', 'Run DESeq2 per contrast': '按对比运行 DESeq2' } }));
    const r1 = await translateLabels(['Input Download', 'Run DESeq2 per contrast', 'counts_matrix.csv', '差异丰度'], 'zh', llm as any, null);
    expect(r1).toEqual({ 'Input Download': '读取输入数据', 'Run DESeq2 per contrast': '按对比运行 DESeq2', 'counts_matrix.csv': 'counts_matrix.csv', '差异丰度': '差异丰度' });
    expect(llm).toHaveBeenCalledTimes(1);
    expect(JSON.parse((llm.mock.calls[0] as any)[0].messages[0].content)).toEqual(['Input Download', 'Run DESeq2 per contrast']);
    await translateLabels(['Input Download'], 'zh', llm as any, null);
    expect(llm).toHaveBeenCalledTimes(1); // cache hit
  });
  it('malformed / missing / other-English output falls back to the source and is retried later', async () => {
    const bad = vi.fn(async () => 'not json');
    expect(await translateLabels(['Normalisation'], 'zh', bad as any, null)).toEqual({ Normalisation: 'Normalisation' });
    const missing = vi.fn(async () => JSON.stringify({ t: {} }));
    expect(await translateLabels(['Normalisation'], 'zh', missing as any, null)).toEqual({ Normalisation: 'Normalisation' });
    const other = vi.fn(async () => JSON.stringify({ t: { Normalisation: 'Normalization step' } }));
    expect(await translateLabels(['Normalisation'], 'zh', other as any, null)).toEqual({ Normalisation: 'Normalisation' });
    const ok = vi.fn(async () => JSON.stringify({ t: { Normalisation: '数据标准化' } }));
    expect(await translateLabels(['Normalisation'], 'zh', ok as any, null)).toEqual({ Normalisation: '数据标准化' });
    expect(ok).toHaveBeenCalledTimes(1); // failures were not cached
  });
  it('a name the model deliberately keeps verbatim is cached (no re-ask every load)', async () => {
    const keep = vi.fn(async () => JSON.stringify({ t: { MultiQC: 'MultiQC' } }));
    expect(await translateLabels(['MultiQC'], 'zh', keep as any, null)).toEqual({ MultiQC: 'MultiQC' });
    await translateLabels(['MultiQC'], 'zh', keep as any, null);
    expect(keep).toHaveBeenCalledTimes(1);
  });
  it('llm throwing never throws to the caller', async () => {
    const boom = vi.fn(async () => { throw new Error('quota'); });
    expect(await translateLabels(['Visualisation & Report'], 'zh', boom as any, null)).toEqual({ 'Visualisation & Report': 'Visualisation & Report' });
  });
});

describe('translateLabels — single pass, no regex second-guessing of names', () => {
  it('one call per batch; a mixed output is accepted as returned (no repair re-ask)', async () => {
    const llm = vi.fn(async () => JSON.stringify({ t: { 'Fetch genotypes using fetch()': '使用 fetch() 获取基因型' } }));
    expect(await translateLabels(['Fetch genotypes using fetch()'], 'zh', llm as any, null)).toEqual({ 'Fetch genotypes using fetch()': '使用 fetch() 获取基因型' });
    expect(llm).toHaveBeenCalledTimes(1);
  });
});

describe('translateLabels — persistent store', () => {
  const mkStore = (seed: Record<string, string> = {}) => {
    const db = new Map(Object.entries(seed));
    return {
      db,
      get: vi.fn(async (_v: number, _l: string, srcs: string[]) => new Map(srcs.filter(s => db.has(s)).map(s => [s, db.get(s)!] as [string, string]))),
      put: vi.fn(async (_v: number, _l: string, entries: Array<[string, string]>) => { for (const [s, t] of entries) db.set(s, t); }),
    };
  };
  it('a stored translation is served without calling the LLM', async () => {
    const store = mkStore({ 'Input Download': '获取输入文件' });
    const llm = vi.fn();
    expect(await translateLabels(['Input Download'], 'zh', llm as any, store)).toEqual({ 'Input Download': '获取输入文件' });
    expect(llm).not.toHaveBeenCalled();
  });
  it('fresh translations are written back; failures are not', async () => {
    const store = mkStore();
    const llm = vi.fn(async () => JSON.stringify({ t: { Normalisation: '归一化' } }));
    await translateLabels(['Normalisation', 'Differential Abundance'], 'zh', llm as any, store);
    expect(store.put).toHaveBeenCalledTimes(1);
    expect([...store.db.entries()]).toEqual([['Normalisation', '归一化']]);
  });
  it('a store that throws degrades to memory-only (translation still returned)', async () => {
    const store = { get: vi.fn(async () => { throw new Error('db down'); }), put: vi.fn(async () => { throw new Error('db down'); }) };
    const llm = vi.fn(async () => JSON.stringify({ t: { Normalisation: '归一化' } }));
    expect(await translateLabels(['Normalisation'], 'zh', llm as any, store)).toEqual({ Normalisation: '归一化' });
  });
});
