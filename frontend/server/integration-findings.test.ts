import { describe, it, expect } from 'vitest';
import { integrationFindings, integrationFindingsMarkdown } from './integration-findings';
const table = 'Embedding\tSilhouette label\tcLISI\tBatch correction\tBio conservation\tTotal\nX_emb\t0.5\t\t0.7360086713642043\t0.5\t0.5944034685456817\nMetric Type\tBio conservation\tBio conservation\tAggregate score\tAggregate score\tAggregate score\n';
describe('integration metric column provenance', () => {
  it('keeps biological conservation separate from the total, including an empty middle cell', () => {
    const data = integrationFindings([{name:'combat_metrics.tsv',content:table}])!;
    expect(data.key_results.find(r=>r.metric.endsWith(' · Bio conservation'))?.value).toBe('0.5');
    expect(data.key_results.find(r=>r.metric.endsWith(' · Total'))?.value).toBe('0.5944034685456817');
    expect(data.key_results.find(r=>r.metric.endsWith(' · cLISI'))?.value).toBe('Not reported');
    expect(data.summary).toContain('Bio conservation: 0.5');
    expect(data.key_results).toHaveLength(5);
    expect(integrationFindingsMarkdown(data,'Integration')).toContain('Bio conservation | 0.5 | combat_metrics.tsv');
  });
  it('uses headers after reorder, preserves methods and embeddings, excludes metadata', () => {
    const data = integrationFindings([{name:'scvi_metrics.tsv',content:'Embedding\tTotal\tBio conservation\tBatch correction\nX1\t0.8\t0.6\t0.7\nX2\t0.4\t0.2\t0.3'}, {name:'combat_metrics.tsv',content:table}])!;
    expect(data.key_results.find(r=>r.metric==='scvi · X2 · Bio conservation')?.value).toBe('0.2');
    expect(data.key_results.some(r=>r.metric.includes('Metric Type'))).toBe(false);
    expect(data.summary).toContain('2 methods');
  });
  it('does not reinterpret unrelated or malformed tables', () => {
    expect(integrationFindings([{name:'metrics.tsv', content:'Total\tValue\n5\t2'}])).toBeNull();
    expect(integrationFindings([{name:'combat_metrics.tsv',content:table.split('\n')[0]+'\nX\tbroken'}])).toBeNull();
  });
});

it('retains verified cell totals and source identity, rejecting inconsistent aggregates',()=>{
 const findings=integrationFindings([{name:'combat_metrics.tsv',content:table},{name:'sizes.tsv',content:'state\tsample_a\tsample_b\ttotal\nthresholded\t355\t373\t728\nwrong\t1\t2\t99'}])!;
 expect(findings.summary).toContain('728 cells');
 expect(findings.key_results.find(r=>r.metric==='thresholded cells · total')).toMatchObject({value:'728',source_file:'sizes.tsv'});
 expect(findings.key_results.some(r=>r.metric.startsWith('wrong'))).toBe(false);
});

it('withholds the entire result when one method table cannot be validated',()=>{
 expect(integrationFindings([{name:'combat_metrics.tsv',content:table},{name:'scvi_metrics.tsv',content:'wrong\theader\n1\t2'}])).toBeNull();
 expect(integrationFindings([{name:'combat_metrics.tsv',content:table},{name:'scvi_metrics.tsv',content:table.split('\n')[0]+'\n'}])).toBeNull();
});
