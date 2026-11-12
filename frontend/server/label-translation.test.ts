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
    const r1 = await translateLabels(['Input Download', 'Run DESeq2 per contrast', 'counts_matrix.csv', '差异丰度'], 'zh', llm as any);
    expect(r1).toEqual({ 'Input Download': '读取输入数据', 'Run DESeq2 per contrast': '按对比运行 DESeq2', 'counts_matrix.csv': 'counts_matrix.csv', '差异丰度': '差异丰度' });
    expect(llm).toHaveBeenCalledTimes(1);
    expect(JSON.parse((llm.mock.calls[0] as any)[0].messages[0].content)).toEqual(['Input Download', 'Run DESeq2 per contrast']);
    await translateLabels(['Input Download'], 'zh', llm as any);
    expect(llm).toHaveBeenCalledTimes(1); // cache hit
  });
  it('malformed / missing / other-English output falls back to the source and is retried later', async () => {
    const bad = vi.fn(async () => 'not json');
    expect(await translateLabels(['Normalisation'], 'zh', bad as any)).toEqual({ Normalisation: 'Normalisation' });
    const missing = vi.fn(async () => JSON.stringify({ t: {} }));
    expect(await translateLabels(['Normalisation'], 'zh', missing as any)).toEqual({ Normalisation: 'Normalisation' });
    const other = vi.fn(async () => JSON.stringify({ t: { Normalisation: 'Normalization step' } }));
    expect(await translateLabels(['Normalisation'], 'zh', other as any)).toEqual({ Normalisation: 'Normalisation' });
    const ok = vi.fn(async () => JSON.stringify({ t: { Normalisation: '数据标准化' } }));
    expect(await translateLabels(['Normalisation'], 'zh', ok as any)).toEqual({ Normalisation: '数据标准化' });
    expect(ok).toHaveBeenCalledTimes(1); // failures were not cached
  });
  it('a name the model deliberately keeps verbatim is cached (no re-ask every load)', async () => {
    const keep = vi.fn(async () => JSON.stringify({ t: { MultiQC: 'MultiQC' } }));
    expect(await translateLabels(['MultiQC'], 'zh', keep as any)).toEqual({ MultiQC: 'MultiQC' });
    await translateLabels(['MultiQC'], 'zh', keep as any);
    expect(keep).toHaveBeenCalledTimes(1);
  });
  it('llm throwing never throws to the caller', async () => {
    const boom = vi.fn(async () => { throw new Error('quota'); });
    expect(await translateLabels(['Visualisation & Report'], 'zh', boom as any)).toEqual({ 'Visualisation & Report': 'Visualisation & Report' });
  });
});

describe('translateLabels — single pass, no regex second-guessing of names', () => {
  it('one call per batch; a mixed output is accepted as returned (no repair re-ask)', async () => {
    const llm = vi.fn(async () => JSON.stringify({ t: { 'Fetch genotypes using fetch()': '使用 fetch() 获取基因型' } }));
    expect(await translateLabels(['Fetch genotypes using fetch()'], 'zh', llm as any)).toEqual({ 'Fetch genotypes using fetch()': '使用 fetch() 获取基因型' });
    expect(llm).toHaveBeenCalledTimes(1);
  });
});
