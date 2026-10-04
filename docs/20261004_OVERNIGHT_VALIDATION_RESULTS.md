# Overnight autonomous validation results (2026-10-04)

**Context:** after the 4 parallel threads (UX run-progress, team activity ledger, pathology WSI,
validation fixes) were committed + deployed, the owner authorized autonomous overnight work. This
records the validation runs on the production path (`/api/workflows/execute`, spot Batch,
self-terminating), audited by reading real `.command.err`/outputs — **honest pass / fail / blocked**,
no fabrication, no run marked "pass" on a mere exit code.

## Deploy (done, verified)
- 4 threads live on dev (commit `010bfee5`, sync health PASS). Verified on dev: `project_activity`
  table exists (B), chipseq real file-inputs (D), pathology WSI workflow present (C), spatial fix
  present (D), frontend healthy (A).
- **DB safe:** dev `galaxy_ai_tools.db` MD5 unchanged (`39d8b5a8…`); no concurrent DB change clobbered.

## Validation runs

| Workflow | Run | Result | Evidence / cause |
|---|---|---|---|
| **merfish** (A infra + libz regression check) | `a2352e0f` | ✅ **PASS** exit 0 | Real squidpy output: `spatially_variable_genes.csv`, `spatial_domains.csv`, `spatial_qc.json`, `morans_I_ranking.png`, `top_svg_spatial.png`, report. Confirms the always-on host-libz mount still holds on this branch and the production run path is healthy. |
| **metaboanalystr** (D metabolomics fix) | `85ed4681` | ⚠️ **BLOCKED on input** (not a fix failure) | exit 1, `Error: Required input peak-intensity table (peak_intensity_table.csv) not found.` This is **correct honest-fail behaviour** (param-less run → no input). The `ReplaceMin → ImputeMissingVar` fix lives on the with-input path; validating it needs a staged peak-intensity table. |
| **visium_voyager_spatial_esda** (D spatial fix) | `4d05c71d` | ❌ **FAIL → re-fixed, re-running** | exit 127, `env: 'Rscript': No such file or directory`. Root cause: the job ran in **`biomate-nextflow-base`** (no R), not a bioc image — the `.nf` used `container "${params.container}"` (variable indirection), which the executor's `/single_cell/` container-force resolved to the base default. Fix (commit `b25d4877c`): **literal** `container '…/bioc-domain-transcriptomics:3.20'` directive (merfish pattern; full `:3.20` = the working sibling `voyager` id 12618's image, not `-slim`). Re-run pending. |
| **chipseq** (D peak-calling fix) | — | ⚠️ **BLOCKED on input** | D's fix correctly made ChIP+control files mandatory (was fabricating demo peaks). Validating needs a small public ChIP+control BAM pair; `team-curated/epigenomics/` has only a txdb + peaks.bed, no reads. Not run (no fabricated input). |
| **pathology WSI** (C) | — | ⬜ not attempted | Needs a WSI slide (public OpenSlide sample) + confirmation the cellpose image ships OpenSlide. Deferred; `executable=0`. |

## Honest headline
- **1 genuine pass** (merfish — real output).
- **2 input-blocked** (metaboanalystr, chipseq) — their *code* fixes are in place and they **honest-fail correctly** without input; end-to-end validation needs staged public inputs.
- **1 real runtime failure found + fixed** (voyager ran in the wrong/base image → literal-container fix; re-running). This is the "indexed ≠ runs" gap: D's fixes passed local checks but only a real run exposed the container-resolution bug.

## Lesson reinforced
A `.nf` process `container` set via `"${params.container}"` indirection is NOT reliable for
`/single_cell/`-path workflows — the executor's container-force resolves it to the base image
(no R/python → exit 127). Use a **literal** container directive (merfish, now voyager). Logged to
`reference_executor_container_resolution` territory.

## Next (autonomous, within guardrails)
- Re-run voyager after the literal-container sync; read outputs.
- Optionally stage a small public metabolomics peak table + ChIP/control BAM pair to close those
  two input-blocked validations (public data, spot runs).
- Pathology: attempt a public OpenSlide sample only if cheap runs stay clean.
