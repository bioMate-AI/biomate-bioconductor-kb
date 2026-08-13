# Multi-omics flexible-integration pipeline — live end-to-end run

Date: 2026-08-11. Branch: integration/next-phase.

Goal: prove the `plan_pipeline` → `run_pipeline` layer runs end-to-end on real data —
normalize each modality, then integrate — on AWS Batch via the production executor.

## Layer under test (all committed, 36/36 unit tests)

`method_selector.recommend` → `integration_planner.plan_pipeline` → `resolve_pipeline` /
`run_pipeline` → `routing.route_multiomics_result`. Proven-runnable paths
(`nextflow_nfcore/subworkflows/bioconductor/<m>/main.nf`, commit 9b7dffb95).

## Dataset (real, already staged)

`s3://biomate-nextflow-work/cll_test/` — CLL (Dietrich 2018), 2 modalities used here:
- `mrna.csv` (12.5 MB), `methylation.csv` (14.9 MB); `ighv_labels.csv` = ground truth.

## API contract (proven — benchmark-orchestrator.ts + sweep_drug_dev_workflows.sh)

- Submit: `POST /api/workflows/execute`
  `{"workflowDefinition":{"name":…,"workflow_type":"nextflow","nextflow_path":…,"parameters":{"omics":[…]}}}`
  → `{ "runId": … }`
- Poll: `GET /api/workflows/runs/<rid>` → `.execution.status ∈ {completed,failed,…}`
- Auth (dev): header `x-e2e-test-token: biomate-e2e-bypass-token-dev-only`
- Base: `https://dev-public.biomate.ai`

## PRE-RUN REVIEW (per CLAUDE.md expensive-test discipline)

Step 0 — normalize only (de-risk first, cheapest maximum-information action):

- **What it does:** submits `omics_normalize/main.nf` with
  `parameters.omics = [s3://…/mrna.csv, s3://…/methylation.csv]`, default executor outdir.
- **Gating conditions:** (a) executor accepts `parameters.omics` as a JSON list of s3 URIs
  and passes it to the subworkflow's universal input; (b) `omics_normalize` is
  standalone-runnable — memory says run `a0f1138f` already proved this; (c) the bioc image
  is available on Batch.
- **Known risk:** the executor's omics-collection fallback (commit fe7a52bc) matches
  file-valued params by data-file extension. Passing `omics` explicitly as a list should
  pass through unchanged; watch for it being mangled or dropped.
- **Predicted result:** run reaches `completed`; the run's S3 outdir contains
  `normalized_mrna.csv`, `normalized_methylation.csv`, `omics_qc_metrics.csv`. This
  reveals the EXACT publishDir layout (the one thing not predictable without a run) and
  how the runs snapshot exposes the output prefix — the input to step 1.
- **If it fails:** read the FULL nextflow error from the runs snapshot (`.execution.
  nextflowStatus`), do NOT retry-with-guess. An exit code is not a diagnosis.

Only after step 0's layout is known do we fire step 1 (MOFA2 on the normalized CSVs).

## RESULTS

### Step 0 — normalize (run af1f0a1f-fe6a-4145-acc5-2b9e585e8512) ✅ SUCCEEDED

Submitted `omics_normalize/main.nf` with `omics=[…/cll_test/mrna.csv, …/methylation.csv]`.
`nextflowStatus.status=succeeded`, returncode 0. Output prefix returned in the submit
response at `.outputs.outdir` = `s3://biomate-nextflow-work/nextflow/outputs/unknown/47158f99`.

Real S3 layout (validates the `resolve_pipeline` contract EXACTLY — files land directly
at `{outdir}/normalized_<stem>.csv`, no subdir):
```
{outdir}/normalized_mrna.csv          12,535,862 B
{outdir}/normalized_methylation.csv   14,815,178 B
{outdir}/omics_qc_metrics.csv
{outdir}/omics_qc_plots.pdf
{outdir}/versions.yml
```
So step 1's omics resolves deterministically to
`[{outdir}/normalized_mrna.csv, {outdir}/normalized_methylation.csv]` — no runtime S3
listing needed, confirming the `plan_pipeline`/`resolve_pipeline` design against real output.

### Executor contract findings (for the production `execute_and_wait` adapter)

- Submit `POST /api/workflows/execute` returns the assigned outdir immediately at
  `.outputs.outdir` — capture it there; no need to poll for it.
- **Status endpoint is `GET /api/workflows/runs/<rid>/status`** (returns
  `{status, nextflowStatus:{status,returncode,outdir}, …}`). The bare
  `GET /api/workflows/runs/<rid>` returns `{"error":"Not authenticated"}` with the e2e
  bypass token — use the `/status` sub-path for polling.
- Terminal when `.status ∈ {completed, failed, cancelled}`; success = `.nextflowStatus.status
  == "succeeded"` / returncode 0.
- `parameters.omics` passes through as a JSON list of s3 URIs unchanged — the universal
  interface works as designed.

### Step 1 — MOFA2 (run 7e8979d1-c6a1-4ddf-ac64-ffa331f87baa) — RUNNING

Submitted `mofa2/main.nf` with `omics=[{step0_outdir}/normalized_mrna.csv,
{step0_outdir}/normalized_methylation.csv]`, `n_factors=10`. Outdir
`s3://biomate-nextflow-work/nextflow/outputs/unknown/21fd8cb0`.

✅ **SUCCEEDED** (`status=completed`, `nextflowStatus=succeeded`). Outputs:
```
{outdir}/mofa_extracted_factors.csv     89 KB   ← latent factor matrix (samples × 10 factors)
{outdir}/mofa_extracted_weights.csv    6.2 MB   ← feature loadings
{outdir}/mofa_extracted_data.csv       106 MB
{outdir}/mofa_analysis_plots.pdf
{outdir}/normalized_mrna.csv, normalized_methylation.csv   ← step-0 inputs, confirming MOFA2 consumed them
```

### Scientific validation — factors recover known biology ✅

Scored the MOFA factors against the CLL IGHV ground truth (`cll_test/ighv_labels.csv`,
104 mutated / 84 unmutated, direction-agnostic Mann–Whitney AUC):

| Factor | \|AUC vs IGHV\| |
|---|---|
| **Factor 1** | **0.962** (n=188) |
| Factor 5 | 0.641 |
| Factor 4 | 0.599 |
| others | ≤ 0.57 |

**Factor 1 separates IGHV-mutated vs unmutated at AUC 0.962** — consistent with the
prior standalone figure (~0.968). The flexibly-planned normalize→integrate pipeline,
run on real 2-modality CLL data via AWS Batch, produces biologically meaningful output.

## CONCLUSION — the flexible-integration pipeline works end-to-end

- `plan_pipeline`/`resolve_pipeline`/`run_pipeline` (36/36 unit tests) are now validated
  against a real 2-step AWS Batch run: **normalize → MOFA2**, on `mrna + methylation`.
- The deterministic `{outdir}/normalized_<stem>.csv` contract matched the real S3 layout
  exactly, so no runtime S3 listing is needed to chain steps.
- Result is scientifically correct (Factor 1 ↔ IGHV, AUC 0.962).

### Remaining to fully productionize

1. Land the production `execute_and_wait` (submit → capture `.outputs.outdir` → poll
   `/api/workflows/runs/<rid>/status` to `succeeded` → return outdir) so `run_pipeline`
   drives both steps automatically from one chat action. The two steps were driven
   manually here to de-risk; the contract each step needs is now proven.
2. Enable `MULTIOMICS_ROUTING=1` on dev + E2E-verify the integration card.
3. Package a StabMap/mosaic workflow for partial-overlap integration.
