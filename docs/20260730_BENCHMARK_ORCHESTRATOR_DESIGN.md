# Multi-Omics Benchmark — Backend Orchestrator Design

**Date:** 2026-07-30
**Decision (user):** implement the benchmark as a **backend orchestrator**, not a composed
nextflow workflow. The composed workflow ran the methods fine but its in-nextflow COMPARE
step was fragile (head-process kill on the long run). The orchestrator reuses the
individual method workflows — which already run flawlessly — and scores in Node.

---

## Concept
`benchmark = fan out to N individual method runs + score their clusters.csv`

1. **Fan-out:** for each USER-SELECTED method, submit a normal `/api/workflows/execute`
   run (the exact single-method bioc workflow that already works). Collect N child run IDs.
2. **Aggregate:** a status endpoint polls the N child runs (existing run-status).
3. **Score (on demand, when all children terminal):** fetch each completed child's
   `<method>_clusters.csv` (existing `output_files` → `s3_uri` → S3 read), parse
   `sample,cluster`, compute ARI + NMI vs an optional ground-truth label (or pairwise
   inter-method agreement if no label), rank → the report.

No composed workflow, no in-nextflow COMPARE, none of the four bugs that path hit.

## Endpoint
`POST /api/workflows/benchmark`
```jsonc
{
  "omics": ["s3://…/mrna.csv", "s3://…/methylation.csv", "s3://…/drugs.csv"],
  "methods": ["snf", "intnmf", "mcia"],        // USER-SELECTED subset (the key requirement)
  "labels": "s3://…/ighv_labels.csv",           // optional ground truth (sample,<label>)
  "n_clusters": 2,
  "projectId": "…", "name": "IGHV benchmark"    // optional
}
→ 200 { "benchmarkId": "bm_…", "children": [ {"method":"snf","runId":"…"}, … ] }
```
`GET /api/workflows/benchmark/:benchmarkId`
```jsonc
{
  "benchmarkId": "bm_…",
  "status": "running" | "scoring" | "completed" | "failed",
  "children": [ {"method":"snf","runId":"…","status":"completed"}, … ],
  "report":  [ {"method":"mofa2","ARI":0.80,"NMI":0.72,"n":188,"rank":1}, … ], // when scored
  "winner": "mofa2"
}
```

## Async / persistence decision — deliberately minimal
- Submitting N runs is instant (each `/execute` returns a runId immediately; the Batch
  work is async). So the POST does **not** block on completion — it returns the child IDs.
- **Persistence: in-memory `Map<benchmarkId, {method,runId}[]>`** for v1. Rationale: the
  child runs are already durably tracked in the DB (`getExecutionRun`); the benchmark is
  just a *grouping* + a scoring function. On restart the group is lost but the child runs
  aren't — and the client holds the child IDs in the POST response, so the status endpoint
  can also accept an explicit `?runs=id1,id2,…` fallback (stateless recompute). This avoids
  a new DB table. Promote to a `benchmarks` table only if cross-session persistence is needed.
- **Scoring is on-demand** in the GET handler (when all children terminal) — no background
  worker, no new queue. Idempotent: re-scores from the child outputs each call (cheap).

## Reuse map (no new infra)
| Need | Existing |
|---|---|
| submit a method run | `POST /api/workflows/execute` (routes.ts ~9544) |
| child run status | `getExecutionRun(runId)` → `execution.status` (routes.ts run-status ~10635) |
| child outputs (clusters.csv s3_uri) | `GET /api/workflows/runs/:id/output_files` (~11653) |
| read a cluster CSV from S3 | `@aws-sdk/client-s3` GetObjectCommand (already a dep; see server/s3-client) |
| ARI / NMI | port from `scripts/multiomics_metric_harness.py` (stdlib, ~30 lines TS) |

## Method → workflow path
```
snf          → nextflow_nfcore/subworkflows/bioconductor/snf_multiomics/main.nf
intnmf       → …/intnmf_multiomics/main.nf
mcia         → …/mcia_multiomics/main.nf
iclusterplus → …/iclusterplus_multiomics/main.nf
jive         → …/jive_multiomics/main.nf
mfa          → …/rgcca_multiomics/main.nf   (method is MFA)
```
Each emits `<method>_clusters.csv` (sample,cluster). MOFA2 is factor-output — a follow-up
(k-means its factors in the scorer) to add MOFA2 to the benchmark.

## What must be wired into routes.ts (minimal)
1. `import { registerBenchmarkOrchestrator } from './benchmark-orchestrator';`
2. One call `registerBenchmarkOrchestrator(app, { submitRun, getRun, getOutputFiles, readS3Text });`
   where the deps are thin adapters over the existing `/execute` handler, `getExecutionRun`,
   the output_files logic, and an S3 GetObject helper. (The draft exports both the register
   fn and the pure scorer so it's unit-testable without the server.)

## UI (per the "method-picker in the panel" decision)
- The panel shows the available methods as checkboxes (a `multiselect` param case) → the
  selected list becomes `methods` in the POST body.
- The returned `report` renders in the existing outputs/findings table (step-output-preview
  already renders CSV/JSON tables) — emit the report as a small CSV/JSON the panel shows.

Draft implementation: `frontend/server/benchmark-orchestrator.ts` (this commit's sibling file).
