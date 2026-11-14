import { describe, it, expect } from 'vitest';
import {
  buildFindingsDocument,
  documentToLegacy,
  documentLiabilities,
  flatLiabilities,
  reconcileFindingsDocument,
} from './findings-extract';
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

  // autodelim must detect the delimiter from the HEADER line, not the whole body: a stray tab inside
  // a CSV data cell must NOT flip the delimiter to '\t' and shatter the comma file into 1 col/line.
  it('autodelim: a comma CSV with a stray tab in a data cell still parses (not 0 results)', () => {
    const CSV_WITH_TAB = {
      name: 'deseq2_results.csv',
      content: ['gene,log2FoldChange,padj', 'TP53,2.5\t,0.001', 'BRCA1,3.1,0.0001'].join('\n'),
    };
    const mm = matchDescriptor('nf-core/differentialabundance', [CSV_WITH_TAB]);
    const d = buildFindingsDocument(mm!.descriptor, mm!.file);
    expect(d.entityRoster.map(e => e.label).sort()).toEqual(['BRCA1', 'TP53']);
    expect(d.records.find(r => r.entity.label === 'BRCA1' && r.metric.name === 'padj')?.metric.value).toBe('0.0001');
  });

  // and a real TSV (BioMate's de_results.tsv) still detects tab and parses.
  it('autodelim: a TSV header is detected as tab-delimited', () => {
    const TSV = {
      name: 'de_results.tsv',
      content: ['gene_id\tlog2FoldChange\tpadj', 'ENSG1\t2.1\t0.001', 'ENSG2\t-3.0\t0.0002'].join('\n'),
    };
    const mm = matchDescriptor('nf-core/differentialabundance', [TSV]);
    const d = buildFindingsDocument(mm!.descriptor, mm!.file);
    expect(d.entityRoster.map(e => e.label).sort()).toEqual(['ENSG1', 'ENSG2']);
  });
});

it('registry exposes domain descriptors (ADMET + omics + docking + structure)', () => {
  expect(DESCRIPTORS.map(d => d.id).sort()).toEqual([
    'admet', 'admet_report', 'boltz_qc', 'boltz_summary', 'deseq2', 'enrichgo', 'variant', 'vina_docking',
  ]);
});

const VINA_FILE = {
  name: 'docking_autodock_vina_results.json',
  content: JSON.stringify({
    success: true,
    function: 'docking_autodock_vina',
    results: [
      { smiles: 'CCO', best_affinity_kcal_mol: -4.2, n_poses: 9 },
      { smiles: 'CCN', best_affinity_kcal_mol: -6.1, n_poses: 9 },
      { smiles: 'CCC', best_affinity_kcal_mol: -5.0, n_poses: 5 },
    ],
  }),
};

describe('buildFindingsDocument — Vina docking', () => {
  const m = matchDescriptor('AutoDock Vina Docking', [VINA_FILE]);
  const doc = buildFindingsDocument(m!.descriptor, m!.file);

  it('matches vina_docking and ranks by affinity (most negative first)', () => {
    expect(m?.descriptor.id).toBe('vina_docking');
    expect(doc.entityRoster.map(e => e.label)).toEqual(['CCN', 'CCC', 'CCO']);
  });

  it('summary leads with best affinity and points at Key Results', () => {
    expect(doc.summary).toMatch(/Best affinity -6\.1/);
    expect(doc.summary).toMatch(/Key Results/);
    const leg = documentToLegacy(doc);
    expect(leg.key_results[0].metric).toBe('best affinity');
    expect(leg.key_results[0].value).toMatch(/-6\.1/);
  });
});

const BOLTZ_QC_FILE = {
  name: 'qc_metrics.json',
  content: JSON.stringify({
    mean_plddt: 82.4,
    confident_fraction: 0.81,
    max_pae: 6.2,
    structures_predicted: 1,
    tool: 'Boltz-2',
  }),
};

describe('buildFindingsDocument — Boltz qc_metrics', () => {
  const m = matchDescriptor('boltz_structure_prediction', [BOLTZ_QC_FILE]);
  const doc = buildFindingsDocument(m!.descriptor, m!.file);

  it('surfaces mean pLDDT as batch Key Results (not hollow LLM prose)', () => {
    expect(m?.descriptor.id).toBe('boltz_qc');
    const leg = documentToLegacy(doc);
    expect(leg.key_results.map(k => k.metric)).toEqual(
      expect.arrayContaining(['mean pLDDT', 'confident fraction', 'max PAE', 'structures predicted']),
    );
    expect(doc.summary).toMatch(/mean pLDDT=82/);
    expect(doc.summary).toMatch(/pLDDT gate pass/);
  });
});

describe('buildFindingsDocument — DESeq2 summary names top genes', () => {
  it('leads with padj counts and top hits (not generic Assessment completed)', () => {
    const m = matchDescriptor('nf-core/differentialabundance', [DESEQ2_FILE]);
    const doc = buildFindingsDocument(m!.descriptor, m!.file);
    expect(doc.summary).toMatch(/DESeq2: 3 genes at padj/);
    expect(doc.summary).toMatch(/BRCA1/);
    expect(doc.summary).not.toMatch(/^Assessment completed/);
  });
});

// ADMET structured JSON report: per_compound[] (per-entity) + toxicity{} (batch) — the real
// toxicity_report.json shape, including the batch hERG IC50 that belongs to no compound.
const ADMET_JSON = {
  name: 'toxicity_report.json',
  content: JSON.stringify({
    per_compound: [
      { smiles: 'CC(=O)Oc1ccccc1C(=O)O', dili_probability: 0.855, herg_ic50_uM: 52.725, dili_risk: 'high', logP: 1.31, mw: 180.2 },
      { smiles: 'CN1C=NC2=C1C(=O)N(C(=O)N2C)C', dili_probability: 0.875, herg_ic50_uM: 6633.041, dili_risk: 'high' },
      { smiles: 'CC(C)Cc1ccc(C(C)C(=O)O)cc1', dili_probability: 0.487, herg_ic50_uM: 5.227, dili_risk: 'medium' },
    ],
    toxicity: { herg_ic50_uM: 432.4246, dili_probability: 0.875, ames_probability: 0.1 },
  }),
};

describe('buildFindingsDocument — ADMET structured report (jsonReport + batch)', () => {
  const m = matchDescriptor('Predict ADMET Properties (AI)', [ADMET_JSON]);
  const doc = buildFindingsDocument(m!.descriptor, m!.file);

  it('matches the JSON report descriptor and reads per-compound entities', () => {
    expect(m?.descriptor.id).toBe('admet_report');
    expect(doc.entityRoster).toHaveLength(3);
  });

  it('flags aspirin DILI liability, passes ibuprofen (0.487 < 0.5), with SMILES identity', () => {
    const asp = doc.records.find(r => r.entity.label === 'CC(=O)Oc1ccccc1C(=O)O' && r.metric.name === 'DILI probability')!;
    expect(asp.assessment?.flag).toBe('liability');
    expect(asp.entity.identifier?.scheme).toBe('SMILES');
    const ibu = doc.records.find(r => r.entity.label === 'CC(C)Cc1ccc(C(C)C(=O)O)cc1' && r.metric.name === 'DILI probability')!;
    expect(ibu.assessment?.flag).toBe('pass');
  });

  it('attaches units to hERG IC50 (never a bare number)', () => {
    const herg = doc.records.find(r => r.entity.label === 'CC(=O)Oc1ccccc1C(=O)O' && r.metric.name === 'hERG IC50')!;
    expect(herg.metric.units).toBe('µM');
    expect(herg.metric.value).toBe('52.725');
  });

  it('carries the batch hERG IC50 as scope:batch (belongs to no named compound)', () => {
    const batchHerg = doc.records.find(r => r.entity.scope === 'batch' && r.metric.name === 'hERG IC50 (panel)')!;
    expect(batchHerg).toBeTruthy();
    expect(batchHerg.metric.value).toBe('432.4246');
    expect(batchHerg.metric.units).toBe('µM');
    expect(batchHerg.entity.label).toBe('panel');
  });

  it('applies the categorical DILI-risk verdict (high→liability, medium→neutral)', () => {
    const aspRisk = doc.records.find(r => r.entity.label === 'CC(=O)Oc1ccccc1C(=O)O' && r.metric.name === 'DILI risk')!;
    expect(aspRisk.assessment?.flag).toBe('liability');
    const ibuRisk = doc.records.find(r => r.entity.label === 'CC(C)Cc1ccc(C(C)C(=O)O)cc1' && r.metric.name === 'DILI risk')!;
    expect(ibuRisk.assessment?.flag).toBe('neutral');
  });

  it('uses the Report evidence class', () => {
    expect(doc.provenance.p0.evidenceClass).toBe('Report');
  });
});

// ── Dual-summary contradiction regression (BUG 2) ──────────────────────────────
// Real toxicity_report.json shape: the ADMET-AI probabilities live in
// `per_compound_admet_ai` (hERG_prob, DILI_prob, cyp2d6_inhibitor_prob) while the RDKit
// heuristics live in `per_compound` (herg_ic50_uM, logP, mw, dili_risk). Before the fix the
// descriptor read only `per_compound` — blind to hERG/CYP2D6 — so buildFindingsDocument said
// "No major liabilities flagged." while the flat _parseAdmetOutput path flagged hERG + CYP2D6.
// Terfenadine: hERG_prob 0.977 (liability), cyp2d6_inhibitor_prob 0.861 (liability),
// DILI_prob 0.041 (low, pass).
const TERFENADINE = 'CC(C)(C)c1ccc(cc1)C(O)CCCN1CCC(CC1)C(O)(c1ccccc1)c1ccccc1';
const ADMET_AI_JSON = {
  name: 'toxicity_report.json',
  content: JSON.stringify({
    per_compound_admet_ai: [
      {
        smiles: TERFENADINE,
        hERG_prob: 0.977,
        DILI_prob: 0.041,
        cyp2d6_inhibitor_prob: 0.861,
        oral_bioavailability_prob: 0.72,
        clintox_prob: 0.12,
        cyp3a4_substrate_prob: 0.55,
        bbb_prob: 0.60,
        ppbr_pct: 98.2,
        caco2_logPapp: 1.4,
      },
    ],
    per_compound: [
      { smiles: TERFENADINE, dili_probability: 0.041, herg_ic50_uM: 0.01, dili_risk: 'low', logP: 5.8, mw: 471.7 },
    ],
    toxicity: { herg_ic50_uM: 0.01, dili_probability: 0.041, ames_probability: 0.1 },
  }),
};

// The flat findings object exactly as _parseAdmetOutput (routes.ts) emits it for the same run.
const TERFENADINE_FLAT = {
  summary: 'ADMET prediction completed for 1 compound. Potential liabilities flagged: hERG inhibition, CYP2D6 inhibitor.',
  key_results: [
    { metric: 'hERG inhibition',  value: '0.977', interpretation: 'Elevated hERG (cardiac) liability risk (0.977) — potential liability', source_file: 'toxicity_report.json' },
    { metric: 'DILI probability', value: '0.041', interpretation: 'Acceptable drug-induced liver injury risk (0.041)', source_file: 'toxicity_report.json' },
    { metric: 'CYP2D6 inhibitor', value: '0.861', interpretation: 'Elevated CYP2D6 inhibitor risk (0.861) — potential liability', source_file: 'toxicity_report.json' },
  ],
};

describe('BUG 2 — ADMET findings_document agrees with the flat verdict (no dual-summary contradiction)', () => {
  const m = matchDescriptor('Predict ADMET Properties (AI)', [ADMET_AI_JSON]);
  const doc = buildFindingsDocument(m!.descriptor, m!.file);

  it('matches the JSON report descriptor and reads the single merged compound', () => {
    expect(m?.descriptor.id).toBe('admet_report');
    expect(doc.entityRoster).toHaveLength(1);
  });

  it('flags hERG (0.977) and CYP2D6 (0.861), passes DILI (0.041)', () => {
    const herg = doc.records.find(r => r.metric.name === 'hERG inhibition')!;
    expect(herg.metric.value).toBe('0.977');
    expect(herg.assessment?.flag).toBe('liability');
    const cyp = doc.records.find(r => r.metric.name === 'CYP2D6 inhibitor')!;
    expect(cyp.metric.value).toBe('0.861');
    expect(cyp.assessment?.flag).toBe('liability');
    const dili = doc.records.find(r => r.metric.name === 'DILI probability')!;
    expect(dili.metric.value).toBe('0.041');
    expect(dili.assessment?.flag).toBe('pass');
  });

  it('merges per_compound heuristics alongside the AI probabilities (no data lost)', () => {
    // logP/mw come from per_compound, hERG_prob from per_compound_admet_ai — same compound.
    expect(doc.records.find(r => r.metric.name === 'logP')?.metric.value).toBe('5.8');
    expect(doc.records.find(r => r.metric.name === 'MW')?.metric.value).toBe('471.7');
  });

  it('document summary flags hERG + CYP2D6 and NEVER says "no liabilities"', () => {
    expect(doc.summary).toMatch(/hERG inhibition/);
    expect(doc.summary).toMatch(/CYP2D6 inhibitor/);
    expect(doc.summary).not.toMatch(/No major liabilities/i);
  });

  it('the two verdicts AGREE — same liability set, reconciliation is a no-op', () => {
    const docSet = documentLiabilities(doc);
    const flatSet = flatLiabilities(TERFENADINE_FLAT);
    expect([...docSet].sort()).toEqual(['CYP2D6 inhibitor', 'hERG inhibition']);
    expect([...flatSet].sort()).toEqual(['CYP2D6 inhibitor', 'hERG inhibition']);
    // sets equal → reconcile returns the document unchanged (no deferral, no extra caveat)
    const reconciled = reconcileFindingsDocument(TERFENADINE_FLAT, doc);
    expect(reconciled.summary).toBe(doc.summary);
    expect(reconciled.caveats).toEqual(doc.caveats);
  });
});

// Regression — multi-file descriptor selection (document-as-truth shadow, 2026-11-05). A real ADMET
// run emits SEVEN output files; the structured report is toxicity_report.json but a sibling
// pk_summary.json ALSO carries a `per_compound` array (RDKit logP/mw) and a `*_results.json` wrapper
// matches the loose `admet.*\.json` name regex with no arrays at all. matchDescriptor used to return
// the FIRST file that hit on ANY signal, so pk_summary (content-matched `per_compound`, earlier in
// the list) won → the ADMET document collapsed to a single logP and lost every liability.
describe('matchDescriptor — picks the structured report out of a multi-file ADMET run', () => {
  const PK_SUMMARY = {
    name: 'pk_summary.json',
    content: JSON.stringify({ logP: 6.4, mw_Da: 471.7, ppbr_pct: 98.5, per_compound: [{ smiles: TERFENADINE, logP: 6.4, mw_Da: 471.7, descriptor_source: 'rdkit' }] }),
  };
  const RESULTS_WRAPPER = {
    name: 'predict_admet_properties_results.json',
    content: JSON.stringify({ success: true, function: 'predict_admet_properties', domain: 'pharmacology', result: 'ADMET-AI Predictions ...text dump...' }),
  };
  // Output order as the run lists them: pk_summary first, wrapper second, toxicity_report last.
  const FILES = [PK_SUMMARY, RESULTS_WRAPPER, ADMET_AI_JSON];

  it('chooses toxicity_report.json (per_compound_admet_ai) over pk_summary.json and the results wrapper', () => {
    const m = matchDescriptor('Predict ADMET Properties (AI)', FILES);
    expect(m?.descriptor.id).toBe('admet_report');
    expect(m?.file.name).toBe('toxicity_report.json');
  });

  it('projects all ADMET-AI metrics (hERG/DILI/CYP2D6), not just logP', () => {
    const m = matchDescriptor('Predict ADMET Properties (AI)', FILES);
    const leg = documentToLegacy(buildFindingsDocument(m!.descriptor, m!.file));
    const metrics = new Set(leg.key_results.map(k => k.metric));
    expect(metrics.has('hERG inhibition')).toBe(true);
    expect(metrics.has('DILI probability')).toBe(true);
    expect(metrics.has('CYP2D6 inhibitor')).toBe(true);
    expect(leg.key_results.length).toBeGreaterThan(1); // not the degenerate logP-only projection
  });

  it('does NOT match the PK summary alone (generic per_compound is not the toxicity marker)', () => {
    // pk_summary carries `per_compound` but no `per_compound_admet_ai` and no ADMET/toxicity name →
    // it must not be mistaken for the toxicity report when it is the only ADMET-ish file present.
    const m = matchDescriptor('Predict ADMET Properties (AI)', [PK_SUMMARY, RESULTS_WRAPPER]);
    // Assert a concrete winner (the name-matching wrapper), not just "not pk_summary" — a bare
    // .not.toBe would also pass if no descriptor matched (m === null), masking a regression.
    expect(m).not.toBeNull();
    expect(m?.file.name).toBe('predict_admet_properties_results.json');
    expect(m?.file.name).not.toBe('pk_summary.json');
  });
});

describe('reconcileFindingsDocument — safeguard fires on a genuine mismatch', () => {
  const m = matchDescriptor('Predict ADMET Properties (AI)', [ADMET_AI_JSON]);
  const doc = buildFindingsDocument(m!.descriptor, m!.file); // flags hERG + CYP2D6

  it('keeps the document as primary when the flat has NO deterministic liability signal (audit S3#1)', () => {
    // An LLM-generated flat ("no liabilities", no "potential liability" marker) → flatSet empty.
    // Empty flatSet vs non-empty docSet is NOT a genuine disagreement; the document is the
    // reliable source and its correct summary must be preserved — NOT overwritten with the flat's
    // "no liabilities" text (which previously re-created the #4 dual-verdict contradiction).
    const flatSaysNothing = { summary: 'ADMET prediction completed for 1 compound. No major liabilities flagged.', key_results: [] };
    const logged: string[] = [];
    const reconciled = reconcileFindingsDocument(flatSaysNothing, doc, (m2) => logged.push(m2));
    expect(reconciled.summary).toBe(doc.summary);                 // document summary PRESERVED
    expect(reconciled.summary).toMatch(/hERG inhibition/);        // still flags the real liabilities
    expect(reconciled.caveats).toEqual(doc.caveats);              // no reconcile caveat added
    expect(logged.length).toBe(0);                                // nothing logged (early return)
  });

  it('still defers to the flat when a DETERMINISTIC flat liability signal genuinely disagrees', () => {
    // Deterministic flat (carries the "potential liability" marker) flags a different set → a real
    // disagreement → the defer-to-flat safeguard still fires.
    const flatDet = { summary: 'ADMET: AMES liability only.', key_results: [{ metric: 'AMES mutagenicity', interpretation: 'positive — potential liability' }] };
    const logged: string[] = [];
    const reconciled = reconcileFindingsDocument(flatDet, doc, (m2) => logged.push(m2));
    expect(reconciled.summary).toBe(flatDet.summary);
    expect(reconciled.caveats.some(c => /reconciled/i.test(c))).toBe(true);
    expect(logged.some(l => /mismatch/i.test(l))).toBe(true);
  });

  it('is a no-op when neither path produced a liability signal', () => {
    const cleanDoc = { ...doc, records: doc.records.filter(r => r.assessment?.flag !== 'liability') };
    const out = reconcileFindingsDocument({ summary: 'clean', key_results: [] }, cleanDoc);
    expect(out).toBe(cleanDoc);
  });

  it('committee Opus-2: a CLEAN deterministic flat (empty liability set) is NOT overridden by a document false-positive', () => {
    // Deterministic parser genuinely found zero liabilities (flatSet empty), but the entity document
    // flags one. With flatIsDeterministic=true the empty-flatSet early return must NOT fire (that would
    // silently trust the document over the clean primary verdict); instead defer to the clean flat + log.
    const flatClean = { summary: 'ADMET prediction completed. No liabilities flagged.', key_results: [] };
    const logged: string[] = [];
    const reconciled = reconcileFindingsDocument(flatClean, doc, (m2) => logged.push(m2), /* flatIsDeterministic */ true);
    expect(reconciled.summary).toBe(flatClean.summary);              // deferred to the clean deterministic flat
    expect(reconciled.caveats.some(c => /reconciled/i.test(c))).toBe(true);
    expect(logged.some(l => /mismatch/i.test(l))).toBe(true);        // the disagreement IS logged
  });

  it('an LLM flat (not deterministic) with empty liability set keeps the document (unchanged S3#1 behavior)', () => {
    const flatLLM = { summary: 'No liabilities flagged.', key_results: [] };
    const logged: string[] = [];
    const reconciled = reconcileFindingsDocument(flatLLM, doc, (m2) => logged.push(m2) /* flatIsDeterministic defaults false */);
    expect(reconciled.summary).toBe(doc.summary);                    // document primary for LLM flat
    expect(logged.length).toBe(0);
  });
});

describe('buildFindingsDocument — variant (categorical IMPACT verdict, autodelim)', () => {
  const VCF_TSV = {
    name: 'annotated_variants.tsv',
    content: ['gene\tIMPACT\tConsequence', 'TP53\tHIGH\tstop_gained', 'BRCA2\tMODERATE\tmissense_variant', 'EGFR\tLOW\tsynonymous_variant'].join('\n'),
  };
  const m = matchDescriptor('nf-core/raredisease', [VCF_TSV]);
  const doc = buildFindingsDocument(m!.descriptor, m!.file);
  it('flags HIGH impact as liability, MODERATE as neutral', () => {
    expect(m?.descriptor.id).toBe('variant');
    const tp53 = doc.records.find(r => r.entity.label === 'TP53' && r.metric.name === 'IMPACT')!;
    expect(tp53.entity.type).toBe('variant');
    expect(tp53.assessment?.flag).toBe('liability');
    const brca = doc.records.find(r => r.entity.label === 'BRCA2' && r.metric.name === 'IMPACT')!;
    expect(brca.assessment?.flag).toBe('neutral');
  });
});

describe('documentToLegacy — backward-compatible flat projection', () => {
  const m = matchDescriptor('Predict ADMET Properties (AI)', [ADMET_JSON]);
  const legacy = documentToLegacy(buildFindingsDocument(m!.descriptor, m!.file));
  it('projects records to {metric,value,interpretation,source_file,entity}', () => {
    const asp = legacy.key_results.find(k => k.entity === 'CC(=O)Oc1ccccc1C(=O)O' && k.metric === 'hERG IC50')!;
    expect(asp.value).toBe('52.725 µM');          // units preserved in the flat value
    expect(asp.source_file).toBe('toxicity_report.json');
    const batchHerg = legacy.key_results.find(k => k.metric === 'hERG IC50 (panel)')!;
    expect(batchHerg.entity).toBe('panel (batch)'); // batch marked, not fabricated as a compound
  });
});
