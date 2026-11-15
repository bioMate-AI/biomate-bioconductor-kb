/**
 * Pure derivation of the pre-run "Inputs mapped" state (L3 of the publication
 * flow: before a run, BioMate restates which dataset is bound to each input and
 * flags anything not safely resolved). Extracted from nextflow-workflow-viewer's
 * inline card so the status logic — and the run-block condition — is unit-testable
 * without mounting the ~3,700-line panel.
 *
 * Honesty rule: a resolved input is "resolved · format not checked" unless we
 * actually sniffed a kind (perception viewKind or clear extension map) and it
 * matched — we never assert a green compatibility "ok" we did not check. A
 * declared `format_mismatch_warning` or a strong sniff contradiction → needs-mapping.
 */

import {
  isDataInputParam,
  isBoundUserDataParam,
  isOptionalFileOverride,
  isBoundValue,
  CLINIC_HARD_REQUIRED_DATA_NAMES,
  type DataInputParamLike,
} from '../../../shared/workflow-data-inputs';
import { kindFromName } from './datasets/dataset-view-model';

export interface InputParam {
  id?: string;
  name?: string;
  label?: string;
  type?: string;
  value?: unknown;
  defaultValue?: unknown;
  required?: boolean;
}

export interface SessionDataset {
  id: string;
  name: string;
  file_path?: string | null;
  source_url?: string | null;
  /** Perception (or stored profileSummary) viewKind when known. */
  viewKind?: string | null;
  /** Perception quality — blocked/unreached must not invent a type mismatch. */
  quality?: string | null;
}

export interface ParamDef extends DataInputParamLike {
  name?: string;
  /** Optional; prefer undefined over null for DataInputParamLike compat. */
  format?: string;
  format_mismatch_warning?: string | null;
}

export type InputMappingStatus =
  | 'resolved'        // bound to a value; no known format mismatch
  | 'unresolved'      // required input with no value → run is blocked
  | 'needs-mapping'   // bound but format mismatch (declared or sniffed) → blocked
  | 'optional-empty'; // optional input left empty → fine, run not blocked

export interface InputMappingRow {
  param: InputParam;
  value: unknown;
  empty: boolean;
  dataset: SessionDataset | null;
  mismatch: string | null;
  status: InputMappingStatus;
  /** True when we sniffed a kind and it was compatible (chip can say format ok). */
  formatChecked?: boolean;
}

export type ParamSchemaHint = {
  description?: string | null;
  type?: string | null;
  format?: string | null;
  label?: string | null;
};

/** True when schema text clearly describes a samplesheet / CSV / TSV table input. */
export function schemaHintsSamplesheet(hint?: ParamSchemaHint | null): boolean {
  if (!hint) return false;
  const blob = [hint.description, hint.format, hint.label, hint.type]
    .filter((s): s is string => typeof s === 'string' && s.length > 0)
    .join(' ')
    .toLowerCase();
  if (!blob) return false;
  return /samplesheet|sample[_\s-]?sheet|sample[_\s-]?metadata|coldata|contrasts|\bcsv\b|\btsv\b|\btable\b/.test(blob);
}

/** Param-name families → accepted perception viewKinds. null = do not sniff-gate. */
export function expectedViewKindsForParam(
  name: string | undefined,
  schemaHint?: ParamSchemaHint | null,
): ReadonlySet<string> | null {
  if (!name) return null;
  const n = name.toLowerCase().replace(/-/g, '_');
  if (/^(reads|fastq|fastqs|input_fastq|read1|read2|r1|r2)$/.test(n) || /_fastq$/.test(n)) {
    return new Set(['reads']);
  }
  if (/^(bam|cram|sam|alignment|alignments)$/.test(n) || /_(bam|cram)$/.test(n)) {
    return new Set(['alignment']);
  }
  if (/^(vcf|variants)$/.test(n) || /_vcf$/.test(n)) {
    return new Set(['variants']);
  }
  if (/^(fasta|fa|genome_fasta|reference_fasta|ref_fasta)$/.test(n) || /_fasta$/.test(n)) {
    return new Set(['sequences']);
  }
  if (/^(gtf|gff|gff3|annotation)$/.test(n)) {
    return new Set(['annotation']);
  }
  if (/^(movies_path|movie_dir|movies|mrc|tomogram)$/.test(n)) {
    return new Set(['image']);
  }
  if (/^(matrix|counts|count_matrix|countmatrix|expression)$/.test(n)) {
    return new Set(['table', 'matrix', 'anndata', 'loom']);
  }
  // Explicit samplesheet / design CSV names — the bound file is the sheet, not FASTQs.
  // Bare `input` is too generic (FASTA/FASTQ/BAM workflows use it) — only gate when
  // schema/description hints samplesheet/csv/tsv.
  if (/^(samplesheet|sample_sheet|sample_metadata|metadata|design|contrasts|coldata|input_csv)$/.test(n)) {
    return new Set(['table', 'records', 'document']);
  }
  if (n === 'input' && schemaHintsSamplesheet(schemaHint)) {
    return new Set(['table', 'records', 'document']);
  }
  return null;
}

function datasetNameHint(dataset: SessionDataset | null, value: unknown): string {
  if (dataset?.name) return dataset.name;
  if (value === undefined || value === null || value === '') return '';
  const s = String(value);
  // Basename of a path / URI for extension sniff when session lookup missed.
  const leaf = s.split(/[\\/]/).pop() || s;
  return leaf.split('?')[0] || leaf;
}

/** Kinds strong enough to contradict a param family. binary/archive/json/… stay unchecked. */
const GATEABLE_KINDS = new Set([
  'reads', 'alignment', 'variants', 'sequences', 'annotation', 'image',
  'table', 'matrix', 'anndata', 'loom', 'records', 'document',
]);

function sniffedViewKind(dataset: SessionDataset | null, value?: unknown): string | null {
  if (dataset?.quality === 'blocked') return null;
  const vk = dataset?.viewKind;
  if (typeof vk === 'string' && vk && vk !== 'unknown') {
    return GATEABLE_KINDS.has(vk) ? vk : null;
  }
  const fromName = kindFromName(datasetNameHint(dataset, value));
  return GATEABLE_KINDS.has(fromName) ? fromName : null;
}

/**
 * Strong contradiction between a bound file's sniffed kind and the param's
 * expected kinds. Returns a user-facing warning or null (no block).
 */
export function perceptionMismatch(
  paramName: string | undefined,
  dataset: SessionDataset | null,
  value?: unknown,
  schemaHint?: ParamSchemaHint | null,
): string | null {
  const expected = expectedViewKindsForParam(paramName, schemaHint);
  if (!expected) return null;
  const got = sniffedViewKind(dataset, value);
  if (!got) return null;
  if (expected.has(got)) return null;
  const label = datasetNameHint(dataset, value) || 'file';
  return `Expected ${[...expected].join('/')} for “${paramName}”, got ${got} (${label})`;
}

/** Resolve a bound param value to the session dataset object it refers to (by
 *  file path, source URL, id, or name), or null when nothing matches. */
export function datasetForValue(
  value: unknown,
  sessionDatasets: readonly SessionDataset[],
): SessionDataset | null {
  if (value === undefined || value === null || value === '') return null;
  const s = String(value);
  return (
    sessionDatasets.find(
      d => d.file_path === s || d.source_url === s || d.id === s || d.name === s,
    ) || null
  );
}

/** The real compatibility signal: a format-mismatch warning declared on the
 *  param definition (same source the panel already surfaces), or null. */
export function mismatchForParam(
  name: string | undefined,
  paramDefs: readonly ParamDef[],
): string | null {
  if (!name) return null;
  return paramDefs.find(d => d?.name === name)?.format_mismatch_warning || null;
}

function isEmpty(value: unknown): boolean {
  return value === undefined || value === null || value === '';
}

/** Derive one row per file input: which dataset is bound and its resolution
 *  status. This is the load-bearing logic behind the "Inputs mapped" card. */
export function deriveInputMappingRows(
  fileParams: readonly InputParam[],
  sessionDatasets: readonly SessionDataset[],
  paramDefs: readonly ParamDef[],
): InputMappingRow[] {
  return fileParams.map(p => {
    const value = p.value;
    const empty = isEmpty(value);
    const dataset = datasetForValue(value, sessionDatasets);
    const paramName = p.id || p.name || '';
    const def = paramDefs.find(d => d?.name === paramName);
    const schemaHint: ParamSchemaHint | null = def
      ? {
          description: typeof (def as any).description === 'string' ? (def as any).description : null,
          type: def.type ?? null,
          format: typeof def.format === 'string' ? def.format : null,
          label: typeof (p as any).label === 'string' ? (p as any).label
            : typeof (def as any).label === 'string' ? (def as any).label : null,
        }
      : {
          description: null,
          type: p.type ?? null,
          format: null,
          label: typeof (p as any).label === 'string' ? (p as any).label : null,
        };
    const declared = mismatchForParam(paramName, paramDefs);
    const sniffed = perceptionMismatch(paramName, dataset, value, schemaHint);
    const mismatch = declared || sniffed;
    const formatChecked = !empty && !mismatch && sniffedViewKind(dataset, value) != null
      && expectedViewKindsForParam(paramName, schemaHint) != null;
    const status: InputMappingStatus =
      p.required && empty
        ? 'unresolved'
        : mismatch
          ? 'needs-mapping'
          : empty
            ? 'optional-empty'
            : 'resolved';
    return { param: p, value, empty, dataset, mismatch, status, formatChecked };
  });
}

/** Rows that must be resolved before the run can proceed. */
export function blockingInputRows(rows: readonly InputMappingRow[]): InputMappingRow[] {
  return rows.filter(r => r.status === 'unresolved' || r.status === 'needs-mapping');
}

/** Whether the run is blocked by unresolved/mismatched inputs. */
export function runIsBlockedByInputs(rows: readonly InputMappingRow[]): boolean {
  return blockingInputRows(rows).length > 0;
}

/**
 * The pre-run Inputs card model. Splits the workflow's params into:
 *  - `primary`   — the user's data inputs (required data inputs first, even when
 *                  the schema types them as plain strings, e.g. nf-core/rnaseq's
 *                  `input` samplesheet), plus any optional file the user/AI bound;
 *  - `overrides` — optional file overrides still on their default (reference
 *                  FASTA/GTF from the genome, the rRNA manifest, …). These are NOT
 *                  "mapped inputs"; the card shows them collapsed.
 * Classification comes from shared/workflow-data-inputs (same classifier the chat
 * reply state uses), reading schema metadata from the workflow's param defs.
 */
export interface PrerunInputsModel {
  primary: InputMappingRow[];
  overrides: InputMappingRow[];
  requiredCount: number;
  requiredUnset: number;
  boundCount: number;
}

export function derivePrerunInputs(
  params: readonly InputParam[],
  sessionDatasets: readonly SessionDataset[],
  paramDefs: readonly ParamDef[],
): PrerunInputsModel {
  const defFor = (p: InputParam) => paramDefs.find(d => d?.name && d.name === (p.id || p.name));
  // Viewer fields (resolved type/required/value) win over the raw def.
  const merged = (p: InputParam): DataInputParamLike => ({ ...(defFor(p) || {}), ...p });
  const primaryParams: InputParam[] = [];
  const overrideParams: InputParam[] = [];
  for (const p of params) {
    const m = merged(p);
    if (isDataInputParam(m)) { primaryParams.push(p); continue; }
    // Bound to the user's data although the schema does not mark it required
    // (catalog schemas often declare no `required` list) — still a mapped input.
    if (isBoundUserDataParam({ ...m, value: p.value })) { primaryParams.push(p); continue; }
    if (!isOptionalFileOverride(m)) continue;
    // An optional file the user/AI actually bound (value differs from its default)
    // IS a mapped input; one still on its default is only an override.
    const userBound = isBoundValue(p.value) && String(p.value) !== String(p.defaultValue ?? '');
    (userBound ? primaryParams : overrideParams).push(p);
  }
  // Clinic hard primary data must count as required for unresolved/blocking status
  // even when the schema left required=false (movies_path demo elvis, DE stubs).
  for (const p of primaryParams) {
    const n = String(p.id || p.name || '').toLowerCase();
    if (CLINIC_HARD_REQUIRED_DATA_NAMES.has(n)) (p as InputParam).required = true;
  }
  primaryParams.sort((a, b) => Number(!!b.required) - Number(!!a.required));
  const primary = deriveInputMappingRows(primaryParams, sessionDatasets, paramDefs);
  const overrides = deriveInputMappingRows(overrideParams, sessionDatasets, paramDefs);
  const required = primary.filter(r => r.param.required);
  return {
    primary,
    overrides,
    requiredCount: required.length,
    requiredUnset: required.filter(r => r.empty).length,
    boundCount: primary.filter(r => !r.empty).length,
  };
}
