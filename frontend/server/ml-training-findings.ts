/**
 * Deterministic findings for ml_training runs.
 *
 * The trainer always writes results/metrics.json ({metrics:{…}, gate:{…}}).
 * The LLM findings path previously preferred Ludwig bookkeeping
 * (model_hyperparameters.json, training_set_metadata.json) and produced
 * architecture fluff that omitted the actual test/val scores — while those
 * scores were already listed clearly in Outputs.
 *
 * Rule first: parse metrics.json (+ optional progress / manifest). LLM only
 * as a fallback when this returns null.
 */
import { summarizeTrainingMetrics, type TrainingSummary } from './model-training-activity';

export interface EvidenceFile { name: string; content: string }

export interface MlTrainingFindings {
  summary: string;
  key_results: Array<{
    metric: string;
    value: string;
    interpretation: string;
    source_file: string;
  }>;
  next_steps: string[];
  caveats: string[];
  evidence_version: 'ml-training-metrics-v1';
}

const METRIC_LABELS: Record<string, string> = {
  test_mae: 'Test MAE',
  val_mae: 'Validation MAE',
  mae: 'MAE',
  test_rmse: 'Test RMSE',
  val_rmse: 'Validation RMSE',
  rmse: 'RMSE',
  test_r2: 'Test R²',
  val_r2: 'Validation R²',
  r2: 'R²',
  accuracy: 'Accuracy',
  auc: 'AUC',
  macro_f1: 'Macro F1',
  f1: 'F1',
  pr_auc: 'PR-AUC',
  cv_accuracy_mean: 'CV accuracy (mean)',
};

function fmt(n: number): string {
  if (!Number.isFinite(n)) return String(n);
  const a = Math.abs(n);
  if (a >= 100 || a === 0) return n.toFixed(3).replace(/\.?0+$/, '') || '0';
  if (a >= 1) return n.toFixed(3);
  return n.toFixed(4);
}

function labelFor(name: string): string {
  if (METRIC_LABELS[name]) return METRIC_LABELS[name];
  return name.replace(/_/g, ' ');
}

/** Prefer the trainer's own metrics.json; accept basename anywhere in the path. */
export function findMetricsFile(files: EvidenceFile[]): EvidenceFile | null {
  const exact = files.find(f => /(^|\/)metrics\.json$/i.test(f.name));
  if (exact) return exact;
  return files.find(f => {
    try {
      const j = JSON.parse(f.content);
      return j && typeof j === 'object' && j.metrics && typeof j.metrics === 'object';
    } catch { return false; }
  }) || null;
}

function parseJson(file: EvidenceFile | undefined): Record<string, any> | null {
  if (!file) return null;
  try {
    const j = JSON.parse(file.content);
    return j && typeof j === 'object' ? j : null;
  } catch { return null; }
}

function progressR2(files: EvidenceFile[]): { split: string; r2: number; source: string }[] {
  const f = files.find(x => /training_progress\.json$/i.test(x.name));
  const j = parseJson(f || undefined);
  if (!j) return [];
  const out: { split: string; r2: number; source: string }[] = [];
  const blocks: Array<[string, any]> = [
    ['test', j.best_eval_test_metrics],
    ['validation', j.best_eval_validation_metrics],
    ['train', j.best_eval_train_metrics],
  ];
  for (const [split, block] of blocks) {
    const r2 = block?.combined?.r2 ?? block?.pIC50?.r2 ?? block?.r2;
    if (typeof r2 === 'number' && Number.isFinite(r2)) {
      out.push({ split, r2, source: f!.name });
    }
  }
  return out;
}

function splitInfo(files: EvidenceFile[]): {
  method?: string; n_train?: number; n_val?: number; n_test?: number; source: string
} | null {
  const f = files.find(x => /(^|\/)manifest\.json$/i.test(x.name))
    || files.find(x => {
      try {
        const j = JSON.parse(x.content);
        return j?.extra?.split && typeof j.extra.split === 'object';
      } catch { return false; }
    });
  const j = parseJson(f || undefined);
  const split = j?.extra?.split;
  if (!split || typeof split !== 'object') return null;
  return {
    method: typeof split.method === 'string' ? split.method : (typeof split.requested === 'string' ? split.requested : undefined),
    n_train: typeof split.n_train === 'number' ? split.n_train : undefined,
    n_val: typeof split.n_val === 'number' ? split.n_val : undefined,
    n_test: typeof split.n_test === 'number' ? split.n_test : undefined,
    source: f!.name,
  };
}

/**
 * True when a persisted findings sidecar looks like architecture fluff that
 * missed the trainer metrics — safe signal to regenerate for ml_training runs.
 *
 * Delegates to the cross-workflow hollow/fluff detector so the class stays closed
 * even when callers forget the isModelTrainingRun gate.
 */
export function looksLikeMlTrainingFluff(findings: unknown): boolean {
  // Lazy require avoided — keep this module free of circular imports by inlining
  // the same predicates as findings-quality.looksLikeHollowFindings (kept in sync
  // by findings-quality.test.ts + ml-training-findings.test.ts).
  if (!findings || typeof findings !== 'object') return false;
  const f = findings as Record<string, any>;
  const rows = Array.isArray(f.key_results) ? f.key_results : [];
  const fluff = rows.some((k: any) =>
    /combiner|hyperparameter|training set (mean|standard)|dropout rate|outlier threshold|activation function|fully connected layers|model_hyperparameters|training_set_metadata/i
      .test(`${k?.metric || ''} ${k?.interpretation || ''} ${k?.source_file || ''}`));
  const admitsMissing = (Array.isArray(f.caveats) ? f.caveats : [])
    .some((c: unknown) => /no model training or validation performance metrics|no .*metrics (are|were) present|could not find .*metric/i.test(String(c)));
  const summaryFluff = /combiner layer|multimodal input|z-score standardization|deep learning framework/i
    .test(String(f.summary || ''));
  const emptyRedirect = rows.length === 0
    && /see (the )?outputs|open .*in outputs|retrieve the metrics/i.test(String(f.summary || ''));
  return fluff || admitsMissing || summaryFluff || emptyRedirect;
}

export function parseMlTrainingFindings(
  files: EvidenceFile[],
  workflowName = 'Model training',
): { context: string; numbers: Set<string>; findings: MlTrainingFindings } | null {
  const metricsFile = findMetricsFile(files);
  if (!metricsFile) return null;
  let doc: Record<string, any>;
  try { doc = JSON.parse(metricsFile.content); } catch { return null; }
  if (!doc || typeof doc !== 'object' || !doc.metrics || typeof doc.metrics !== 'object') return null;

  const metrics = doc.metrics as Record<string, unknown>;
  const headline: TrainingSummary | null = summarizeTrainingMetrics(doc);
  const key_results: MlTrainingFindings['key_results'] = [];
  const numbers = new Set<string>();

  // Hold-out scores FIRST so Findings headline chips (top 3) and report tables
  // lead with what users actually need — not the gate row.
  const metricNames = Object.keys(metrics).filter(k => typeof metrics[k] === 'number');
  const order = (a: string, b: string) => {
    const rank = (k: string) =>
      (/^test_/.test(k) ? 0 : /^val_/.test(k) ? 1 : METRIC_LABELS[k] ? 2 : 3);
    return rank(a) - rank(b) || a.localeCompare(b);
  };
  for (const name of metricNames.sort(order)) {
    const raw = metrics[name] as number;
    const value = fmt(raw);
    numbers.add(String(raw));
    key_results.push({
      metric: labelFor(name),
      value,
      interpretation: /^test_/i.test(name)
        ? `Hold-out test performance (${name})`
        : /^val_/i.test(name)
          ? `Validation performance (${name})`
          : `Trainer-reported ${name}`,
      source_file: metricsFile.name,
    });
  }

  // Enrich with R² from Ludwig training_progress when metrics.json only has MAE.
  for (const row of progressR2(files)) {
    if (key_results.some(k => k.metric.toLowerCase().includes(`${row.split} r`))) continue;
    const value = fmt(row.r2);
    numbers.add(String(row.r2));
    key_results.push({
      metric: `${row.split[0].toUpperCase()}${row.split.slice(1)} R²`,
      value,
      interpretation: `Best-checkpoint R² on the ${row.split} split`,
      source_file: row.source,
    });
  }

  const split = splitInfo(files);
  if (split) {
    const parts = [
      split.method,
      split.n_train != null ? `train=${split.n_train}` : null,
      split.n_val != null ? `val=${split.n_val}` : null,
      split.n_test != null ? `test=${split.n_test}` : null,
    ].filter(Boolean);
    if (parts.length) {
      key_results.push({
        metric: 'Data split',
        value: parts.join(' · '),
        interpretation: 'Scaffold-aware / holdout separation used for training',
        source_file: split.source,
      });
    }
  }

  // Gate last (Train-runs list still reads gate from metrics.json directly).
  const gate = Array.isArray(doc.gate?.gates) ? doc.gate.gates.find((g: any) => g && typeof g.measured === 'number') : null;
  if (gate) {
    const measured = fmt(gate.measured);
    numbers.add(String(gate.measured));
    if (typeof gate.threshold === 'number') numbers.add(String(gate.threshold));
    key_results.push({
      metric: `Gate · ${labelFor(String(gate.name))}`,
      value: measured,
      interpretation: gate.status === 'pass'
        ? `Passed gate (threshold ${gate.threshold ?? 'n/a'}, ${gate.direction || 'higher_is_better'})`
        : gate.status === 'fail'
          ? `Failed gate (threshold ${gate.threshold ?? 'n/a'}, ${gate.direction || 'higher_is_better'})`
          : `Gate status: ${gate.status ?? 'unknown'}`,
      source_file: metricsFile.name,
    });
  }

  if (!key_results.length) return null;

  // Lead with the hold-out scores users care about; gate status is secondary.
  const headlineBits: string[] = [];
  const pushMetric = (key: string, label: string) => {
    if (typeof metrics[key] === 'number') headlineBits.push(`${label}=${fmt(metrics[key] as number)}`);
  };
  pushMetric('test_mae', 'test MAE');
  pushMetric('val_mae', 'validation MAE');
  pushMetric('test_rmse', 'test RMSE');
  pushMetric('val_rmse', 'validation RMSE');
  pushMetric('test_r2', 'test R²');
  pushMetric('r2', 'R²');
  pushMetric('accuracy', 'accuracy');
  pushMetric('auc', 'AUC');
  if (!headlineBits.length && headline) {
    headlineBits.push(`${labelFor(headline.metric)}=${fmt(headline.value)}`);
  }
  if (headline?.gate) headlineBits.push(`gate ${headline.gate}`);

  const name = (typeof doc.name === 'string' && doc.name.trim()) || workflowName;
  const summary = headlineBits.length
    ? `${name} finished. Key scores: ${headlineBits.join('; ')}. Read the Key Results table below (sourced from metrics.json); full artifacts remain in Outputs.`
    : `${name} finished. Trainer metrics are listed in Key Results (from metrics.json). Full artifacts remain in Outputs.`;

  const next_steps = [
    'Open metrics.json in Outputs for the authoritative score table.',
    'If the gate failed, adjust features / split / model type and re-train.',
    'Register the model from Train runs when the gate passes and you want it reusable.',
  ];
  const caveats = [
    'Scores are read directly from the trainer metrics.json (and optional training_progress / manifest), not inferred.',
    'Hold-out metrics can still overstate real-world performance — validate on an external set before deployment.',
  ];

  const findings: MlTrainingFindings = {
    summary,
    key_results: key_results.slice(0, 24),
    next_steps,
    caveats,
    evidence_version: 'ml-training-metrics-v1',
  };

  const contextLines = [
    `### Model training results — ${name}`,
    ...findings.key_results.map(k => `${k.metric}: ${k.value}`),
    ``,
    `Source file: ${metricsFile.name}`,
  ];

  return { context: contextLines.join('\n'), numbers, findings };
}
