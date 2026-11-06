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

export interface InputParam {
  id?: string;
  name?: string;
  label?: string;
  type?: string;
  value?: unknown;
  required?: boolean;
}

export interface SessionDataset {
  id: string;
  name: string;
  file_path?: string | null;
  source_url?: string | null;
}

export interface ParamDef {
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
