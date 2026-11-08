import { describe, expect, it } from 'vitest';
import { topoOrderIntents, canonicalBranchDomain, dagPlanName } from './galaxy-assistant';

// Committee review 2026-11-05: a combining step listed before its branches lost its edges (numbered in
// emitted order, only earlier steps could be dependencies); branch domains outside the router's 14
// canonical values never earned the domain term; purely parallel plans were named after the last branch.
describe('topoOrderIntents', () => {
  it('orders a fan-in after its branches whatever order the classifier emitted', () => {
    const out = topoOrderIntents([
      { id: 'join', dependsOn: ['a', 'b'] }, { id: 'a' }, { id: 'b', dependsOn: [] },
    ]);
    expect(out!.map(i => i.id)).toEqual(['a', 'b', 'join']);
  });
  it('ignores unknown and self dependencies, rejects cycles', () => {
    expect(topoOrderIntents([{ id: 'a', dependsOn: ['a', 'zzz'] }, { id: 'b', dependsOn: ['a'] }])!.map(i => i.id)).toEqual(['a', 'b']);
    expect(topoOrderIntents([{ id: 'a', dependsOn: ['b'] }, { id: 'b', dependsOn: ['a'] }])).toBeNull();
  });
});

describe('canonicalBranchDomain', () => {
  it('keeps canonical domains, maps aliases, drops what the router cannot use', () => {
    expect(canonicalBranchDomain('proteomics')).toBe('proteomics');
    expect(canonicalBranchDomain('variant_calling')).toBe('genomics');
    expect(canonicalBranchDomain('pharmacology')).toBe('drug_discovery');
    expect(canonicalBranchDomain('imaging')).toBe('bioimaging');
    expect(canonicalBranchDomain('methylation')).toBe('epigenomics');
    expect(canonicalBranchDomain('immunology')).toBeUndefined();
    expect(canonicalBranchDomain(undefined)).toBeUndefined();
  });
});

describe('dagPlanName', () => {
  it('does not name a purely parallel plan after its last branch', () => {
    expect(dagPlanName([{ description: 'germline variant calling on WGS', depends_on: [] },
      { description: 'RNA-seq DE', depends_on: [] }])).toBe('2 parallel analyses');
  });
});
