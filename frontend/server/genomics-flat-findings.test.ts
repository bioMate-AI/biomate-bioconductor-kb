import { describe, expect, it } from 'vitest';
import {
  parseDeseq2Findings,
  parseEnrichGoFindings,
  parseRarediseaseFindings,
} from './genomics-flat-findings';

const DESEQ2_TSV = {
  name: 'de_results.tsv',
  content: [
    'gene\tlog2FoldChange\tpadj',
    'TP53\t2.10\t0.001',
    'MYC\t-1.50\t0.02',
    'GAPDH\t0.10\t0.40',
  ].join('\n'),
};

const ENRICH_TSV = {
  name: 'enrichgo_BP.tsv',
  content: [
    'Description\tp.adjust\tGeneRatio\tCount',
    'apoptotic process\t0.0001\t10/200\t10',
    'cell cycle\t0.03\t8/200\t8',
    'noise term\t0.20\t2/200\t2',
  ].join('\n'),
};

const VARIANT_TSV = {
  name: 'annotated_variants.tsv',
  content: [
    'SYMBOL\tIMPACT\tConsequence',
    'BRCA1\tHIGH\tstop_gained',
    'TTN\tMODERATE\tmissense_variant',
    'OR4F5\tMODIFIER\tupstream_gene_variant',
  ].join('\n'),
};

describe('parseDeseq2Findings (flat belt)', () => {
  it('emits score-first Key Results with deseq2-flat-v1', () => {
    const r = parseDeseq2Findings([DESEQ2_TSV]);
    expect(r).not.toBeNull();
    expect(r!.findings.evidence_version).toBe('deseq2-flat-v1');
    expect(r!.findings.summary).toMatch(/2 genes at padj/);
    expect(r!.findings.key_results[0].metric).toMatch(/Significant genes/);
    expect(r!.findings.key_results[0].value).toBe('2');
    const entities = r!.findings.key_results.map((k: any) => k.entity).filter(Boolean);
    expect(entities).toEqual(expect.arrayContaining(['TP53', 'MYC']));
  });

  it('returns null when no DE columns', () => {
    expect(parseDeseq2Findings([{ name: 'notes.txt', content: 'hello' }])).toBeNull();
  });
});

describe('parseEnrichGoFindings (flat belt)', () => {
  it('parses TSV enrichment (autodelim) with enrichgo-flat-v1', () => {
    const r = parseEnrichGoFindings([ENRICH_TSV]);
    expect(r).not.toBeNull();
    expect(r!.findings.evidence_version).toBe('enrichgo-flat-v1');
    expect(r!.findings.key_results[0].value).toBe('2');
    expect(r!.findings.summary).toMatch(/apoptotic process/);
  });
});

describe('parseRarediseaseFindings (flat belt)', () => {
  it('counts HIGH vs MODIFIER correctly (no /mod/ substring leak)', () => {
    const r = parseRarediseaseFindings([VARIANT_TSV]);
    expect(r).not.toBeNull();
    expect(r!.findings.evidence_version).toBe('raredisease-flat-v1');
    const byMetric = Object.fromEntries(
      r!.findings.key_results
        .filter((k: any) => k.metric.includes('impact') || k.metric.includes('IMPACT') || k.metric.includes('HIGH') || k.metric.includes('MODERATE') || k.metric.includes('Variants'))
        .map((k: any) => [k.metric, k.value]),
    );
    expect(byMetric['HIGH impact (sampled)']).toBe('1');
    expect(byMetric['MODERATE impact (sampled)']).toBe('1');
    expect(byMetric['Variants in sampled output']).toBe('3');
    expect(r!.findings.summary).toMatch(/BRCA1/);
  });
});
