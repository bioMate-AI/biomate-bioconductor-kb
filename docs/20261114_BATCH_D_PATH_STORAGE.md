# Batch D — coldstart path / storage / PRODUCTION_MD (easy)

**Date:** 2026-11-14  
**Cases:** `analysis-try-sample-data-8`, `-0`, `-3`  
**Evidence:** `frontend/e2e/execshots/coldstart-analysis-design-deep/`  
**Inventory:** `docs/20261114_COLDSTART_FAILED_WORKFLOWS_INVENTORY.md` §6

---

## Case → root cause → fix

| Case | Workflow | Observed | Root cause | Fix |
|------|----------|----------|------------|-----|
| `analysis-try-sample-data-8` | `perform_chipseq_peak_calling_with_macs2` | `No such file or directory: [path] … (main.nf, line 413)` | Demo used live `raw.githubusercontent.com` MACS CTCF URLs with `file(..., checkIfExists: true)`. Batch/Galaxy head often cannot fetch GitHub raw at launch → missing path (redacted as `[path]`). | Vendor CTCF pair under `backend/biomni_workflows/sample_data/chipseq/`; entry workflow demo points at `${projectDir}/../../../../sample_data/chipseq/CTCF_SE_{ChIP,CTRL}_chr22_50k.bed.gz`. Same real public tracks; no runtime HTTPS. |
| `analysis-try-sample-data-0` | `nf-core/differentialabundance` | `Exception thrown downloading storage [storage] (differentialabundance.nf, …)` | `Channel.fromPath` on remote `s3://` (attached upload / demo URI). nf-amazon head-node fetch of private work-bucket objects failed (`[storage]` = redacted `s3://…`). Stale header still said “aws s3 cp in R” though process already used staged paths. | (1) When **all** of samplesheet/input/matrix/contrasts blank → vendored `sample_data/mg_demo/` CSVs via local `Channel.fromPath(..., checkIfExists: true)`. (2) When user paths supplied → still `Channel.fromPath` with `checkIfExists` (no R `aws s3 cp`). Partial supply still requires samplesheet (no demo/user mix). |
| `analysis-try-sample-data-3` | `analyze_flow_cytometry_immunophenotyping` | `There's no process matching config selector: PRODUCTION_MD` | Executor override always emitted `withName: 'PRODUCTION_MD'` whenever a GPU queue was set. Nextflow 24+ strict mode exits 1 when no process matches (flow cytometry has none). | **Executor:** emit `withName: 'PRODUCTION_MD'` only if the `.nf` declares `process PRODUCTION_MD` (parent applied in lib + packages). **Workflow demo path:** `params.fcs_file_path` default resolves to vendored Accuri blank at `sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs` (13 603 bytes) — confirmed on disk. |

---

## Files changed (this batch)

| File | Change |
|------|--------|
| `backend/biomni_workflows/sample_data/chipseq/CTCF_SE_*.bed.gz` + `PROVENANCE.md` | Vendored MACS CTCF demo pair |
| `backend/biomni_workflows/sample_data/mg_demo/{sample_metadata,counts_matrix,contrasts}.csv` + `PROVENANCE.md` | Vendored GSE227835 tutorial CSVs (same as cold-start `/demo/mg_demo/`) |
| `…/genomics/perform_chipseq_peak_calling_with_macs2/main.nf` | Demo sources → `sample_data/chipseq/` (not GitHub raw) |
| `…/nfcore/differentialabundance/main.nf` | Local mg_demo fallback; `checkIfExists` on `Channel.fromPath`; header corrected |
| `backend/lib/…/nextflow_executor.py` (+ packages hardlink) | `PRODUCTION_MD` withName gated on process declaration (**parent**) |
| `sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs` | Pre-existing; path resolve verified |

**Not touched (per Batch D boundary):** reinvent4 allow-list / `_PER_PROCESS_CONTAINER_WORKFLOWS`, soft-pass harness, attachment→samplesheet binding.

---

## Verify

1. **ChIP-seq path resolve**
   ```bash
   python3 -c "from pathlib import Path; p=Path('backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/perform_chipseq_peak_calling_with_macs2');
   print((p/'../../../../sample_data/chipseq/CTCF_SE_ChIP_chr22_50k.bed.gz').resolve().exists())"
   # True
   rg -n 'sample_data/chipseq' backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/perform_chipseq_peak_calling_with_macs2/main.nf
   # no raw.githubusercontent.com/macs3-project
   ```

2. **DE demo + Channel.fromPath**
   ```bash
   rg -n 'sample_data/mg_demo|checkIfExists' backend/biomni_workflows/nfcore/differentialabundance/main.nf
   ls backend/biomni_workflows/sample_data/mg_demo/*.csv
   ```

3. **Flow Accuri**
   ```bash
   python3 -c "from pathlib import Path; p=Path('backend/biomni_workflows/nextflow_nfcore/subworkflows/cell_biology/analyze_flow_cytometry_immunophenotyping');
   f=(p/'../../../../sample_data/flow_cytometry/Accuri_C6_A01_H2O.fcs').resolve(); print(f.exists(), f.stat().st_size)"
   # True 13603
   ```

4. **PRODUCTION_MD gate (parent)** — config for a non-MD `.nf` must not contain `withName: 'PRODUCTION_MD'`.

5. **Coldstart re-run (after sync):** filter  
   `BIOMATE_DEEP_FILTER='^analysis-try-sample-data-(0|3|8)$' ./e2e/run_coldstart_deep.sh`

---

## Gaps

- **Attached MG uploads still prefer S3 URIs when prefilled.** Demo local paths only fire when all three DE params are blank. If clarify leaves a bad remote URI, `Channel.fromPath` can still fail until executor-side boto3 localization (or successful nf-amazon) is in place — out of scope for this Batch D note if parent owns executor.
- **Flow cytometry on Batch:** default `params.fcs_file_path` is a host `projectDir` string passed into the container; if the workflow tree is not mounted into the task, the Accuri file may be missing inside the container even though the path resolves on the head. Staging as a `path` input would close that; not required to clear the PRODUCTION_MD session abort.
- **PRODUCTION_MD gate** must remain in both lib + packages copies after any sync/merge.
- Live Batch re-grade of the three cases not run in this session (sync + coldstart deep filter still required).
