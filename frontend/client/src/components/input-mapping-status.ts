/**
 * Pure derivation of the pre-run "Inputs mapped" state (L3 of the publication
 * flow: before a run, BioMate restates which dataset is bound to each input and
 * flags anything not safely resolved). Extracted from nextflow-workflow-viewer's
 * inline card so the status logic — and the run-block condition — is unit-testable
 * without mounting the ~3,700-line panel.
 *
 * Honesty rule: a resolved input is "resolved · format not checked" unless a real
 * `format_mismatch_warning` exists on its param definition — we never assert a
 * green compatibility "ok" we did not actually check.
 */

import {
  isDataInputParam,
  isBoundUserDataParam,
  isOptionalFileOverride,
  isBoundValue,
  CLINIC_HARD_REQUIRED_DATA_NAMES,
  type DataInputParamLike,
} from '../../../shared/workflow-data-inputs';

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
}

export interface ParamDef extends DataInputParamLike {
  name?: string;
  format_mismatch_warning?: string | null;
}

export type InputMappingStatus =
  | 'resolved'        // bound to a value; no known format mismatch (compat not auto-checked)
  | 'unresolved'      // required input with no value → run is blocked
  | 'needs-mapping'   // bound but the param def carries a real format-mismatch warning → blocked
  | 'optional-empty'; // optional input left empty → fine, run not blocked

export interface InputMappingRow {
  param: InputParam;
  value: unknown;
  empty: boolean;
  dataset: SessionDataset | null;
  mismatch: string | null;
  status: InputMappingStatus;
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
    const mismatch = mismatchForParam(p.id || p.name || '', paramDefs);
    const status: InputMappingStatus =
      p.required && empty
        ? 'unresolved'
        : mismatch
          ? 'needs-mapping'
          : empty
            ? 'optional-empty'
            : 'resolved';
    return { param: p, value, empty, dataset, mismatch, status };
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
