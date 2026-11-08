// Multi-Omics Benchmark — backend ORCHESTRATOR (design: docs/20260730_BENCHMARK_ORCHESTRATOR_DESIGN.md)
//
// benchmark = fan out to N individual method runs (each a working single-method bioc
// workflow) + score their clusters.csv in Node. Reuses the /execute, run-status and
// output_files paths; NO composed nextflow workflow (that path's in-nextflow COMPARE was
// fragile). DRAFT — wire into routes.ts with: registerBenchmarkOrchestrator(app, deps).
//
// The user picks WHICH methods to compare (req.methods) — never an implicit "all".

import type { Express, Request, Response } from 'express';

// ------------------------------------------------------------------ method registry
export const BENCHMARK_METHOD_PATHS: Record<string, string> = {
  snf:          'nextflow_nfcore/subworkflows/bioconductor/snf_multiomics/main.nf',
  intnmf:       'nextflow_nfcore/subworkflows/bioconductor/intnmf_multiomics/main.nf',
  mcia:         'nextflow_nfcore/subworkflows/bioconductor/mcia_multiomics/main.nf',
  iclusterplus: 'nextflow_nfcore/subworkflows/bioconductor/iclusterplus_multiomics/main.nf',
  jive:         'nextflow_nfcore/subworkflows/bioconductor/jive_multiomics/main.nf',
  mfa:          'nextflow_nfcore/subworkflows/bioconductor/rgcca_multiomics/main.nf', // method = MFA
};
// clusters.csv basename each method publishes (for output_files matching)
const CLUSTER_FILE: Record<string, string> = {
  snf: 'snf_clusters.csv', intnmf: 'intnmf_clusters.csv', mcia: 'mcia_clusters.csv',
  iclusterplus: 'iclusterplus_clusters.csv', jive: 'jive_clusters.csv', mfa: 'mfa_clusters.csv',
};

// ------------------------------------------------------------------ pure scorer (unit-testable)
// Ported from scripts/multiomics_metric_harness.py (ari/nmi), stdlib only.
function comb2(v: number): number { return v < 2 ? 0 : (v * (v - 1)) / 2; }

export function ari(a: string[], b: string[]): number {
  const n = a.length; if (n < 2 || n !== b.length) return NaN;
  const tab = new Map<string, number>(), ca = new Map<string, number>(), cb = new Map<string, number>();
  for (let i = 0; i < n; i++) {
    tab.set(a[i] + '' + b[i], (tab.get(a[i] + '' + b[i]) || 0) + 1);
    ca.set(a[i], (ca.get(a[i]) || 0) + 1); cb.set(b[i], (cb.get(b[i]) || 0) + 1);
  }
  let idx = 0; tab.forEach(v => idx += comb2(v));
  let sa = 0; ca.forEach(v => sa += comb2(v));
  let sb = 0; cb.forEach(v => sb += comb2(v));
  const exp = (sa * sb) / comb2(n), mx = (sa + sb) / 2;
  return mx === exp ? 1 : (idx - exp) / (mx - exp);
}

export function nmi(a: string[], b: string[]): number {
  const n = a.length; if (n < 2 || n !== b.length) return NaN;
  const tab = new Map<string, number>(), ca = new Map<string, number>(), cb = new Map<string, number>();
  for (let i = 0; i < n; i++) {
    tab.set(a[i] + '' + b[i], (tab.get(a[i] + '' + b[i]) || 0) + 1);
    ca.set(a[i], (ca.get(a[i]) || 0) + 1); cb.set(b[i], (cb.get(b[i]) || 0) + 1);
  }
  const H = (c: Map<string, number>) => { let h = 0; c.forEach(v => { const p = v / n; h -= p * Math.log(p); }); return h; };
  let mi = 0;
  tab.forEach((nxy, key) => {
    const [x, y] = key.split('');
    mi += (nxy / n) * Math.log((nxy * n) / (ca.get(x)! * cb.get(y)!));
  });
  const denom = (H(ca) + H(cb)) / 2;
  return denom ? mi / denom : 1;
}

/** parse a clusters.csv (sample,cluster) text into a map */
export function parseClusters(text: string): Map<string, string> {
  const out = new Map<string, string>();
  const lines = text.split(/\r?\n/).filter(Boolean);
  for (let i = 1; i < lines.length; i++) {                 // skip header
    const cells = lines[i].split(',').map(s => s.trim().replace(/^["']|["']$/g, ''));
    if (cells.length >= 2 && cells[0]) out.set(cells[0], cells[1]);
  }
  return out;
}

/** parse a labels csv (sample,<label>) — second column is the label */
export function parseLabels(text: string): Map<string, string> {
  const out = new Map<string, string>();
  const lines = text.split(/\r?\n/).filter(Boolean);
  for (let i = 1; i < lines.length; i++) {
    const cells = lines[i].split(',').map(s => s.trim().replace(/^["']|["']$/g, ''));
    if (cells.length >= 2 && cells[0] && !['', 'NA', 'NaN'].includes(cells[1])) out.set(cells[0], cells[1]);
  }
  return out;
}

export interface BenchmarkScore {
  mode: 'ground_truth' | 'agreement';
  report: Array<{
    method: string; n: number; available_n: number; rank: number | null;
    status?: 'scored' | 'failed';
    ARI?: number | null; NMI?: number | null; mean_agreement?: number | null;
  }>;
  winner: string | null;
  reason: 'insufficient_methods' | 'insufficient_common_samples' | 'tied' | null;
  common_samples: string[];
}

/** Compare every method on the same cohort. Agreement measures consensus, not accuracy. */
export function scoreBenchmark(
  methodClusters: Record<string, Map<string, string>>,
  labels?: Map<string, string>,
): BenchmarkScore {
  const names = Object.keys(methodClusters);
  // An explicitly supplied empty label set must not silently switch scoring mode.
  const mode = labels !== undefined ? 'ground_truth' : 'agreement';
  const usable = (value: string | undefined) => value !== undefined && !['', 'NA', 'NaN'].includes(value.trim());
  const common = names.length ? [...methodClusters[names[0]].keys()].filter(sample =>
    names.every(name => usable(methodClusters[name].get(sample))) &&
    (labels === undefined || usable(labels.get(sample))),
  ).sort() : [];
  const reason = names.length < 2 ? 'insufficient_methods'
    : common.length < 2 ? 'insufficient_common_samples' : null;
  const vectors = names.map(name => common.map(sample => methodClusters[name].get(sample)!));
  const report: BenchmarkScore['report'] = names.map((method, i) => {
    const row = { method, n: common.length, available_n: methodClusters[method].size, rank: null };
    if (mode === 'ground_truth') {
      const truth = common.map(sample => labels!.get(sample)!);
      return { ...row, ARI: reason ? null : ari(vectors[i], truth), NMI: reason ? null : nmi(vectors[i], truth) };
    }
    const agreements = vectors.filter((_, j) => i !== j).map(other => ari(vectors[i], other));
    return { ...row, mean_agreement: reason ? null : agreements.reduce((sum, v) => sum + v, 0) / agreements.length };
  });
  if (reason) return { mode, report, winner: null, reason, common_samples: common };
  const value = (row: BenchmarkScore['report'][number]) => (mode === 'ground_truth' ? row.ARI : row.mean_agreement)!;
  report.sort((a, b) => value(b) - value(a));
  // Equal scores share rank; input ordering must never decide a scientific winner.
  report.forEach((row, i) => {
    row.rank = i > 0 && Math.abs(value(row) - value(report[i - 1])) <= 1e-12 ? report[i - 1].rank : i + 1;
  });
  const tied = report[1].rank === 1;
  return { mode, report, winner: tied ? null : report[0].method, reason: tied ? 'tied' : null, common_samples: common };
}

/**
 * Append explicit rows for methods that produced no clusters, so a PARTIAL
 * comparison report shows WHICH method failed instead of hiding it in
 * `coverage.missing_methods`. Failed rows carry null metrics and rank=null, so
 * they never enter ranking or winner selection (scoreBenchmark already decided
 * those over the scored methods only). Pure + unit-testable.
 */
export function withFailedMethodRows(
  score: BenchmarkScore,
  missingMethods: string[],
): BenchmarkScore['report'] {
  const failed = missingMethods.map(method => ({
    method, n: 0, available_n: 0, rank: null, status: 'failed' as const,
    ...(score.mode === 'ground_truth' ? { ARI: null, NMI: null } : { mean_agreement: null }),
  }));
  return [...score.report.map(r => ({ ...r, status: 'scored' as const })), ...failed];
}

// ------------------------------------------------------------------ orchestrator deps (injected)
export interface BenchmarkDeps {
  // submit a single method run; returns its runId (thin adapter over POST /api/workflows/execute)
  submitRun: (args: { name: string; nextflow_path: string; parameters: Record<string, any>; req: Request }) => Promise<string>;
  // current run status ('running' | 'completed' | 'succeeded' | 'failed' | 'error' | ...)
  getRun: (runId: string) => Promise<{ status: string } | null>;
  // list a run's output files → [{ name, s3_uri }]
  getOutputFiles: (runId: string, req: Request) => Promise<Array<{ name?: string; s3_uri?: string }>>;
  // read an s3://… (or local) text file
  readS3Text: (uri: string) => Promise<string>;
}

const TERMINAL = new Set(['completed', 'succeeded', 'failed', 'error', 'cancelled', 'canceled', 'blocked', 'skipped']);
const OK = new Set(['completed', 'succeeded']);

// v1 persistence: in-memory grouping (child runs are durably tracked in the DB; the
// benchmark is just a grouping + on-demand scorer). Client also gets child IDs in the POST
// response, and the GET accepts ?runs= for stateless recompute after a restart.
const _benchmarks = new Map<string, { methods: string[]; runIds: string[]; labels?: string }>();
let _seq = 0;

export function registerBenchmarkOrchestrator(app: Express, deps: BenchmarkDeps): void {
  // -------- fan-out --------
  app.post('/api/workflows/benchmark', async (req: Request, res: Response) => {
    try {
      const { omics, methods, labels, n_clusters, name } = (req.body || {}) as any;
      if (!Array.isArray(omics) || omics.length < 2) return res.status(400).json({ error: 'omics must be a list of ≥2 matrix paths' });
      const sel: string[] = Array.isArray(methods) ? methods.map((m: string) => String(m).toLowerCase()) : [];
      if (!sel.length) return res.status(400).json({ error: 'methods is required — the user selects which methods to compare' });
      if (new Set(sel).size !== sel.length) return res.status(400).json({ error: 'methods must be unique' });
      const bad = sel.filter(m => !BENCHMARK_METHOD_PATHS[m]);
      if (bad.length) return res.status(400).json({ error: `unknown methods: ${bad.join(', ')}`, available: Object.keys(BENCHMARK_METHOD_PATHS) });

      const children: Array<{ method: string; runId: string }> = [];
      for (const m of sel) {
        const params: Record<string, any> = { omics };
        if (n_clusters != null) params.n_clusters = n_clusters;
        const runId = await deps.submitRun({
          name: `${name || 'Benchmark'} — ${m}`,
          nextflow_path: BENCHMARK_METHOD_PATHS[m],
          parameters: params,
          req,
        });
        children.push({ method: m, runId });
      }
      const benchmarkId = `bm_${Date.now().toString(36)}_${_seq++}`;
      _benchmarks.set(benchmarkId, { methods: sel, runIds: children.map(c => c.runId), labels });
      res.json({ benchmarkId, children });
    } catch (e: any) {
      res.status(500).json({ error: 'benchmark_fanout_failed', detail: String(e?.message || e) });
    }
  });

  // -------- status + on-demand scoring --------
  app.get('/api/workflows/benchmark/:benchmarkId', async (req: Request, res: Response) => {
    try {
      const bid = req.params.benchmarkId;
      let grp = _benchmarks.get(bid);
      // stateless fallback: ?runs=method:runId,method:runId  (survives a restart)
      if (!grp && typeof req.query.runs === 'string') {
        const pairs = req.query.runs.split(',').map(s => s.split(':'));
        grp = { methods: pairs.map(p => p[0]), runIds: pairs.map(p => p[1]), labels: req.query.labels as string | undefined };
      }
      if (!grp) return res.status(404).json({ error: 'unknown benchmarkId (pass ?runs=method:runId,… to recompute)' });

      const children = await Promise.all(grp.methods.map(async (m, i) => {
        const runId = grp!.runIds[i];
        const r = await deps.getRun(runId).catch(() => null);
        return { method: m, runId, status: r?.status || 'unknown' };
      }));
      const allTerminal = children.every(c => TERMINAL.has(c.status));
      if (!allTerminal) return res.json({ benchmarkId: bid, status: 'running', children });

      // all done → fetch clusters for the OK ones + score
      const methodClusters: Record<string, Map<string, string>> = {};
      for (const c of children.filter(c => OK.has(c.status))) {
        const files = await deps.getOutputFiles(c.runId, req).catch(() => []);
        const want = CLUSTER_FILE[c.method];
        const hit = files.find(f => (f.s3_uri || '').endsWith(want) || (f.name || '') === want)
                 || files.find(f => (f.s3_uri || '').includes('_clusters.csv') && !(f.s3_uri || '').includes('_views'));
        if (hit?.s3_uri) {
          const txt = await deps.readS3Text(hit.s3_uri).catch(() => '');
          if (txt) methodClusters[c.method] = parseClusters(txt);
        }
      }
      let labels: Map<string, string> | undefined;
      if (grp.labels) {
        const text = await deps.readS3Text(grp.labels).catch(() => '');
        labels = parseLabels(text);
        if (!labels.size) return res.json({ benchmarkId: bid, status: 'failed', children, winner: null, error: 'labels_unavailable' });
      }

      const missingMethods = grp.methods.filter(method => !methodClusters[method]?.size);
      if (missingMethods.length === grp.methods.length) return res.json({
        benchmarkId: bid, status: 'failed', children, winner: null, error: 'no method produced clusters',
        coverage: { expected: grp.methods.length, observed: 0, missing_methods: missingMethods },
      });
      const score = scoreBenchmark(methodClusters, labels);
      const partial = missingMethods.length > 0;
      res.json({
        benchmarkId: bid, status: partial ? 'partial' : 'completed', children, ...score,
        report: withFailedMethodRows(score, missingMethods),
        winner: partial ? null : score.winner,
        reason: partial ? 'incomplete_method_coverage' : score.reason,
        coverage: { expected: grp.methods.length, observed: grp.methods.length - missingMethods.length, missing_methods: missingMethods },
      });
    } catch (e: any) {
      res.status(500).json({ error: 'benchmark_status_failed', detail: String(e?.message || e) });
    }
  });
}
