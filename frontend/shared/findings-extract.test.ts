import { describe, it, expect } from 'vitest';
import { buildFindingsDocument } from './findings-extract';
import { matchDescriptor, DESCRIPTORS } from './findings-descriptors';

const CAFFEINE = 'Cn1c(=O)c2c(ncn2C)n(C)c1=O';

// ADMET per-compound kv-block output (mirrors the live dev run: caffeine DILI 0.875).
const ADMET_FILE = {
  name: 'admet_results.txt',
  content: [
    `Drug: ${CAFFEINE}`,
    '  hERG inhibition: 0.115',
    '  DILI probability: 0.875',
    '  Oral bioavailability: 0.936',
    '  Caco-2 logPapp: > 1.2',          // censored value
    'Drug: CN(C)C(=N)NC(=N)N',           // metformin
    '  hERG inhibition: 0.08',
    '  DILI probability: 0.21',
    '  Oral bioavailability: 0.78',
    'Drug: NC(=O)c1cccnc1',              // nicotinamide
    '  hERG inhibition: 0.05',
    '  DILI probability: 0.11',
    '  Oral bioavailability: 0.90',
  ].join('\n'),
};

describe('buildFindingsDocument — ADMET (kvBlocks, compound entity)', () => {
  const m = matchDescriptor('Predict ADMET Properties (AI)', [ADMET_FILE]);
  it('matches the ADMET descriptor by content', () => {
    expect(m?.descriptor.id).toBe('admet');
  });
  const doc = buildFindingsDocument(m!.descriptor, m!.file);

  it('is ready and rosters all 3 compounds', () => {
    expect(doc.status).toBe('ready');
    expect(doc.entityRoster).toHaveLength(3);
  });

  it('attributes each result to a real SMILES entity (not Compound N)', () => {
    const r = doc.records.find(r => r.entity.label === CAFFEINE && r.metric.name === 'DILI probability')!;
    expect(r.entity.type).toBe('compound');
    expect(r.entity.scope).toBe('per_entity');
    expect(r.entity.identifier).toEqual({ scheme: 'SMILES', value: CAFFEINE });
    expect(r.entity.identitySource).toBe('output_column');
  });

  it('flags the DILI liability with its threshold, passes hERG/oral-bioavail', () => {
    const dili = doc.records.find(r => r.entity.label === CAFFEINE && r.metric.name === 'DILI probability')!;
    expect(dili.metric.value).toBe('0.875');
    expect(dili.assessment?.flag).toBe('liability');
    expect(dili.assessment?.threshold).toEqual({ value: 0.5, direction: 'high_bad' });

    const herg = doc.records.find(r => r.entity.label === CAFFEINE && r.metric.name === 'hERG inhibition')!;
    expect(herg.assessment?.flag).toBe('pass');
    const oral = doc.records.find(r => r.entity.label === CAFFEINE && r.metric.name === 'Oral bioavailability')!;
    expect(oral.assessment?.flag).toBe('pass'); // 0.936 >= 0.5 low_bad → acceptable
  });

  it('preserves a censored inequality (never coerced)', () => {
    const caco = doc.records.find(r => r.entity.label === CAFFEINE && r.metric.name === 'Caco-2 logPapp')!;
    expect(caco.metric.comparator).toBe('>');
    expect(caco.metric.value).toBe('> 1.2');
  });

  it('cites provenance once, referenced by every record', () => {
    expect(Object.keys(doc.provenance)).toHaveLength(1);
    expect(doc.provenance.p0.source.file).toBe('admet_results.txt');
    expect(doc.provenance.p0.evidenceClass).toBe('Table');
    expect(doc.records.every(r => r.provenanceRef === 'p0')).toBe(true);
  });

  it('summary names the DILI liability', () => {
    expect(doc.summary).toMatch(/DILI probability/);
  });
});

// DESeq2 differential-expression CSV (gene entity, significance = selection not verdict).
const DESEQ2_FILE = {
  name: 'deseq2_results.csv',
  content: [
    'gene,log2FoldChange,padj',
    'TP53,2.5,0.001',
    'MYC,-1.8,0.02',
    'ACTB,0.1,0.8',      // not significant → excluded
    'BRCA1,3.1,0.0001',
  ].join('\n'),
};

describe('buildFindingsDocument — DESeq2 (csv, gene entity)', () => {
  const m = matchDescriptor('nf-core/differentialabundance', [DESEQ2_FILE]);
  const doc = buildFindingsDocument(m!.descriptor, m!.file);

  it('matches deseq2 and selects only significant genes, top by |lfc|', () => {
    expect(m?.descriptor.id).toBe('deseq2');
    expect(doc.entityRoster.map(e => e.label)).toEqual(['BRCA1', 'TP53', 'MYC']); // ACTB excluded; sorted by |lfc|
  });

  it('emits gene-typed records with no misleading liability verdict', () => {
    const brca = doc.records.find(r => r.entity.label === 'BRCA1' && r.metric.name === 'log2FoldChange')!;
    expect(brca.entity.type).toBe('gene');
    expect(brca.metric.value).toBe('3.1');
    // a significant gene is a hit, not a "liability"
    expect(doc.records.some(r => r.assessment?.flag === 'liability')).toBe(false);
  });
});

it('registry exposes both ported descriptors', () => {
  expect(DESCRIPTORS.map(d => d.id).sort()).toEqual(['admet', 'deseq2']);
});
