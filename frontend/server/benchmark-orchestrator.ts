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
  const n = a.length; if (n < 2) return NaN;
  const tab = new Map<string, number>(), ca = new Map<string, number>(), cb = new Map<string, number>();
  for (let i = 0; i < n; i++) {
    tab.set(a[i] + '' + b[i], (tab.get(a[i] + '' + b[i]) || 0) + 1);
    ca.set(a[i], (ca.get(a[i]) || 0) + 1); cb.set(b[i], (cb.get(b[i]) || 0) + 1);
  }
  let idx = 0; tab.forEach(v => idx += comb2(v));
  let sa = 0; ca.forEach(v => sa += comb2(v));
  let sb = 0; cb.forEach(v => sb += comb2(v));
  const exp = (sa * sb) / comb2(n), mx = (sa + sb) / 2;
  return mx === exp ? 0 : (idx - exp) / (mx - exp);
}

export function nmi(a: string[], b: string[]): number {
  const n = a.length; if (n < 2) return NaN;
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
  return denom ? mi / denom : 0;
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

/** score a set of method clusterings. If labels given → ARI/NMI ranked; else pairwise agreement. */
export function scoreBenchmark(
  methodClusters: Record<string, Map<string, string>>,
  labels?: Map<string, string>,
): { mode: 'ground_truth' | 'agreement'; report: any[]; winner: string | null } {
  const names = Object.keys(methodClusters);
  if (labels && labels.size) {
    const rows = names.map(m => {
      const clu = methodClusters[m];
      const common = [...clu.keys()].filter(s => labels.has(s));
      if (common.length < 2) return { method: m, ARI: NaN, NMI: NaN, n: common.length };
      const a = common.map(s => clu.get(s)!), b = common.map(s => labels.get(s)!);
      return { method: m, ARI: ari(a, b), NMI: nmi(a, b), n: common.length };
    }).sort((x, y) => (Number.isNaN(y.ARI) ? -9 : y.ARI) - (Number.isNaN(x.ARI) ? -9 : x.ARI))
      .map((r, i) => ({ ...r, rank: i + 1 }));
    return { mode: 'ground_truth', report: rows, winner: rows[0]?.method ?? null };
  }
  // no labels → mean pairwise inter-method agreement (consensus ranking)
  const mean: Record<string, number[]> = {}; names.forEach(m => (mean[m] = []));
  for (let i = 0; i < names.length; i++) for (let j = i + 1; j < names.length; j++) {
    const x = names[i], y = names[j];
    const common = [...methodClusters[x].keys()].filter(s => methodClusters[y].has(s));
    if (common.length < 2) continue;
    const v = ari(common.map(s => methodClusters[x].get(s)!), common.map(s => methodClusters[y].get(s)!));
    mean[x].push(v); mean[y].push(v);
  }
  const rows = names.map(m => ({
    method: m, mean_agreement: mean[m].length ? mean[m].reduce((s, v) => s + v, 0) / mean[m].length : 0,
  })).sort((a, b) => b.mean_agreement - a.mean_agreement).map((r, i) => ({ ...r, rank: i + 1 }));
  return { mode: 'agreement', report: rows, winner: rows[0]?.method ?? null };
}

// ------------------------------------------------------------------ orchestrator deps (injected)
export interface BenchmarkDeps {
  // submit a single method run; returns its runId (thin adapter over POST /api/workflows/execute)
  submitRun: (args: { name: string; nextflow_path: string; parameters: Record<string, any>; req: Request }) => Promise<string>;
  // current run status ('running' | 'completed' | 'succeeded' | 'failed' | 'error' | ...)
  getRun: (runId: string) => Promise<{ status: string } | null>;
  // list a run's output files → [{ name, s3_uri }]
  getOutputFiles: (runId: string) => Promise<Array<{ name?: string; s3_uri?: string }>>;
  // read an s3://… (or local) text file
  readS3Text: (uri: string) => Promise<string>;
}

const TERMINAL = new Set(['completed', 'succeeded', 'failed', 'error']);
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
        const files = await deps.getOutputFiles(c.runId).catch(() => []);
        const want = CLUSTER_FILE[c.method];
        const hit = files.find(f => (f.s3_uri || '').endsWith(want) || (f.name || '') === want)
                 || files.find(f => (f.s3_uri || '').includes('_clusters.csv') && !(f.s3_uri || '').includes('_views'));
        if (hit?.s3_uri) {
          const txt = await deps.readS3Text(hit.s3_uri).catch(() => '');
          if (txt) methodClusters[c.method] = parseClusters(txt);
        }
      }
      let labels: Map<string, string> | undefined;
      if (grp.labels) { const t = await deps.readS3Text(grp.labels).catch(() => ''); if (t) labels = parseLabels(t); }

      if (!Object.keys(methodClusters).length) return res.json({ benchmarkId: bid, status: 'failed', children, error: 'no method produced clusters' });
      const { mode, report, winner } = scoreBenchmark(methodClusters, labels);
      res.json({ benchmarkId: bid, status: 'completed', mode, children, report, winner });
    } catch (e: any) {
      res.status(500).json({ error: 'benchmark_status_failed', detail: String(e?.message || e) });
    }
  });
}
