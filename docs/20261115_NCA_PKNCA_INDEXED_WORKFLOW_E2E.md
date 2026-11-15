# NCA / `nca_pknca` indexed workflow E2E (2026-11-15)

**Verdict: PASS (primary criteria)** — catalogue routed to `nca_pknca`, AWS Batch / Nextflow launched, and `nca_results.csv` was produced and staged. Overall run status on the first E2E was **failed** because step 3 (`NCA_REPORT_HTML`) hit a Nextflow GString bug; PKNCA analysis itself succeeded. **Fix shipped** (same day): escape R `$` in the report process script so Groovy no longer interpolates `opts_chunk$set` / `info$dose` / etc.

| Field | Value |
|-------|-------|
| **pass/fail** | **PASS** on route + launch + `nca_results.csv`; report-step GString root cause **fixed** (local Nextflow smoke `GSTRING_SMOKE_OK`) |
| **runId** | `35e0b532-2c63-432c-a2e4-9f941d73bc7a` |
| **nextflowRunId** | `442bf75a-13fd-4374-80f6-53b17ac3099e` |
| **tip** | `cb472efe5c13d798b67e02aa642e088e1bdf9847` (`build-info.json`) |
| **BASE_URL** | `https://dev-public.biomate.ai` |
| **fixture user** | `lifeifei163361@163.com` (password from `E2E_FIXTURE_PASSWORD` / `~/.config/biomate/e2e_fixture_password`) |
| **elapsed** | ~148 s to terminal |

Gate prerequisite: tip includes `3303372c04` (`.ga` import gated behind `GA_IMPORT_ENABLED=false`) via merge `cb472efe5c`. No competing sync started for this test.

---

## What was tested

Indexed catalogue workflow **`nca_pknca`** (`drug_discovery/nca_pknca/main.nf`) via BioMate production path:

1. `POST /api/ai_assistant/generate_workflow` → route
2. `POST /api/datasets/upload` → stage concentration–time CSV
3. `POST /api/workflows/execute` → AWS Batch / Nextflow executor

Not chat `run_code` / local Rscript.

---

## Test dataset

Prior benchmark fixture from docs (`docs/20260417_DRUG_DISCOVERY_7_WORKFLOW_FIXES.md`, tutorials `test-data/pk_concentration_time.csv`):

- Canonical S3: `s3://biomate-nextflow-work/test-data/pk_concentration_time.csv`
- This run used a fixture-user upload of that same CSV:
  - `dataset_id`: `81fed4ca-e929-4007-8c98-4515d8d19aec`
  - `input_csv`: `s3://biomate-nextflow-work/uploads/81fed4ca-e929-4007-8c98-4515d8d19aec/pk_concentration_time.csv`
- Shape: 2 subjects × oral 100 mg concentration–time points (`subject_id,time,conc,dose,route`)

---

## Routing

| Check | Result |
|-------|--------|
| generate_workflow HTTP | 200 |
| `workflow_ga.name` | `Nca Pknca` |
| `nextflow_path` | `nextflow_nfcore/subworkflows/drug_discovery/nca_pknca/main.nf` |
| execute `workflowName` | `nca_pknca` |
| `executionEngine` | `nextflow` |

---

## Execution / artifacts

**Steps 1–2 succeeded** (Nextflow stats: `succeededCount=2`):

| Artifact | S3 (outdir `…/9cd8b24a/`) |
|----------|---------------------------|
| `validated_conc_time.csv` | `01_validation/` |
| `nca_results.csv` | `02_nca_analysis/` |
| `nca_summary.json` | `02_nca_analysis/` |
| `qc_metrics.json` | `02_nca_analysis/` |

Copied evidence: `docs/qa/20261115-nca-pknca-e2e/`.

### `nca_results.csv` (staged)

```csv
subject_id,AUClast,Cmax,Tmax,t_half,AUCinf,dose,route
S001,804.9425608777908,95.4,2,7.3326808391140945,866.758870424678,100,extravascular
S002,758.4126622018664,91.2,2,7.163115869110678,811.158973910119,100,extravascular
```

### QC (process `NCA_PKNCA_ANALYSIS`)

- PKNCA **0.12.1**, linear-up / log-down
- `auc_extrap_pct_max` ≈ 7.13% → `auc_extrap_within_20pct=true`
- terminal-slope coverage 100%
- evidence tier: `GOLD-auc_extrap / SILVER-terminal_slope`

---

## Failure (report step only) — root cause

**Status (run `35e0b532-…`):** `failed`  
**errorMessage:** `Process NCA_REPORT_HTML (nca_report) failed: No such variable: set -- Check script '[path]' at line: 389`

`NCA_REPORT_HTML` uses a Nextflow `"""` GString script that embeds R markdown / R `$` accessors inside a Python heredoc, e.g.:

- `knitr::opts_chunk$set(...)` → Groovy sees `$set`
- `smry$study_info`, `info$dose`, … → same class of GString interpolation

The process never reached Batch container execution for the report; template evaluation failed. No local R workaround was used.

---

## Fix (2026-11-15) — escape R `$` in `NCA_REPORT_HTML`

**File:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/nca_pknca/main.nf`

Escaped all eight R `$` literals inside the report process `"""…"""` block (same pattern already used in `NCA_INPUT_VALIDATION` / `NCA_PKNCA_ANALYSIS`):

| Before (Groovy-interpolated) | After (literal `$` for R) |
|------------------------------|---------------------------|
| `knitr::opts_chunk$set(...)` | `knitr::opts_chunk\$set(...)` |
| `smry$study_info` | `smry\$study_info` |
| `info$dose` / `$route` / `$time_unit` / `$conc_unit` / `$auc_unit` / `$n_subjects` | `info\$…` |

**Local smoke:** extracted the fixed process, stubbed only the `rmarkdown::render` call, ran Nextflow 25.10.6 → process submitted, wrote `nca_report.Rmd` with literal `opts_chunk$set` / `smry$study_info` / `info$dose`, printed `GSTRING_SMOKE_OK`, exit 0. Confirms GString evaluation no longer raises `No such variable: set`.

Did **not** skip or gate the report step.

### Prediction (deploy)

After this tip lands on live, a re-run of the indexed `nca_pknca` path should get past `NCA_REPORT_HTML` template evaluation: Nextflow will emit literal R `$` into `nca_report.Rmd` (no `No such variable: set`), and the report process will proceed to container/Batch `rmarkdown::render` like the other NCA steps. PKNCA CSV/JSON behavior is unchanged; residual risk is only R/image/runtime for render, not GString.

---

## Scorecard vs success criteria

| Criterion | Result |
|-----------|--------|
| Routes to `nca_pknca` | ✅ |
| Run launches (Batch / Nextflow) | ✅ |
| Produces / stages `nca_results.csv` | ✅ |
| Clear Batch failure + root-cause if no artifact | n/a (artifact present); report-step failure documented + fixed |
| Report GString compiles (`\$` escape) | ✅ local smoke |
| No local R / pydeseq substitute | ✅ |
