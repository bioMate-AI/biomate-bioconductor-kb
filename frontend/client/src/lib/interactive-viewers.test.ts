import { describe, it, expect } from 'vitest';
import { recommendViewers, VIEWER_TOOL_ID } from './interactive-viewers';

describe('recommendViewers — auto-select interactive viewer by dataset format', () => {
  it('h5ad → CellxGene primary, iSEE + generic as alternatives', () => {
    const r = recommendViewers('h5ad');
    expect(r.primary).toBe('cellxgene');
    expect(r.alternatives).toContain('isee');
    expect(r.alternatives).toContain('jupyter'); // escape-hatch always offered
  });

  it('vcf / vcf_bgzip → vcf.iobio', () => {
    expect(recommendViewers('vcf').primary).toBe('vcf_iobio');
    expect(recommendViewers('VCF_BGZIP').primary).toBe('vcf_iobio'); // case-insensitive
  });

  it('bam → bam.iobio', () => {
    expect(recommendViewers('bam').primary).toBe('bam_iobio');
  });

  it('cool/bigwig → HiGlass', () => {
    expect(recommendViewers('mcool').primary).toBe('higlass');
    expect(recommendViewers('bigwig').primary).toBe('higlass');
  });

  it('rds/rdata → iSEE primary, RStudio alternative', () => {
    expect(recommendViewers('rds').primary).toBe('isee');
    expect(recommendViewers('rdata').alternatives).toContain('rstudio');
  });

  it('unknown format → Jupyter primary, RStudio alternative (universal escape-hatch)', () => {
    const r = recommendViewers('someBinaryThing');
    expect(r.primary).toBe('jupyter');
    expect(r.alternatives).toContain('rstudio');
  });

  it('plain tabular → generic primary, Pavian offered as an alternative (report is ambiguous)', () => {
    const r = recommendViewers('tabular');
    expect(r.primary).toBe('jupyter');
    expect(r.alternatives).toContain('pavian');
  });

  it('empty/undefined format defaults to Jupyter', () => {
    expect(recommendViewers(undefined).primary).toBe('jupyter');
    expect(recommendViewers('').primary).toBe('jupyter');
  });

  it('every viewer key maps to a real interactive_tool_ id', () => {
    for (const id of Object.values(VIEWER_TOOL_ID)) {
      expect(id).toMatch(/^interactive_tool_/);
    }
  });
});
