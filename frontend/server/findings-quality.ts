/**
 * Cross-workflow findings quality gates.
 *
 * Class of bug closed here: LLM (or a stale S3 sidecar) narrates bookkeeping /
 * architecture / "metrics missing" prose while the real scores already sit in
 * structured output files. ml_training was the first instance; ADMET already
 * had a deterministic parser; DESeq2/enrichGO/variant still funnel through the
 * descriptor → document path. These helpers are shared by sampling rank,
 * sidecar refuse-fluff, and report download.
 */

/** Rank an output filename so result-bearing files are sampled before noise. */
export function scoreFindingsSampleName(name: string): number {
  const n = name.toLowerCase();
  let s = 0;
  // Trainer / structured score cards
  if (/(^|\/)metrics\.json$/.test(n) || /(^|\/)manifest\.json$/.test(n)) s += 10;
  if (/(^|\/)training_progress\.json$/.test(n)) s += 8;
  if (/(toxicity_report|predict_admet|deseq2|de_results|enrichgo|enrich_go|multiqc)/.test(n)) s += 8;
  if (/(report|summary|result|finding|final|metric|stat|score|predict|analysis|toxic|qc|vina|docking)/.test(n)) s += 3;
  if (/\.(json|tsv|csv)$/.test(n)) s += 2;
  if (/\.(txt|md)$/.test(n)) s += 1;
  // Ludwig / false-QC / Nextflow bookkeeping — demote so they never crowd out scores
  if (/(model_hyperparameters|training_set_metadata|qc_events)/.test(n)) s -= 6;
  if (/(\.nextflow\.log|_trace|_timeline|_report|\bdag\b|execution_)/.test(n)) s -= 5;
  return s;
}

/**
 * True when a persisted findings object looks like architecture / bookkeeping
 * fluff that missed the real scores — safe signal to regenerate.
 *
 * Not limited to ml_training: any run whose sidecar admits "no metrics" or
 * elevates Ludwig hyperparams / combiner prose is poison for the class.
 */
export function looksLikeHollowFindings(findings: unknown): boolean {
  if (!findings || typeof findings !== 'object') return false;
  const f = findings as Record<string, any>;
  const rows = Array.isArray(f.key_results) ? f.key_results : [];
  const fluffRow = rows.some((k: any) => {
    const blob = `${k?.metric || ''} ${k?.interpretation || ''} ${k?.source_file || ''}`;
    return /combiner|hyperparameter|training set (mean|standard)|dropout rate|outlier threshold|activation function|fully connected layers|model_hyperparameters|training_set_metadata/i
      .test(blob);
  });
  const admitsMissing = (Array.isArray(f.caveats) ? f.caveats : [])
    .some((c: unknown) => /no model training or validation performance metrics|no .*metrics (are|were) present|could not find .*metric/i.test(String(c)));
  const summaryFluff = /combiner layer|multimodal input|z-score standardization|deep learning framework/i
    .test(String(f.summary || ''));
  // Hollow: has a summary but zero key_results AND tells the user to go look in outputs
  // for the numbers it should have extracted.
  const emptyRedirect = rows.length === 0
    && /see (the )?outputs|open .*in outputs|retrieve the metrics/i.test(String(f.summary || ''));
  return fluffRow || admitsMissing || summaryFluff || emptyRedirect;
}
