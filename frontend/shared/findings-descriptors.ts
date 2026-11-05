/**
 * Pattern descriptors — the DATA that replaces per-workflow parser CODE.
 *
 * Each descriptor says: how to recognize an output file, how to split it into entities,
 * and which metrics (+ units + thresholds) to read. The generic extractor
 * (findings-extract.ts) turns any descriptor into FindingRecord[]. Adding a domain =
 * adding a descriptor row here, NOT writing a new `_parseXOutput` function.
 *
 * See docs/20261025_FINDINGS_PROVENANCE_FRAMEWORK.md §3.
 */
import type { EntityType, EvidenceClass } from './findings';

export interface MetricSpec {
  name: string;
  /** csv/tsv header match · kvBlocks "key: value" key match · jsonReport field name (dot path). */
  source: string | RegExp;
  units?: string;
  /** numeric pass/fail gate (ADMET safety). Absent for descriptive/selection metrics. */
  threshold?: { value: number; direction: 'high_bad' | 'low_bad' | 'band'; label?: string };
  /** categorical verdict map (e.g. variant IMPACT HIGH→liability). First match wins. */
  categories?: Array<{ match: string | RegExp; flag: 'pass' | 'liability' | 'neutral'; label?: string }>;
  label?: string;
}

export interface PatternDescriptor {
  id: string;
  match: { fileRegex?: RegExp; contentIncludes?: string[] };
  parse: 'csv' | 'tsv' | 'autodelim' | 'kvBlocks' | 'jsonReport';
  entity: {
    type: EntityType;
    column?: string | RegExp;        // csv/tsv: entity column
    blockHeaderRegex?: RegExp;       // kvBlocks: new-entity line; capture group 1 = id
    arrayPath?: string | string[];   // jsonReport: dot path(s) to the entity array. When several
                                     // paths are given, every present array is MERGED by idField
                                     // (e.g. per_compound_admet_ai AI probs + per_compound heuristics).
    idField?: string;                // jsonReport: field in each entity object for the id
    scheme?: string;                 // identifier scheme (SMILES, Ensembl, …)
  };
  metrics: MetricSpec[];
  /** jsonReport: aggregate/batch fields that belong to no single entity (scope:'batch'). */
  batch?: { path?: string; metrics: MetricSpec[] };
  /** optional row selection for high-cardinality entities. */
  select?: {
    significant?: { metric: string; op: '<' | '>'; value: number };
    sort?: { metric: string; mode: 'absDesc' | 'asc' | 'desc' };
    topN?: number;
  };
  evidenceClass: EvidenceClass;
}

/** Looks like a SMILES (ring/bond/hetero tokens, no spaces) vs a plain name. */
export function looksLikeSmiles(s: string): boolean {
  return /[=#()\[\]]/.test(s) && /[A-Za-z]/.test(s) && !/\s/.test(s) && s.length <= 200;
}

// ── ADMET structured report (toxicity_report.json: per_compound[] + batch toxicity{}) ──
// The real toxicity_report.json (predict_admet_properties/main.nf) carries TWO per-compound
// arrays: `per_compound_admet_ai` (Chemprop AI probabilities: hERG_prob, DILI_prob,
// cyp2d6_inhibitor_prob, …) and `per_compound` (RDKit heuristics: herg_ic50_uM, logP, mw,
// dili_risk). The AI array holds the liability-bearing endpoints (hERG, CYP2D6) that the flat
// `_parseAdmetOutput` path in routes.ts flags from the same run's human-readable log. Reading
// ONLY `per_compound` (the old descriptor) left this path blind to hERG/CYP2D6, so the embedded
// findings_document summary said "No major liabilities flagged." while the flat summary flagged
// them — the dual-summary contradiction. We now MERGE both arrays by SMILES and mirror the flat
// path's exact metric names + 0.5 thresholds so the two liability verdicts can never disagree.
const ADMET_REPORT: PatternDescriptor = {
  id: 'admet_report',
  match: { fileRegex: /toxicity_report|admet.*\.json/i, contentIncludes: ['per_compound'] },
  parse: 'jsonReport',
  entity: { type: 'compound', arrayPath: ['per_compound_admet_ai', 'per_compound'], idField: 'smiles', scheme: 'SMILES' },
  metrics: [
    // ADMET-AI probability endpoints (per_compound_admet_ai) — names + thresholds mirror the
    // flat `_parseAdmetOutput` THRESHOLDS map exactly so both summaries flag the same set.
    { name: 'hERG inhibition',       source: 'hERG_prob',                threshold: { value: 0.5, direction: 'high_bad' }, label: 'hERG (cardiac) liability risk' },
    { name: 'DILI probability',      source: /^(dili_prob|dili_probability)$/i, threshold: { value: 0.5, direction: 'high_bad' }, label: 'drug-induced liver injury risk' },
    { name: 'CYP2D6 inhibitor',      source: 'cyp2d6_inhibitor_prob',    threshold: { value: 0.5, direction: 'high_bad' }, label: 'CYP2D6 inhibitor risk' },
    { name: 'Oral bioavailability',  source: 'oral_bioavailability_prob', threshold: { value: 0.5, direction: 'low_bad' },  label: 'oral bioavailability' },
    { name: 'ClinTox',               source: 'clintox_prob',             threshold: { value: 0.5, direction: 'high_bad' }, label: 'clinical toxicity probability' },
    { name: 'CYP3A4 substrate',      source: 'cyp3a4_substrate_prob',    label: 'CYP3A4 substrate probability' },
    { name: 'BBB penetration',       source: 'bbb_prob',                 label: 'blood-brain barrier penetration' },
    { name: 'Plasma protein bind %', source: 'ppbr_pct', units: '%',     label: 'plasma protein binding (%)' },
    { name: 'Caco-2 logPapp',        source: 'caco2_logPapp',            label: 'intestinal permeability (logPapp)' },
    // RDKit per_compound endpoints — kept for legacy reports that carry no ADMET-AI block.
    { name: 'hERG IC50',        source: 'herg_ic50_uM', units: 'µM', label: 'hERG (cardiac) IC50' },
    { name: 'logP',             source: 'logP', label: 'lipophilicity (logP)' },
    { name: 'MW',               source: 'mw', units: 'Da', label: 'molecular weight' },
    { name: 'DILI risk',        source: 'dili_risk', categories: [{ match: /high/i, flag: 'liability', label: 'high DILI risk' }, { match: /medium|moderate/i, flag: 'neutral' }, { match: /low/i, flag: 'pass' }], label: 'DILI risk tier' },
  ],
  batch: {
    path: 'toxicity',
    metrics: [
      { name: 'hERG IC50 (panel)', source: 'herg_ic50_uM', units: 'µM', label: 'panel hERG IC50' },
      { name: 'DILI probability (panel)', source: 'dili_probability', threshold: { value: 0.5, direction: 'high_bad' }, label: 'panel worst-compound DILI' },
      { name: 'Ames probability (panel)', source: 'ames_probability', threshold: { value: 0.5, direction: 'high_bad' }, label: 'panel Ames risk' },
    ],
  },
  evidenceClass: 'Report',
};

// ── ADMET per-compound kv-block text (the earlier _parseAdmetOutput format) ──
const ADMET: PatternDescriptor = {
  id: 'admet',
  match: { fileRegex: /admet|predict_admet|predict.*prop/i, contentIncludes: ['hERG', 'DILI'] },
  parse: 'kvBlocks',
  entity: { type: 'compound', blockHeaderRegex: /^(?:Drug|Compound):\s*(\S.*)$/i, scheme: 'SMILES' },
  metrics: [
    { name: 'hERG inhibition',       source: 'hERG inhibition',       threshold: { value: 0.5, direction: 'high_bad' }, label: 'hERG (cardiac) liability risk' },
    { name: 'DILI probability',      source: 'DILI probability',      threshold: { value: 0.5, direction: 'high_bad' }, label: 'drug-induced liver injury risk' },
    { name: 'Oral bioavailability',  source: 'Oral bioavailability',  threshold: { value: 0.5, direction: 'low_bad' },  label: 'oral bioavailability' },
    { name: 'BBB penetration',       source: 'BBB penetration',       label: 'blood-brain barrier penetration' },
    { name: 'ClinTox',               source: 'ClinTox',               threshold: { value: 0.5, direction: 'high_bad' }, label: 'clinical toxicity probability' },
    { name: 'Plasma protein bind %', source: 'Plasma protein bind %', units: '%', label: 'plasma protein binding (%)' },
    { name: 'Caco-2 logPapp',        source: 'Caco-2 logPapp',        label: 'intestinal permeability (logPapp)' },
    { name: 'CYP2D6 inhibitor',      source: 'CYP2D6 inhibitor',      threshold: { value: 0.5, direction: 'high_bad' }, label: 'CYP2D6 inhibitor risk' },
    { name: 'CYP3A4 substrate',      source: 'CYP3A4 substrate',      label: 'CYP3A4 substrate probability' },
    { name: 'Ames mutagenicity',     source: 'Ames mutagenicity',     threshold: { value: 0.5, direction: 'high_bad' }, label: 'Ames mutagenicity risk' },
  ],
  evidenceClass: 'Table',
};

// ── DESeq2 differential expression (gene entity; significance = selection not verdict) ──
const DESEQ2: PatternDescriptor = {
  id: 'deseq2',
  match: { fileRegex: /deseq2|de_results|differential/i, contentIncludes: ['log2FoldChange'] },
  parse: 'autodelim',
  entity: { type: 'gene', column: /^(gene|gene_id|geneid|gene\.name|name|symbol)$/i, scheme: 'symbol' },
  metrics: [
    { name: 'log2FoldChange', source: /log2fold/i, label: 'log2 fold-change' },
    { name: 'padj',           source: /^(padj|p\.adj|fdr|bh|q\.value)$/i, label: 'adjusted p-value' },
  ],
  select: { significant: { metric: 'padj', op: '<', value: 0.05 }, sort: { metric: 'log2FoldChange', mode: 'absDesc' }, topN: 16 },
  evidenceClass: 'Table',
};

// ── GO / pathway enrichment (go_term entity; smallest padj first) ──
const ENRICHGO: PatternDescriptor = {
  id: 'enrichgo',
  match: { fileRegex: /enrichgo|enrich_go|go_enrich|clusterprofiler|gsea|pathway/i, contentIncludes: ['GeneRatio'] },
  parse: 'autodelim',
  entity: { type: 'go_term', column: /^(description|term|pathway|name)$/i },
  metrics: [
    { name: 'p.adjust',  source: /^(p\.adjust|padj|fdr|qvalue)$/i, label: 'adjusted p-value' },
    { name: 'GeneRatio', source: /^(generatio|gene_ratio|ratio)$/i, label: 'gene ratio' },
    { name: 'Count',     source: /^(count|gene_count)$/i, label: 'gene count' },
  ],
  select: { significant: { metric: 'p.adjust', op: '<', value: 0.05 }, sort: { metric: 'p.adjust', mode: 'asc' }, topN: 12 },
  evidenceClass: 'Table',
};

// ── Rare-disease / annotated variants (variant entity; categorical IMPACT verdict) ──
const VARIANT: PatternDescriptor = {
  id: 'variant',
  // audit S3#7: dropped the generic tokens `annotated`/`filtered` — matchDescriptor matches on
  // filename alone, so they cross-fired on non-variant outputs (scRNA `filtered_feature_bc_matrix`,
  // annotated cell tables) and attached a spurious impact document. Keep variant-specific tokens;
  // real variant tables carry variant/vep/snpeff/.vcf.
  match: { fileRegex: /variant|vep|snpeff|\.vcf(\.|$)/i },
  parse: 'autodelim',
  entity: { type: 'variant', column: /gene|gene\.refgene|symbol/i, scheme: 'symbol' },
  metrics: [
    { name: 'IMPACT', source: /^(impact|severity)$/i,
      categories: [
        { match: /high/i, flag: 'liability', label: 'high-impact variant' },
        { match: /moderate|^mod$/i, flag: 'neutral', label: 'moderate-impact variant' },
        { match: /low|modifier/i, flag: 'pass', label: 'low-impact variant' },
      ], label: 'predicted impact' },
    { name: 'consequence', source: /func|consequence|exonicfunc/i, label: 'consequence' },
  ],
  select: { topN: 200 },
  evidenceClass: 'Table',
};

export const DESCRIPTORS: PatternDescriptor[] = [ADMET_REPORT, ADMET, DESEQ2, ENRICHGO, VARIANT];

/** Pick the first descriptor whose match hits for (workflowName, files). */
export function matchDescriptor(
  workflowName: string,
  files: Array<{ name: string; content: string }>,
): { descriptor: PatternDescriptor; file: { name: string; content: string } } | null {
  for (const d of DESCRIPTORS) {
    for (const f of files) {
      const nameHit = d.match.fileRegex ? d.match.fileRegex.test(f.name) || d.match.fileRegex.test(workflowName) : false;
      const contentHit = d.match.contentIncludes ? d.match.contentIncludes.every(c => f.content.includes(c)) : false;
      if (nameHit || (d.match.contentIncludes && contentHit)) return { descriptor: d, file: f };
    }
  }
  return null;
}
