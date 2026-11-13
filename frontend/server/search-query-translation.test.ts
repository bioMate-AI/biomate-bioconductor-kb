import { afterEach, describe, expect, it, vi } from 'vitest';
import { _resetSearchQueryCache, searchQueryForCatalog } from './search-query-translation';

afterEach(() => _resetSearchQueryCache());

describe('library search in Chinese (founder 2026-11-12: Chinese search returned nothing)', () => {
  it('a Chinese query becomes English catalog terms, once (cached)', async () => {
    const llm = vi.fn(async () => 'ADMET property prediction');
    expect(await searchQueryForCatalog('ADMET 性质预测', llm as any)).toEqual({ query: 'ADMET property prediction', translated: true });
    expect(await searchQueryForCatalog('ADMET 性质预测', llm as any)).toEqual({ query: 'ADMET property prediction', translated: true });
    expect(llm).toHaveBeenCalledTimes(1);
  });
  it('English queries are untouched; a failed or non-English answer falls back to the original', async () => {
    const llm = vi.fn(async () => { throw new Error('down'); });
    expect(await searchQueryForCatalog('rna-seq', llm as any)).toEqual({ query: 'rna-seq', translated: false });
    expect(llm).not.toHaveBeenCalled();
    expect(await searchQueryForCatalog('单细胞分析', llm as any)).toEqual({ query: '单细胞分析', translated: false });
    expect(await searchQueryForCatalog('单细胞分析', vi.fn(async () => '单细胞') as any)).toEqual({ query: '单细胞分析', translated: false });
  });
});
