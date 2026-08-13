# C5 — Productionize the cleaning QC gate as a BioMate auto-loop gate: ready plan

Date: 2026-08-12. Mechanism fully mapped; this is the exact, ready-to-execute plan. I stopped
short of deploying because it's a high-blast-radius core-executor change that can't be verified
without a live Batch run (review-before-expensive-deploy discipline).

## Mechanism (verified in code)
- QC gates are evaluated post-run by `_evaluate_qc_from_s3(run_id, s3_output_files,
  workflow_domain, qc_overrides)` in `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`
  (~line 2953). **It is hardcoded per-domain** — line 24: `if not (is_admet…) and not is_cryo:
  return []`. Only ADMET + CryoEM have gates today.
- Gate shape the auto-loop consumes: a metric dict `{name, measured, unit, threshold, pass}`;
  failing metrics (`pass=False`) become `gate_failures` → `_runs[run_id]["qc_gates"]` →
  surfaced to the frontend + drive the auto-loop (halt / advisory / remediation).
- The cleaner integration: the workflow emits a `qc_report.json` containing
  `{"_all_metrics":[{name,measured,threshold,pass}, …]}`; a new domain branch reads it.

## The two pieces to build

### (1) Cleaning subworkflow — `nextflow_nfcore/subworkflows/bioconductor/clean_and_verify/main.nf`
Follows the proven bioc pattern (container `bioc-domain-general:3.20-*`, R inline, runtime
Bioconductor install of `sva`). Inputs: expression matrix CSV (genes×samples) + metadata CSV
(sample, batch, condition), outdir. R does:
1. read + log2/normalize if raw;
2. PCA → condition-sep & batch-sep BEFORE;
3. `sva::ComBat(dat, batch, mod=model.matrix(~condition))` — **covariate-protected** ComBat
   (protecting the biological condition is the correct usage; the gate verifies it worked);
4. PCA → condition-sep & batch-sep AFTER; outlier flag (robust PCA distance);
5. write `cleaned_matrix.csv` + `qc_report.json` with `_all_metrics`:
   - `{"name":"Biology conservation (post-clean)","measured": cs_after/cs_before,
      "threshold":0.7,"pass": ratio>=0.7}`  ← the over-correction gate
   - `{"name":"Batch removal","measured": bs_after,"threshold":0.15,"pass": bs_after<=0.15}`
   - `{"name":"Outlier samples","measured": n_outliers,"threshold":…,"pass":…}`
Contract validated locally against the real algorithm in `scripts/clean_and_verify_qc_proofpoint.py`
(clean=TRUSTED, confounded=OVER-CORRECTED) and the C4 battery (`scripts/qc_battery.py`).

### (2) Executor gate branch — additive, low-risk (`_evaluate_qc_from_s3`)
Add alongside the ADMET/cryo branches (returns `[]` for other domains, so ZERO impact on
existing gates):
```python
is_preproc = any(k in domain_upper for k in ("PREPROC","CLEANING","QC_CLEAN"))
is_preproc_files = any(f.get("filename","").endswith("qc_report.json") for f in s3_output_files)
if is_preproc or is_preproc_files:
    qc = _load_json_from_s3(s3_output_files, "qc_report.json")     # small helper
    return [ {"name":m["name"],"measured":m["measured"],"threshold":m["threshold"],
              "severity":"halt" if m["name"].startswith("Biology") else "advisory"}
             for m in (qc or {}).get("_all_metrics",[]) if not m.get("pass",True) ]
```
Biology-conservation failure = `halt` → auto-loop remediation (e.g. "ComBat erased the
condition signal — design is confounded; protect the covariate or don't batch-correct").

### (3) Register + deploy
- Insert the workflow row (domain=`preprocessing`) into `galaxy_ai_tools.db` (dev + S3 canonical).
- **Pre-sync checklist** (mandatory): `cd frontend && npx tsc --noEmit`; `npx vitest run`;
  `cd backend && PYTHONPATH=lib python3.9 -c "import galaxy.webapps.galaxy.api.nextflow_executor"`
  (catches the executor edit's load errors in 3 s — the 2026-06-03 crash-loop lesson).
- `scripts/sync_to_dev.sh` (from main repo /Users/kky/biomate on next-phase only).
- E2E: submit `clean_and_verify` on a confounded matrix → expect `qc_gates` with a failed
  "Biology conservation" halt; submit a clean matrix → expect no gate failures.

## Why this is a deploy DECISION, not an autonomous step
- **Blast radius:** `_evaluate_qc_from_s3` is on the completion path of EVERY workflow run. A
  bug there breaks QC for ADMET/cryo/all. The branch is additive + guarded, but it is still an
  edit to a core file that cannot be verified without a live run.
- **Unverifiable locally:** the R subworkflow (sva/ComBat on Batch) and the executor branch only
  execute on dev; there is no local test. Firing blind = the forbidden "deploy to see if it works."
- **Sync scope:** `sync_to_dev.sh` deploys ALL of next-phase (frontend rebuild + galaxy) — needs
  a clean, intended branch state (concurrent-session churn risk).

## Recommendation
Everything above is specified and the verdict logic is validated locally. The remaining action
is a deliberate deployment: apply pieces (1)+(2), run the pre-sync checklist, sync, and do the
E2E run. That's the go/no-go — pull it when the branch state is clean and the Batch spend +
core-file deploy are intended, not in an autonomous loop.
