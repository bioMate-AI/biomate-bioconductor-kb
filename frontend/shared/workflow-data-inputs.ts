/**
 * Which workflow parameters are the user's DATA inputs (samplesheet, reads,
 * count matrix, …) versus optional reference/file overrides or plain settings.
 *
 * One classifier, used by both surfaces so they cannot disagree:
 *   - the chat reply state (server/galaxy-assistant.ts) — "workflow found, its
 *     required data input is not provided yet" vs "ready to run";
 *   - the pre-run Inputs card (client input-mapping-status.ts).
 *
 * Schema signals come first (the backend's `data_input` flag, required-ness,
 * `type: 'file'`, nf-core `format: file-path` / `mimetype`, the nf-core
 * "Input/output options" group). Canonical data-input names are only a
 * fallback for stub-parsed params that carry no schema metadata (e.g. the
 * nf-core/rnaseq stub's `params.input = null // Samplesheet CSV …`, which the
 * .nf parser surfaces as a required *string*).
 */

export interface DataInputParamLike {
  name?: string;
  id?: string;
  label?: string;
  description?: string;
  type?: string;
  required?: boolean;
  /** Backend flag for files the workflow reads (ai_assistant.py style-A data tokens). */
  data_input?: boolean;
  /** nf-core schema group title, e.g. "Input/output options", "Reference genome options". */
  group?: string;
  /** nf-core JSON-schema format, e.g. "file-path". */
  format?: string;
  mimetype?: string;
  value?: unknown;
  default?: unknown;
  defaultValue?: unknown;
}

/** Set by the executor on every run, or pure run metadata — never a user data input. */
const EXECUTOR_SET_PARAMS = new Set([
  'outdir', 'out_dir', 'output_dir', 'publish_dir', 'work_dir', 'email', 'email_on_fail',
  'multiqc_title', 'plaintext_email', 'monochrome_logs', 'hook_url',
]);

/** Fallback only: canonical names of primary data inputs when no schema metadata exists. */
const CANONICAL_DATA_INPUT_NAMES = new Set([
  'input', 'input_csv', 'input_file', 'input_dir', 'input_path', 'samplesheet', 'sample_sheet',
  'reads', 'reads1', 'reads2', 'fastq', 'fastq1', 'fastq2', 'fastq_1', 'fastq_2', 'input_fastq',
  'matrix', 'counts', 'count_matrix', 'contrasts', 'design', 'bam', 'vcf', 'input_fasta',
  // Cryo-EM primary data (missed here → panel treated Movies Path as optional override)
  'movies_path', 'movie_dir',
]);

/**
 * Clinic hard-required primary data — must block Confirm & Run / execute even when
 * nextflow_schema.json declares `required: []` or the .nf elvis-falls-back to test_data.
 * Keep in sync with AIAssistant._CLINIC_HARD_REQUIRED_DATA.
 * (contrasts intentionally omitted — DE auto-derives when absent.)
 */
export const CLINIC_HARD_REQUIRED_DATA_NAMES = new Set([
  'movies_path', 'movie_dir',
  'samplesheet', 'sample_sheet',
  'matrix', 'counts', 'count_matrix',
  'reads', 'fastq', 'fastq_1', 'fastq_2', 'input_fastq',
  'input_csv', 'input_file', 'input_path',
]);

function paramName(p: DataInputParamLike): string {
  return String(p.name || p.id || '').trim().toLowerCase();
}

export function isExecutorSetParam(p: DataInputParamLike): boolean {
  return EXECUTOR_SET_PARAMS.has(paramName(p));
}

/** True for a parameter the user supplies DATA through (not a setting, not an executor-managed path). */
export function isDataInputParam(p: DataInputParamLike): boolean {
  const name = paramName(p);
  if (!name || name.startsWith('__') || isExecutorSetParam(p)) return false;
  if (p.data_input === true) return true;
  // Clinic hard primary data is always a data input — even when the schema left
  // required=false (differentialabundance stub, cryo demo elvis).
  if (CLINIC_HARD_REQUIRED_DATA_NAMES.has(name)) return true;
  // Optional params without the backend data_input flag are overrides/settings
  // (reference FASTA/GTF with genome defaults, multiqc_config, …), not the
  // user's primary data.
  if (!p.required) return false;
  if (p.type === 'file') return true;
  if (p.format === 'file-path' || !!p.mimetype) return true;
  if (/\binput\b/i.test(String(p.group || ''))) return true;
  return CANONICAL_DATA_INPUT_NAMES.has(name);
}

/**
 * A param that is BOUND to the user's data even though the schema does not mark it
 * required: a canonical data-input name (samplesheet, matrix, counts, …) or a value
 * that is a stored/staged file (s3://, gs://, file://, an absolute path, or a file
 * name). Many catalog schemas declare no `required` list at all (nf-core
 * differentialabundance: `required: []`), so `isDataInputParam` alone dropped a
 * bound samplesheet + matrix and the panel claimed "no data upload needed".
 */
export function isBoundUserDataParam(p: DataInputParamLike & { value?: unknown }): boolean {
  const name = paramName(p);
  if (!name || name.startsWith('__') || isExecutorSetParam(p)) return false;
  if (!isBoundValue(p.value)) return false;
  if (CANONICAL_DATA_INPUT_NAMES.has(name)) return true;
  const v = String(p.value).trim();
  return /^(?:s3|gs|file):\/\//i.test(v) || /^\/[^\s]+\.[A-Za-z0-9]{1,8}(?:\.gz)?$/.test(v);
}

/** An optional file parameter that only overrides a default (genome reference, rRNA manifest, …). */
export function isOptionalFileOverride(p: DataInputParamLike): boolean {
  return p.type === 'file' && !p.required && !isDataInputParam(p) && !isExecutorSetParam(p);
}

export function isBoundValue(value: unknown): boolean {
  if (value === undefined || value === null) return false;
  if (Array.isArray(value)) return value.length > 0;
  return String(value).trim() !== '';
}

export interface UnboundDataInput {
  name: string;
  label: string;
  description: string;
}

/**
 * The generated workflow's REQUIRED data inputs that have no value yet, read
 * from the workflow_ga param lists the panel renders (plus the backend's own
 * `missing_file_inputs` list). `alsoBound` names inputs the caller knows are
 * satisfied some other way (e.g. inline data extracted from the message).
 */
export function unboundRequiredDataInputs(
  generatedWorkflow: any,
  alsoBound: ReadonlySet<string> = new Set(),
): UnboundDataInput[] {
  const ga = generatedWorkflow?.workflow_ga || {};
  const req: any[] = Array.isArray(ga.required_params) ? ga.required_params
    : Array.isArray(generatedWorkflow?.required_params) ? generatedWorkflow.required_params : [];
  const opt: any[] = Array.isArray(ga.optional_params) ? ga.optional_params
    : Array.isArray(generatedWorkflow?.optional_params) ? generatedWorkflow.optional_params : [];
  const out: UnboundDataInput[] = [];
  const seen = new Set<string>();
  for (const p of req) {
    const name = String(p?.name || '');
    if (!name || seen.has(name)) continue;
    if (!isDataInputParam({ ...p, required: true })) continue;
    if (isBoundValue(p.value) || isBoundValue(p.default) || alsoBound.has(name)) continue;
    seen.add(name);
    out.push({
      name,
      label: String(p.label || name),
      description: String(p.description || '').slice(0, 200),
    });
  }
  // Schema stubs often put samplesheet/matrix/movies_path in optional_params with
  // required:[] — still block the clinic run when unbound.
  for (const p of opt) {
    const name = String(p?.name || '');
    if (!name || seen.has(name)) continue;
    if (!CLINIC_HARD_REQUIRED_DATA_NAMES.has(name.toLowerCase())) continue;
    if (isBoundValue(p.value) || isBoundValue(p.default) || alsoBound.has(name)) continue;
    seen.add(name);
    out.push({
      name,
      label: String(p.label || name),
      description: String(p.description || '').slice(0, 200),
    });
  }
  // Executor-owned required data inputs the backend describes but never exposes as editable
  // params (nf-core `input`: the executor builds the samplesheet from files or an accession).
  const described: any[] = Array.isArray(ga.data_inputs) ? ga.data_inputs
    : Array.isArray(generatedWorkflow?.data_inputs) ? generatedWorkflow.data_inputs : [];
  for (const d of described) {
    const name = String(d?.name || '');
    if (!name || !d?.required || d?.bound || seen.has(name) || alsoBound.has(name)) continue;
    seen.add(name);
    out.push({ name, label: String(d.label || name), description: String(d.description || '').slice(0, 200) });
  }
  const mfi: unknown[] = Array.isArray(generatedWorkflow?.missing_file_inputs) ? generatedWorkflow.missing_file_inputs : [];
  for (const m of mfi) {
    const name = String(m || '');
    if (!name || seen.has(name) || alsoBound.has(name)) continue;
    seen.add(name);
    out.push({ name, label: name, description: '' });
  }
  return out;
}

/**
 * Flat param map + workflow_ga → clinic-hard primary data still unbound.
 * Used by the panel Confirm & Run gate and the server execute gate so they agree.
 */
export function unboundClinicHardDataFromParams(
  workflowDefinition: any,
  flatParams: Record<string, unknown> = {},
): UnboundDataInput[] {
  const alsoBound = new Set<string>();
  for (const [k, v] of Object.entries(flatParams || {})) {
    if (isBoundValue(v)) alsoBound.add(k);
  }
  // Mirror flat values onto param rows so unboundRequiredDataInputs sees them.
  const ga = workflowDefinition?.workflow_ga || workflowDefinition || {};
  const patch = (list: any[] | undefined) =>
    (Array.isArray(list) ? list : []).map((p: any) => {
      const n = String(p?.name || '');
      if (!n || !Object.prototype.hasOwnProperty.call(flatParams, n)) return p;
      return { ...p, value: flatParams[n] };
    });
  return unboundRequiredDataInputs({
    ...workflowDefinition,
    workflow_ga: {
      ...ga,
      required_params: patch(ga.required_params || workflowDefinition?.required_params),
      optional_params: patch(ga.optional_params || workflowDefinition?.optional_params),
      data_inputs: ga.data_inputs || workflowDefinition?.data_inputs,
    },
    missing_file_inputs: workflowDefinition?.missing_file_inputs,
  }, alsoBound);
}

/**
 * True when the resolved workflow ships its own bundled example dataset and can
 * run with no user input (backend `example_data.present`, derived from the .nf
 * definition — a built-in demo-data fallback or a data param defaulting to
 * bundled example data; see ai_assistant._detect_example_data). The chat reply
 * then presents the card as runnable on the example dataset instead of asking
 * for an upload. A real per-workflow property, never a list of workflow names.
 */
export function workflowHasExampleData(generatedWorkflow: any): boolean {
  const ga = generatedWorkflow?.workflow_ga || {};
  return ga?.example_data?.present === true || generatedWorkflow?.example_data?.present === true;
}

/**
 * The runnable workflow should present + run on its own example dataset (no ask)
 * exactly when it ships example data AND the request carried no user data of its
 * own (an upload / accession / inline data / an explicit waiver). When the user
 * supplied data, THEIR data is used, so this is false. A workflow with no example
 * data is always false, so the DATA-FIRST ask is preserved for it.
 */
export function shouldRunOnExampleData(
  generatedWorkflow: any,
  opts: { runnableWorkflow: boolean; userSuppliedRunData: boolean },
): boolean {
  return !!(opts.runnableWorkflow
    && workflowHasExampleData(generatedWorkflow)
    && !opts.userSuppliedRunData);
}

/** The one honest, storage-path-free sentence the backend supplies for the reply. */
export function exampleDataNote(generatedWorkflow: any): string {
  const ga = generatedWorkflow?.workflow_ga || {};
  const note = ga?.example_data?.note || generatedWorkflow?.example_data?.note;
  return typeof note === 'string' && note.trim()
    ? note.trim()
    : "Runs on the workflow's built-in example dataset — attach your own files to replace it.";
}

/** Public data accessions the run can fetch (SRA/ENA/DDBJ runs, GEO, ArrayExpress, PRIDE). */
const RUN_DATA_ACCESSION_RE = /\b(?:[SED]RR\d{6,9}|[SED]RX\d{6,9}|[SED]RP\d{6,9}|PRJ[NED][A-Z]?\d{4,9}|GSE\d{3,9}|GSM\d{3,9}|E-[A-Z]{4}-\d{1,9}|PXD\d{4,9})\b/i;

/** True when the chat message itself carries data for a run: attached/uploaded
 *  datasets (client-appended blocks) or a public data accession. */
export function messageCarriesRunData(message: string): boolean {
  const m = String(message || '');
  return /\[(?:Uploaded datasets?|Attached files?|Galaxy dataset):/i.test(m) || RUN_DATA_ACCESSION_RE.test(m);
}

/** True when the user explicitly asked to proceed without supplying data
 *  (demo / synthetic / "use defaults" / "don't ask") — the reply must not ask for it. */
export function messageWaivesDataAsk(message: string): boolean {
  return /do not ask|don'?t ask|no (further )?clarification|use (the )?provided|use (the )?defaults?|with defaults|default parameters|\bdemo\b|\bmock\b|synthetic data|example data|sample data|built-in demo|just run it|演示|示例数据|默认参数/i
    .test(String(message || ''));
}
