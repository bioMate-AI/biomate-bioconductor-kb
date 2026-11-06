/**
 * Entity-aware findings + provenance — the canonical contract.
 *
 * One record = one entity, one metric, one value, with a verdict and provenance.
 * This schema replaces the ad-hoc per-workflow findings shapes (the 4 `_parseXOutput`
 * parsers + the flat `KeyResult`/`FindingsKeyResult` types). See
 * docs/20261025_FINDINGS_PROVENANCE_FRAMEWORK.md for the full framework + guideline.
 *
 * Migration step 1 (this file): the shared types + a transitional `LegacyKeyResult`
 * that the current consumers (findings-card.tsx, AfterRunReport.tsx) already satisfy, so
 * the type unifies with zero breakage. Later steps migrate the backend emitter + the
 * consumers onto the structured `FindingRecord`.
 */

export type EvidenceClass = 'Table' | 'Figure' | 'Structure' | 'Report' | 'Log';

export type EntityType =
  | 'compound' | 'gene' | 'variant' | 'protein' | 'peptide' | 'cell_type'
  | 'taxon' | 'go_term' | 'pathway' | 'particle' | 'map' | 'residue'
  | 'feature' | 'clonotype' | 'allele' | 'dose' | 'sample' | 'none';

/** WHO a value belongs to. `scope` distinguishes a per-entity value from a batch
 *  aggregate (belongs to no single entity) or a run-level/global metric. */
export interface FindingEntity {
  type: EntityType;
  label: string;
  identifier?: { scheme: string; value: string };
  identitySource?: 'input_mapping' | 'output_column' | 'companion_file' | 'unresolved';
  scope: 'per_entity' | 'batch' | 'global';
}

/** WHAT was measured. Never a bare number: units + (for censored values) a comparator
 *  and any confidence travel with it. */
export interface FindingMetric {
  name: string;
  value: string | number;
  units?: string;
  comparator?: '=' | '<' | '>' | '<=' | '>=' | '~';
  confidence?: { kind: 'ci' | 'sem' | 'prob' | 'applicability' | 'ood'; value: string };
}

/** VERDICT against an explicit criterion. A `pass` is not an overall-safety conclusion. */
export interface FindingAssessment {
  threshold?: { value: number; direction: 'high_bad' | 'low_bad' | 'band'; label?: string };
  flag: 'pass' | 'liability' | 'neutral' | 'unknown';
  interpretation: string;
}

/** WHERE a value came from — immutable, cited once and referenced by many records. */
export interface Provenance {
  id: string;
  source: { file: string; version?: string; locator?: string };
  producer?: { step?: string; tool?: string; toolVersion?: string; model?: string; modelVersion?: string };
  evidenceClass: EvidenceClass;
  outputRef?: string;
}

export interface FindingRecord {
  entity: FindingEntity;
  metric: FindingMetric;
  assessment?: FindingAssessment;
  /** key into FindingsDocument.provenance — provenance is shared, never reprinted per row. */
  provenanceRef: string;
}

export interface FindingsDocument {
  status: 'generating' | 'ready' | 'unavailable';
  summary: string;
  entityRoster: Array<{ type: EntityType; label: string; identifier?: { scheme: string; value: string } }>;
  records: FindingRecord[];
  provenance: Record<string, Provenance>;
  caveats: string[];
  nextSteps: string[];
  report?: { url: string; version?: string };
}

/**
 * Transitional flat shape — exactly what the 4 parsers + the LLM fallback emit and what
 * findings-card.tsx / AfterRunReport.tsx render today. `entity` is still a plain string
 * here (a compound name / SMILES); the structured `FindingEntity` is the migration target.
 * Keeping this as the single shared definition de-duplicates the three copies.
 */
export interface LegacyKeyResult {
  metric: string;
  value: string;
  interpretation: string;
  source_file?: string;
  /** Real entity this result belongs to, when a run assessed several. String, not
   *  structured, until the emitter migrates to FindingRecord. */
  entity?: string;
}

/** Render a measurement without ever producing a bare number: comparator + value + units,
 *  e.g. "> 30 µM", "0.875", "-1.2 kcal/mol". Pure + testable. */
export function formatMetricValue(m: Pick<FindingMetric, 'value' | 'units' | 'comparator'>): string {
  const cmp = m.comparator && m.comparator !== '=' ? `${m.comparator} ` : '';
  const unit = m.units ? ` ${m.units}` : '';
  return `${cmp}${m.value}${unit}`.trim();
}

/** Display label for an entity: prefer the human label, append the identifier scheme:value
 *  when present; `batch`/`global` scopes render as explicit non-attributed labels. */
export function findingEntityLabel(e: FindingEntity): string {
  if (e.scope === 'batch') return e.label ? `${e.label} (batch)` : 'Batch-level';
  if (e.scope === 'global') return e.label || 'Run-level';
  if (e.identitySource === 'unresolved') return `${e.label || 'Unattributed'} (unattributed)`;
  return e.label;
}
