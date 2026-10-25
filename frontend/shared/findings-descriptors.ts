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
  /** csv/tsv: header name match. kvBlocks: the "key: value" key match. */
  source: string | RegExp;
  units?: string;
  threshold?: { value: number; direction: 'high_bad' | 'low_bad' | 'band'; label?: string };
  /** human label used in the interpretation sentence, e.g. "hERG (cardiac) liability risk". */
  label?: string;
}

export interface PatternDescriptor {
  id: string;
  /** recognize the output file. fileRegex OR any contentIncludes hit. */
  match: { fileRegex?: RegExp; contentIncludes?: string[] };
  parse: 'csv' | 'tsv' | 'kvBlocks';
  entity: {
    type: EntityType;
    /** csv/tsv: the entity column name match. */
    column?: string | RegExp;
    /** kvBlocks: the line that starts a new entity block; capture group 1 = the id. */
    blockHeaderRegex?: RegExp;
    /** identifier scheme for the entity id when it is an accession/SMILES/etc. */
    scheme?: string;
  };
  /** explicit metric list (ADMET) — the generic extractor reads exactly these. */
  metrics: MetricSpec[];
  /** optional row selection for high-cardinality entities (e.g. DE genes). */
  select?: {
    significant?: { metric: string; op: '<' | '>'; value: number };
    sortByAbs?: string;      // metric name to sort by |value|, descending
    topN?: number;
  };
  evidenceClass: EvidenceClass;
}

/** Looks like a SMILES (has ring/bond/hetero tokens and no spaces) vs a plain name. */
export function looksLikeSmiles(s: string): boolean {
  return /[=#()\[\]]/.test(s) && /[A-Za-z]/.test(s) && !/\s/.test(s) && s.length <= 200;
}

// ── ADMET (ported from _parseAdmetOutput THRESHOLDS; parse = per-compound kv blocks) ──
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

// ── DESeq2 differential expression (ported from _parseDeseq2Output; parse = csv) ──
const DESEQ2: PatternDescriptor = {
  id: 'deseq2',
  match: { fileRegex: /deseq2|de_results|differential/i, contentIncludes: ['log2FoldChange'] },
  parse: 'csv',
  entity: { type: 'gene', column: /^(gene|gene_id|geneid|gene\.name|name|symbol)$/i, scheme: 'symbol' },
  // NOTE: padj carries NO assessment threshold — significance is a SELECTION criterion
  // (a DE hit is not a pass/fail "verdict"), handled by `select` below. `assessment` is
  // reserved for domains with a real quality gate (e.g. ADMET safety). See framework §4.
  metrics: [
    { name: 'log2FoldChange', source: /log2fold/i, label: 'log2 fold-change' },
    { name: 'padj',           source: /^(padj|p\.adj|fdr|bh|q\.value)$/i, label: 'adjusted p-value' },
  ],
  select: { significant: { metric: 'padj', op: '<', value: 0.05 }, sortByAbs: 'log2FoldChange', topN: 16 },
  evidenceClass: 'Table',
};

export const DESCRIPTORS: PatternDescriptor[] = [ADMET, DESEQ2];

/** Pick the first descriptor whose match hits for (workflowName, files). */
export function matchDescriptor(
  workflowName: string,
  files: Array<{ name: string; content: string }>,
): { descriptor: PatternDescriptor; file: { name: string; content: string } } | null {
  for (const d of DESCRIPTORS) {
    for (const f of files) {
      const nameHit = d.match.fileRegex ? d.match.fileRegex.test(f.name) || d.match.fileRegex.test(workflowName) : false;
      const contentHit = d.match.contentIncludes ? d.match.contentIncludes.some(c => f.content.includes(c)) : false;
      if (nameHit || contentHit) return { descriptor: d, file: f };
    }
  }
  return null;
}
