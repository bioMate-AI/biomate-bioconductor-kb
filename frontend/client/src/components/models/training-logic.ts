/**
 * Helpers for the Models-panel training launcher.
 *
 * The metric table mirrors backend/lib/galaxy/ai/ml_training/plan.py
 * (_SUPERVISED_METRICS / _GENERATIVE_METRIC): only metrics the trainer actually
 * reports are offered, so a configured gate can never fail closed on a metric
 * that is never produced. The backend re-validates every field.
 */

import { locale, t } from '@/lib/i18n';

export type LauncherFamily = 'general' | 'molecular';
export type FileKind = 'table' | 'h5ad' | 'structure' | 'other';
export type TaskType = 'classification' | 'regression';

/** Panel model choices. `ludwig_molecular` = ludwig_tabular + featurizer rdkit_2d.
 *  `chemprop_gnn` = message-passing GNN (same plan path as chat Train).
 *  Mirrors backend MODEL_TYPES (ml_training/config.py) — the panel must surface
 *  the FULL ML/DL set, not a subset. */
export type PanelModelType =
  | 'sklearn_tabular' | 'ludwig_tabular'
  | 'ludwig_llm' | 'trl_dpo' | 'trl_grpo'
  | 'scrna_diffusion' | 'protein_diffusion' | 'tabular_diffusion'
  | 'sklearn_gbr' | 'ludwig_molecular' | 'chemprop_gnn';

export const SUPERVISED_GENERAL: PanelModelType[] = ['sklearn_tabular', 'ludwig_tabular'];
export const MOLECULAR: PanelModelType[] = ['sklearn_gbr', 'ludwig_molecular', 'chemprop_gnn'];
export const LLM_TYPES: PanelModelType[] = ['ludwig_llm', 'trl_dpo', 'trl_grpo'];
/** Generative families — unsupervised (no target/metric gate). */
export const GENERATIVE: PanelModelType[] = ['scrna_diffusion', 'protein_diffusion', 'tabular_diffusion'];

export function isSupervised(type: PanelModelType): boolean {
  return SUPERVISED_GENERAL.includes(type) || MOLECULAR.includes(type);
}

export function fileKind(name: string): FileKind {
  const low = name.toLowerCase().replace(/\.gz$/, '');
  if (/\.(csv|tsv|tab|txt|jsonl|ndjson|parquet|pq)$/.test(low)) return 'table';
  if (low.endsWith('.h5ad')) return 'h5ad';
  if (/\.(pdb|cif|mmcif|ent)$/.test(low)) return 'structure';
  return 'other';
}

const SMILES_CHARS = /^[A-Za-z0-9@+\-[\]()=#$\\/.%*:]{4,}$/;
// A SMILES string has structure: a bond/branch/bracket character, or a ring that
// opens AND closes (c1ccccc1). Short identifiers like "c1" / "S1" / "TP53" have
// neither, so they are never mistaken for molecules.
const SMILES_STRUCTURE = /[=#()[\]]|([A-Za-z])(\d).*[A-Za-z]\2/;
// At least two organic-subset atoms, so ring-bearing gene/sample ids do not qualify.
const SMILES_ATOMS = /[BCNOPSFI]|Cl|Br|[bcnops]/g;

function nonEmpty(values: unknown[]): string[] {
  return values.map(v => (v === null || v === undefined ? '' : String(v).trim())).filter(v => v !== '');
}

/** Columns whose name says SMILES, or whose sampled values read as SMILES strings. */
export function detectSmilesColumns(columns: string[], sampleRows: unknown[][]): string[] {
  const named = columns.filter(col => /smiles|^smi$/i.test(col));
  const byValue = columns.filter((col, i) => {
    if (named.includes(col)) return false;
    const values = nonEmpty(sampleRows.map(r => r?.[i]));
    if (values.length < 2) return false;
    const hits = values.filter(v => SMILES_CHARS.test(v) && SMILES_STRUCTURE.test(v)
      && (v.match(SMILES_ATOMS) ?? []).length >= 2 && !/^-?\d+(\.\d+)?$/.test(v));
    return hits.length / values.length >= 0.8;
  });
  // A column NAMED smiles is the most reliable signal, so it is offered first.
  return [...named, ...byValue];
}

/** Suggest classification for non-numeric or few-valued labels, else regression. */
export function suggestTaskType(values: unknown[]): TaskType {
  const vals = nonEmpty(values);
  if (!vals.length) return 'classification';
  const numeric = vals.every(v => Number.isFinite(Number(v)));
  if (!numeric) return 'classification';
  // A fractional value (7.1, 0.35) is a measurement, never a class label.
  if (!vals.every(v => Number.isInteger(Number(v)))) return 'regression';
  const distinct = new Set(vals).size;
  if (distinct <= 2) return 'classification';
  if (distinct <= 10 && distinct < vals.length / 2) return 'classification';
  return 'regression';
}

export function columnValues(columns: string[], sampleRows: unknown[][], column: string): unknown[] {
  const i = columns.indexOf(column);
  return i < 0 ? [] : sampleRows.map(r => r?.[i]);
}

/** Columns that read as free-text (natural-language), so text-generation trainers
 *  (LLM SFT / DPO / GRPO) can be offered by CONTENT rather than by requiring exact
 *  header names. A value is text when it is non-numeric and either contains
 *  whitespace or is long (≥20 chars); a column qualifies when ≥60% of its sampled
 *  values are text. Short categorical labels and numeric columns never qualify. */
export function detectTextColumns(columns: string[], sampleRows: unknown[][]): string[] {
  return columns.filter((col, i) => {
    const values = nonEmpty(sampleRows.map(r => r?.[i]));
    if (values.length < 2) return false;
    const textish = values.filter(v => !/^-?\d+(\.\d+)?$/.test(v) && (/\s/.test(v) || v.length >= 20));
    return textish.length / values.length >= 0.6;
  });
}

/** Model types offered for a dataset. Surfaces the FULL backend set, filtered to
 *  what the file can actually train:
 *   - molecular family → SMILES-based molecular learners
 *   - h5ad → single-cell diffusion; structure files → protein diffusion
 *   - any feature table → supervised tabular learners + generative tabular diffusion
 *   - a table with free-text columns → LLM SFT / RL (GRPO), and DPO when ≥2 text
 *     columns exist; the column ROLES are chosen in the spec (dropdowns of real
 *     columns), not by requiring literal prompt/chosen/rejected headers. */
export function availableModelTypes(family: LauncherFamily, kind: FileKind, columns: string[],
  smilesColumns: string[], sampleRows: unknown[][] = []): PanelModelType[] {
  if (family === 'molecular') return kind === 'table' && smilesColumns.length ? MOLECULAR : [];
  if (kind === 'h5ad') return ['scrna_diffusion'];
  if (kind === 'structure') return ['protein_diffusion'];
  if (kind !== 'table' || columns.length < 2) return [];
  const out: PanelModelType[] = [...SUPERVISED_GENERAL, 'tabular_diffusion'];
  // LLM SFT maps its instruction/output columns in the spec (configurable in the
  // backend LLMSpec), so it is offered whenever the table carries free text.
  if (detectTextColumns(columns, sampleRows).length >= 1) out.push('ludwig_llm');
  // DPO/GRPO read literally-named columns (backend datasets.load_prompt_rows /
  // load_preference_rows require them), so they are offered only when those exist
  // — never a broken option. (Backend column-mapping is a separate follow-up.)
  if (columns.includes('prompt')) out.push('trl_grpo');
  if (['prompt', 'chosen', 'rejected'].every(c => columns.includes(c))) out.push('trl_dpo');
  return out;
}

const SUPERVISED_METRICS: Record<string, Record<TaskType, string[]>> = {
  sklearn_tabular: { classification: ['accuracy', 'macro_f1', 'auc'], regression: ['r2', 'mae'] },
  ludwig_tabular: { classification: ['accuracy'], regression: ['mae'] },
  ludwig_molecular: { classification: ['auc', 'accuracy'], regression: ['mae'] },
  sklearn_gbr: { classification: ['auc'], regression: ['mae'] },
  chemprop_gnn: { classification: ['auc', 'accuracy'], regression: ['mae', 'rmse'] },
};

export function metricsFor(type: PanelModelType, task: TaskType): string[] {
  return SUPERVISED_METRICS[type]?.[task] ?? [];
}

/** Lower is better for error metrics; the gate is a ceiling for these. */
export function metricIsCeiling(metric: string): boolean {
  return metric === 'mae';
}

/** Map the panel choice onto the backend plan's model_type + featurizer. */
export function backendModelType(type: PanelModelType): { model_type: string; featurizer?: string } {
  if (type === 'ludwig_molecular') return { model_type: 'ludwig_tabular', featurizer: 'rdkit_2d' };
  if (type === 'ludwig_tabular') return { model_type: 'ludwig_tabular', featurizer: 'none' };
  return { model_type: type };
}

/** Language-neutral default model name: <file stem>-<target>. */
export function defaultModelName(fileName: string, target: string): string {
  const stem = fileName.replace(/\.gz$/i, '').replace(/\.[^.]+$/, '');
  return target ? `${stem}-${target}` : stem;
}

export const TERMINAL_STATUSES = new Set(['completed', 'failed', 'cancelled', 'canceled', 'succeeded', 'error', 'interrupted']);

/** Known run states. 'interrupted' is written by the orphan finalizer when a
 *  run's process vanished (not in the run-status schema, but on real records). */
const RUN_STATUSES = ['queued', 'configuring', 'running', 'paused', 'completed', 'succeeded',
  'failed', 'cancelled', 'canceled', 'error', 'interrupted'];

/** A run status string → its localized label. An unrecognised state is shown as
 *  unknown — never as "queued", which claimed a dead run was about to start. */
export function runStatusLabel(status: string): string {
  const key = String(status || '').toLowerCase();
  return t(`models.run_status_${RUN_STATUSES.includes(key) ? key : 'unknown'}`);
}

/** "2026-11-11T07:24:09.433Z" → the viewer's local date-time in the UI language. */
export function formatRunTime(value: string, lang: string = locale): string {
  const date = new Date(value);
  if (!value || Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(lang === 'zh' ? 'zh-CN' : lang, {
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit',
  });
}

/**
 * Open the chat page's Run Manager listing runs from all chats.
 *
 * The Run Manager persists its open state and scope in localStorage
 * (chat-with-artifacts.tsx: biomate-run-manager-open / -scope) and has no
 * per-run deep link, so a panel-launched run is shown by opening the manager on
 * the all-chats scope, where the run is listed. Storage can be unavailable
 * (private mode); navigation still happens. Callers should label the control as
 * opening Run Manager (not as ejecting the user from Models).
 */
export function openRunManager(navigate: (url: string) => void = url => window.location.assign(url)): void {
  try {
    localStorage.setItem('biomate-run-manager-open', 'true');
    localStorage.setItem('biomate-run-manager-scope', 'all_chats');
  } catch { /* storage unavailable — the manager can still be opened by hand */ }
  navigate('/');
}

/** Fewest data rows a training run can use — mirrors MIN_TRAIN_ROWS in
 *  backend galaxy/ai/ml_training/plan.py, which enforces it server-side. */
export const MIN_TRAIN_ROWS = 10;

/** CSV/TSV-style files, where one row is one sample (the row floor applies). */
export function isDelimitedTable(name: string): boolean {
  return /\.(csv|tsv|txt)(\.gz)?$/i.test(name);
}
