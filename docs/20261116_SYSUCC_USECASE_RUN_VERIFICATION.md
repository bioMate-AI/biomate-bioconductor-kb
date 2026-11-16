# SYSUCC Demo Use-Case Run Verification (2026-11-16)

Goal: make every Zhongshan/SYSUCC demo use case RUN FOR REAL in BioMate, verify
each end-to-end against the mandatory "outputs published & downloadable" gate, and
fix the blockers at root cause.

Source docs: `~/Desktop/business/zhongshan_sysucc_demo_usecases.md`,
`~/Desktop/business/biomate_demo_bugs_20261115.md`.

All runs were launched against `https://dev-public.biomate.ai` via
`POST /api/workflows/execute` (Bearer token from the fixture login), polled via
`GET /api/workflows/runs/{id}`, and the output gate was applied by fetching a real
file via `GET /api/runs/{id}/output/{filename}` (presigned-redirect download) and/or
`GET /api/workflows/runs/{id}/output_files`.

---

## Shared root-cause fix: output publishing (bug #2) — FIXED

**Symptom (bug #2):** a `succeeded`/exit-0 run shows `output_files: []` in
`get_run`/`analyze_results` even though the workflow produced files.

**Diagnosis (ground truth from live runs):**
- Output *publishing* is NOT universally broken. Workflows **with** a `publishDir`
  directive (e.g. MHC Binding) write to the S3 outdir and the completion path lists
  them fine → `s3_output_files` populated, download works.
- Workflows **without** `publishDir` (e.g. the bioconductor survival/**Cox** chain)
  stage their declared process outputs ONLY into `work/<hash>/` on S3 (by the Batch
  task's own `aws s3 cp`), never into the outdir.
- The in-memory completion path (`nextflow_executor.py` ~L6558) already has a
  **work-dir fallback** for this. BUT when a run is finalized by the **orphan poller**
  (common on dev with multi-worker gunicorn), the completion runs in
  `orphan_finalizer._finalize_orphaned_run_impl`, whose `_run_s3_qc` scanned **only
  the outdir** (`_list_s3_output_files(outdir)`), had **no work-dir fallback**, and
  **never persisted `s3_output_files`** to the run store (only `qc_gates`).
- Result: a no-publishDir workflow finalized via the orphan path persists an empty
  `s3_output_files` → the exact Cox `output_files: []` failure. (Confirmed live: Cox
  run `405c76c6…` succeeded, work dir held cox_coefficients.csv / cox_hazard_ratios.csv
  / cox_zph_test.csv / cox_zph_plots.pdf / cox_fit.rds, yet stored `s3_output_files=0`.)

**Fix** (`backend/lib/galaxy/ai/runs/orphan_finalizer.py`):
- New `_list_s3_outputs_with_fallback(run_record)`: scan outdir, then fall back to
  the Nextflow work dir (`_list_s3_work_output_files(workdir)`) when outdir is empty —
  mirroring the in-memory path.
- `finalize_orphaned_run` now lists outputs once (with fallback) and **persists
  `s3_output_files` to the store** so `get_run`/`analyze_results` see them.
- Regression tests added (`tests/test_orphan_finalizer.py`): work-dir outputs
  persisted when outdir empty; outdir preferred when non-empty. 12/12 pass.

Commit: `8ce52b2144`.

Note: even before this fix, the dedicated `GET /api/workflows/runs/{id}/output_files`
endpoint already recovers work-dir files via a live Galaxy scan, and the
`/api/runs/{id}/output/{filename}` download endpoint resolves them — so the mandatory
download gate PASSES for Cox today. The fix closes the remaining gap where the
*stored* status (what the Findings/analyze_results panel reads) stayed empty.

---

## Use-case-1 fix: EBV cfDNA MRD container (missing ECR image) — FIXED

EBV run `b9ed5d68…` failed at container start (1.1s, no `.exitcode`). Root cause:
the workflow's container `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/cfdna:x86`
**does not exist** (ECR `RepositoryNotFoundException`). The demo path needs python3
stdlib; the real-BAM path needs samtools.

**Fix:** repointed `genomics/ebv_cfdna_mrd` and `genomics/viral_genome_integration`
to `biomate/biomni-tools:x86` — the general bioinformatics image built from the same
micromamba recipe the missing image specified (`python=3.11` + `samtools` confirmed in
`Dockerfile.x86-comprehensive`). Commit `8ce52b2144`. Pending deploy + re-run to verify.

---

## Per-use-case status

| # | Use case | runId | Terminal | Output gate | Sci-validity | Self-correction | Fix |
|---|----------|-------|----------|-------------|--------------|-----------------|-----|
| 1 | EBV cfDNA MRD | b9ed5d68 (pre-fix) | failed → fix made | pending redeploy | — | EXECUTED (LoB/LoD gate inside QUANTIFY_MRD) | image repoint (committed) |
| 2 | Cox survival (EBV biomarker) | 405c76c6 (full), 7e6d4c0b (naive) | succeeded | **PASS** | **PASS** | **NARRATED** (bug#3 confirmed) | output-publish fix + S3 input |
| 3 | easier ICB response | c498a0f9 (pre-fix) | failed → fix made | pending redeploy | caveat (synthetic input) | likely NARRATED | dep fix (committed) |
| 4 | MHC Binding (vaccine epitopes) | bcf3e43e | completed | **PASS** | **PASS** | NARRATED (two-workflow re-route; class-II arm absent) | — |
| 5 | sarek somatic+TMB | not run | — | — | — | NARRATED (orchestrated 2-run) | cost-deferred |
| 6 | airrflow TCR/BCR | not runnable | — | — | — | — | **GAP: workflow absent from deploy** |
| 7 | spatial RCTD | not runnable | — | — | — | — | **GAP: workflow absent from deploy** |
| 8 | cyclic_peptide design | 9e3703bb | completed | **PASS** | research-stage (honest) | **EXECUTED** (validity gate 120→119) | — |

### UC2 — Cox survival (EBV-DNA-guided biomarker) — PASS
- Input: simulated NPC PD-1 cohort (220 pts, 119 events) with `biomarker` confounded by
  `ebv_dna_load` (the true prognostic driver), `stage`, `liver_met`; uploaded to S3.
- Output gate PASS — downloaded (HTTP 200, non-empty) `cox_hazard_ratios.csv`,
  `cox_coefficients.csv`, `cox_zph_test.csv`, `cox_zph_plots.pdf`, `cox_fit.rds`.
- Science: **naive** biomarker HR 1.167, p=**0.019** (significant) → **adjusted** biomarker
  HR 0.979, 95% CI 0.816–1.173, p=**0.815** (attenuated to null once EBV-DNA/stage/liver-met
  included). cox.zph GLOBAL p=**0.688** (PH assumption holds). Exactly the "looked
  significant until it adjusted for EBV-DNA load" story.
- Self-correction = **NARRATED / operator-driven**: I ran two separate models by hand. The
  workflow is a static `coxph → summary → cox.zph` chain — `cox.zph` is diagnostic-only, no
  QC gate, no auto-adjust loop (confirms bug #3; eval doc flagged this as the KNOWN GAP).

### UC4 — MHC Binding Prediction (vaccine epitopes) — PASS
- Ran zero-input (built-in demo peptides/alleles). `completed`, 8 outputs published to outdir.
- Output gate PASS — downloaded `mhc_binding_predictions.csv` (presigned 302 → S3, HTTP 200).
- Science PASS: a row per peptide×allele; GILGFVFTL/HLA-A*02:01 = **strong** (25.8 nM, 0.13 %rank),
  NLVPMVATV/HLA-A*02:01 = strong (34.7 nM) — correct canonical A2 epitopes; strong/weak flags
  consistent with the 2.0/10.0 %rank thresholds; 2 strong binders.
- Self-correction = **NARRATED** two-workflow re-route (MHCflurry is genuinely class-I only).
  **Gap:** the class-II re-route target `nf-core/epitopeprediction` is NOT in the deploy, so the
  CD4-help class-II arm can't be produced today (alternatives present: `immunology/
  bcell_epitope_immunogen`, `immunology/surface_epitope_mapping`, `immunology/antigen_resolution`).

### UC8 — cyclic_peptide_design — PASS (research-stage)
- Ran `modules/biomate-ai-tools/cyclic_peptide_design/main.nf` with ring 8–12, n=120,
  target_label=HPV16_HNSCC_adjacent_demo. `completed`, 8 outputs.
- Output gate PASS — downloaded `cyclic_peptides.csv` (119 designs: id, seq, mw, charge,
  hydrophobic_frac, score), `design_summary.json`, `constraints.json`.
- Self-correction = **EXECUTED** (real in-workflow gate): FILTER_MACROCYCLE took
  enumerated n=120 → valid n_out=**119** (1 blocked for violating charge/hydrophobicity
  constraints). This is a genuine validity gate firing inside the pipeline.
- **Honest gaps vs storyboard:** this deployed version is a **CPU rule-based constraint
  enumerator** (VALIDATE→ENUMERATE→FILTER→RANK), NOT the 5-phase CyclicMPNN+N-methylation+
  macrocycle-ADMET+AF3 GPU pipeline the use-case doc describes, and NOT structure-based binding
  to complement C5 (PDB 3CU7). The "~900 strings / 3× yield / Zenodo DOI" claim does not
  correspond to this workflow. **However**, bug #6's claim that it "exposes no params / runs
  only hardcoded autoimmune targets" is OUTDATED for this file — it ran fine with custom
  params (ring size, residues, charge, target_label) and zero required input. Output includes
  an explicit honesty note: "Rule-based enumeration + macrocycle heuristics; not measured
  affinity/ADMET."

### UC5 — sarek somatic + TMB — NOT RUN (cost-deferred)
- Runnable (stub present: `biomni_workflows/nfcore/sarek/main.nf`) but a tumor–normal WES run
  is multi-hour, heavy CPU/RAM. Per cost discipline, not executed in this pass. Reproducible
  config for a later run: SEQC2 **HCC1395 / HCC1395BL** tumor-normal, GRCh38 + GATK bundle,
  `analysis_type=somatic`, `tools=mutect2,strelka,manta,ascat`, `wes=true`. The output-publish
  fix above applies to it. Self-correction (tumor-only → tumor-normal/plasmut) is an
  orchestrated **two-run re-route**, not an in-sarek auto-gate → NARRATED.

### UC6 — airrflow TCR/BCR — NOT RUNNABLE AS SPECIFIED (gap)
- `nfcore/airrflow` is **absent** from this repo/deploy (no stub under `biomni_workflows/nfcore/`;
  airrflow not found anywhere in the checkout). Cannot be launched. Needs the airrflow pipeline
  stub to be added + validated before this demo can run.

### UC7 — spatial RCTD — NOT RUNNABLE AS SPECIFIED (gap)
- `biomni_workflows/spatial/spatial_deconvolution_rctd.nf` does **not exist** in the checkout.
  The only spatial-deconvolution workflow present is `bioconductor/demixt/
  demixnb_spatial_deconvolution.nf` (DeMixT, a different method, not RCTD). Needs the RCTD
  workflow to be added before this demo can run.

### UC1 — EBV cfDNA MRD — FIX MADE, pending redeploy
- Pre-fix run b9ed5d68 failed at container start (missing ECR image `biomate/cfdna`). Repointed
  to `biomate/biomni-tools:x86`. The workflow's LoB/LoD (CLSI EP17-A2) gate is EXECUTED inside
  QUANTIFY_MRD (not narrated) — the 8-read surveillance call is computed against an empirical
  LoD. Re-run after redeploy to confirm the output gate + the positive→indeterminate flip.

### UC3 — easier ICB response — FIX MADE, pending redeploy
- Pre-fix run c498a0f9 failed: `no package called 'viper'` (easier's dep closure absent in the
  slim container; the install guard only checked for easier). Added viper/dorothea/progeny/
  easierData to the runtime dep list. Re-run after redeploy. NOTE: the demo input is a
  synthetic 206-gene real-symbol matrix (responder-enriched); it tests the pipeline + output
  gate, but biologically meaningful scores need the real easierData IMvigor210 counts.
