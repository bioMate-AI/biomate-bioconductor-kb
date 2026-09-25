# Domain Validation Results — Single-cell + Metabolomics (BLOCKED, NO SPEND)

> ## UPDATE 2026-09-24 (independent re-verification pass) — COMPILE FIXES CONFIRMED CORRECT; real Batch runs correctly WITHHELD ($0.00)
>
> A follow-up task independently re-verified the compile-bug fixes already in the
> working tree and was asked to do ONE cheap real Batch run per workflow. **Both
> fixes are correct and both files compile free** (Nextflow 25.10.6 local). **No
> Batch run was dispatched** because a disciplined code review (CLAUDE.md "Review
> Code Before Testing") proved that both real runs would fail for pre-existing
> STRUCTURAL reasons unrelated to the compile bugs fixed — spending to observe
> those failures is forbidden. Total spend this pass: **$0.00**. No files committed,
> nothing synced to dev.
>
> ### FREE compile verification (independently re-run this pass)
> | Workflow | Command | Result |
> |---|---|---|
> | metabolomics | `nextflow inspect main.nf --mzml_dir /tmp/fake` | **EXIT 0** — all 4 includes resolve, full 4-process DAG (XCMS→CAMERA→METABOANNOTATION→CLUSTERPROFILER) built, every `.out.*` ref valid |
> | metabolomics | `nextflow run main.nf -stub-run --mzml_dir … --gene_list …` | DAG executes; XCMS/CAMERA/METABOANNOTATION stubs pass; **fails only inside the clusterprofiler subworkflow's own stub** (declares mandatory `emit: qc_metrics = path("qc_metrics.json")` but its `stub:` block only `touch`es the CSV — a pre-existing defect in `subworkflows/bioconductor/clusterprofiler/main.nf`, not the orchestrator) |
> | single-cell | `nextflow inspect main.nf --fastq_dir /tmp/fake` | **EXIT 0** — process + named workflow + anonymous entry all parse; `_detect_nextflow_entry()` returns `None` (default entry) as designed |
>
> ### Why NO real run was dispatched (predicted failures, all unrelated to the compile fix)
> **Metabolomics** — the four bioconductor subworkflows are independent single-package
> demos, NOT a chained pipeline. Confirmed by reading the subworkflow bodies this pass:
> - `clusterprofiler/main.nf:305-307` — the `*_WORKFLOW` hard-`error`s unless
>   `--gene_list` (a gene-symbol file) is supplied, and reads that file directly; it
>   does NOT consume `BIOC_METABOANNOTATION.out`. A real MTBLS136 run aborts at this
>   param check before any compute.
> - `camera/main.nf:64` — hardcodes `file <- "MM14.mzML"` and runs its OWN
>   `xcmsSet()` peak-picking; it ignores the XCMS `.rds` the orchestrator passes and
>   would `stop("Required input file missing: MM14.mzML")`.
> - XCMS is `..._DIRECT_INJECTION_MS_PREPROCESSING` (single spectrum/sample, no
>   chromatographic dimension) — wrong modality for LC-MS MTBLS136.
> - Making these actually chain requires rewriting the subworkflow R bodies (a
>   data-flow redesign). Per the task constraint that forbids fabricating outputs to
>   pass, this is out of scope. The compile/wiring bug named in the task IS fixed.
>
> **Single-cell** — the entry-point bug IS fixed (verified above), but the process
> container `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scrnaseq-standard:v1`
> **does not exist** (`aws ecr describe-repositories` → RepositoryNotFoundException,
> re-confirmed this pass) so a Batch job dies at container pull; and STAGE 2's
> `counts_matrix.h5ad` is never staged (grep of `nextflow_executor.py` = 0 hits for
> `counts_matrix.h5ad` / `scrnaseq_standard_endtoend`). Per the task's own escape
> hatch, single-cell needs the Docker image + STARsolo staging built before any
> scored run — a large separate task. The entry-point defect itself is fixed.
>
> **Conclusion:** the two compile/entry execution bugs named in the task are fixed
> and free-verified. Real runs remain gated behind pre-existing structural gaps that
> spending money cannot fix and that fixing-to-pass would violate CLAUDE.md.

> ## UPDATE 2026-09-23 (later, code-fix pass) — COMPILE BUGS FIXED; runs still blocked by deeper (non-compile) defects
>
> A follow-up task fixed the **Nextflow-compile / entry-point defects** the original
> report identified (these are legitimate execution-bug fixes, NOT benchmark hacks).
> **Both files now compile and their entry resolves** — verified free with
> `nextflow inspect` (Nextflow 25.10.6, local). **No AWS spend was incurred**: on
> code review both real runs were predicted to FAIL for reasons *unrelated to the
> compile bugs fixed*, so per CLAUDE.md "Review Code Before Testing — No Speculative
> Deploys" no Batch job was dispatched. Changes left in the working tree (uncommitted).
>
> ### A. Metabolomics — `nextflow_nfcore/workflows/bioconductor_metabolomics/main.nf` — COMPILES ✅
> - **Fix 1 (include names), lines 22–25:** aliased the bare names to the real
>   subworkflow definitions:
>   `BIOC_XCMS` → `BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING_WORKFLOW as BIOC_XCMS`;
>   `BIOC_CAMERA` → `BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION_WORKFLOW as BIOC_CAMERA`;
>   `BIOC_METABOANNOTATION` → `..._MATCH_VALUES_WORKFLOW as ...`;
>   `BIOC_CLUSTERPROFILER` → `..._OVER_REPRESENTATION_ANALYSIS_WORKFLOW as ...`.
> - **Fix 2 (emit/channel names), lines 44–62:** the subworkflows emit
>   `tables/plots/objects/versions` (no `rds`/`results`). Rewired:
>   `BIOC_XCMS.out.rds` → `BIOC_XCMS.out.objects`;
>   `BIOC_CAMERA.out.results` → `BIOC_CAMERA.out.objects`;
>   `.out.results` reads → `.out.tables`; and `BIOC_CLUSTERPROFILER(...)` is now
>   called with **no argument** (its `*_WORKFLOW` has no `take:` — it reads
>   `params.gene_list` directly). `nextflow inspect` builds the full 4-process DAG.
> - **REMAINING (deeper, non-compile) blocker → no run dispatched:** the four
>   bioconductor subworkflows are *independent single-package demos*, not a chained
>   pipeline. CAMERA hardcodes `file <- "MM14.mzML"` (`camera/main.nf:64`) and does
>   its OWN xcms peak-picking; metaboannotation hardcodes `ms1_features.txt` +
>   `LipidMaps_CompDB.txt`. They **ignore** the upstream `.out.objects` the
>   orchestrator now correctly passes and read fixed filenames that the orchestrator
>   never stages. A real MTBLS136 run would compile but die inside R at the CAMERA
>   stage (`stop("Required input file missing: MM14.mzML")`). Making it a genuine
>   chained pipeline requires rewriting the subworkflow R bodies (a data-flow
>   redesign) — out of scope, and forcing it would be a fabricated-to-pass edit.
>
> ### B. Single-cell — `nextflow_nfcore/subworkflows/single_cell/scrnaseq_standard_endtoend/main.nf` — COMPILES ✅
> - **Fix (entry point), appended after the process (new lines ~195–240):** added a
>   named `workflow SCRNASEQ_STANDARD_ENDTOEND_WORKFLOW { take: meta_ch; main:
>   SCRNASEQ_STANDARD_ENDTOEND(meta_ch); emit: ... }` re-exporting all 8 process
>   outputs, plus an anonymous `workflow { }` that validates `params.fastq_dir`,
>   builds `[id: ...]`, and pipes it in. This is the exact pattern of the sibling
>   single_cell subworkflows (`parse_split_seq_scrna`, `bd_rhapsody_scrna`,
>   `cite_seq_preprocessing`). `_detect_nextflow_entry()` now returns `None`
>   (anonymous entry present → Nextflow uses default entry). `nextflow inspect` OK.
> - **REMAINING (deeper, non-compile) blockers → no run dispatched:**
>   1. The process container `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/scrnaseq-standard:v1`
>      **does not exist** (`aws ecr describe-repositories` → repo `biomate/scrnaseq-standard`
>      RepositoryNotFoundException). On AWS Batch the job fails at container pull.
>      The `/opt/biomate/scrnaseq/*.py|*.R` stage scripts live only inside that
>      (unbuilt) image. Building it is a large separate task.
>   2. STAGE 2 is a comment ("orchestrator stages counts_matrix.h5ad") but **no
>      orchestrator code** stages it (`grep counts_matrix.h5ad|scrnaseq_standard_endtoend
>      nextflow_executor.py` = 0 hits), so STAGE 3 `scdblfinder_qc.R --h5ad
>      counts_matrix.h5ad` has no input even if the image existed.
>   - Per the task's own escape hatch ("If a correct entry-point fix is genuinely
>     large/ambiguous... report single-cell as needing more work — don't force it"),
>     single-cell needs the Docker image + orchestrator STARsolo staging before any
>     scored run is possible. The entry-point defect itself is fixed.
>
> **Net:** the two *compile/entry* execution bugs named in the task are fixed and
> verified free. The real-run gate correctly stopped BOTH runs after review — the
> predicted failures are pre-existing structural gaps (demo-only subworkflows /
> missing container / missing orchestrator staging), not the compile bugs, and
> spending to "see them fail" is forbidden. **Total spend this pass: $0.00.**
> Original (pre-fix) report retained below for context.

---

**Date:** 2026-09-23
**Author:** Yaoyun Zhang
**Companion to:** `docs/20260923_DOMAIN_VALIDATION_PLAN.md`
**Outcome:** **STOPPED before any AWS Batch dispatch. $0.00 spent.** Both target
workflows are non-runnable due to **code-level (Nextflow-compile) defects** in
the production `.nf` files — not data-staging or infra issues. Fixing them would
require editing production workflow `.nf` files, which CLAUDE.md and the task
constraints forbid for the purpose of making a run pass. No input data was staged
(staging is wasted work for a workflow that cannot compile).

This is the correct disciplined result per the task guardrail: *"If staging or
dispatch fails, STOP + report — don't loop-retry burning money"* and CLAUDE.md
*"Review Code Before Testing — No Speculative Deploys."*

---

## Pre-flight verification that WAS done (read-only, $0)

| Check | Result |
|---|---|
| AWS identity (`sts get-caller-identity`, us-west-2) | OK — account 399683337364 |
| Dev reachable (`https://dev-public.biomate.ai/api/health`) | HTTP 200, 0.34 s |
| Batch compute env `biomate-nextflow-ce-v2` | VALID / ENABLED |
| Batch queue `biomate-nextflow-queue` | VALID / ENABLED |
| S3 input paths for both domains | **empty** (0 objects) — as the plan flagged |
| Any prior real SC output on S3 (`annotated.h5ad`) | **none anywhere** — no SC run has ever completed |
| Workflow DB (`galaxy_ai_tools.db`, 318 MB full enriched copy) | queried both ids directly |

Infra is healthy. The blockers below are entirely in the workflow source.

---

## Domain 1 — Single-cell (`scrnaseq_standard_endtoend`, id 12777)

- **Staged input URI:** none (not staged — workflow non-runnable, see below).
- **run_id / Batch job ids:** none (never dispatched).
- **Terminal status:** N/A — blocked pre-dispatch.
- **Gold metric (`azimuth_macro_f1` ≥ 0.85):** N/A.
- **Cost:** $0.00.

### Blockers (code-level, deterministic)

1. **DB id 12777 is `nf-core/scrnaseq`, and its on-disk file
   `backend/biomni_workflows/nfcore/scrnaseq/main.nf` is a NON-EXECUTABLE
   parameter stub** — 0 `output:` / `emit:` / `publishDir` blocks, and its
   process scripts use invented CLI flags (`fastqc --input … --whitelist`,
   `cellranger count --aligner …` — not real tool flags). It produces no real
   outputs. So dispatching by the DB `filename` cannot yield a scored run.

2. **The real executable workflow the plan points to —
   `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/scrnaseq_standard_endtoend/main.nf`
   — has NO Nextflow entry point.** It defines only
   `process SCRNASEQ_STANDARD_ENDTOEND` — there is **no `workflow { }` block and
   no named `workflow`**. `_detect_nextflow_entry()` in `nextflow_executor.py`
   returns `None` for it, and there is no anonymous entry, so **Nextflow has
   nothing to execute** ("no entry workflow" — fails at invocation, pre-compute).

3. **Even if it had an entry, STAGE 3 reads `counts_matrix.h5ad`** that STAGE 2
   is documented to have the *orchestrator* stage from the nf-core/scrnaseq
   STARsolo sub-run — **but no orchestrator code references
   `scrnaseq_standard_endtoend` or stages `counts_matrix.h5ad`** (grep of
   `nextflow_executor.py` = 0 hits). The file's `include` of nf-core/scrnaseq
   does not exist either. So the STARsolo counts its downstream stages depend on
   are never produced.

4. **The plan's "cheap `.h5ad` input path (skip STARsolo)" is not supported by
   this workflow.** id 12777 (`input_types: ["fastq","samplesheet"]`,
   `output_types: [...,"h5ad",...]`) *consumes* FASTQ and *produces* h5ad — it
   does not accept a pre-computed `.h5ad` as input. There is no h5ad-input code
   path in the executor for this workflow. Feeding a `.h5ad` would require adding
   a new input branch to the production `.nf`.

Making single-cell runnable would require authoring a real workflow entry +
STARsolo-count orchestration (or an h5ad-input branch) in the production `.nf` —
i.e. editing production workflow files to make a run pass. **Forbidden.**

---

## Domain 2 — Metabolomics (`bioconductor_metabolomics`, id 12731)

- **Staged input URI:** none (not staged — workflow non-runnable, see below).
- **run_id / Batch job ids:** none (never dispatched).
- **Terminal status:** N/A — blocked pre-dispatch.
- **Gold metric (`published_biomarker_recall` ≥ 0.70):** N/A.
- **Cost:** $0.00.

### Blockers (code-level, deterministic — DSL2 compile failure)

1. **DB id 12731 is `nf-core/metaboigniter`, filename
   `nfcore/metaboigniter/main.nf`, which DOES NOT EXIST on disk** (No such file).
   Dispatching by DB filename → 404 at path resolution.

2. **The real workflow the plan points to —
   `backend/biomni_workflows/nextflow_nfcore/workflows/bioconductor_metabolomics/main.nf`
   — will NOT COMPILE.** It does:
   ```
   include { BIOC_XCMS            } from '../../subworkflows/bioconductor/xcms/main.nf'
   include { BIOC_CAMERA          } from '../../subworkflows/bioconductor/camera/main.nf'
   include { BIOC_METABOANNOTATION } from '../../subworkflows/bioconductor/metaboannotation/main.nf'
   include { BIOC_CLUSTERPROFILER } from '../../subworkflows/bioconductor/clusterprofiler/main.nf'
   ```
   but each subworkflow defines a DIFFERENTLY-NAMED workflow:
   - xcms → `BIOC_XCMS_DIRECT_INJECTION_MS_PREPROCESSING_WORKFLOW`
   - camera → `BIOC_CAMERA_SINGLE_SAMPLE_LCMS_ANNOTATION_WORKFLOW`
   - metaboannotation → `BIOC_METABOANNOTATION_MATCH_VALUES_WORKFLOW`
   - clusterprofiler → `BIOC_CLUSTERPROFILER_OVER_REPRESENTATION_ANALYSIS_WORKFLOW`

   None of the bare names (`BIOC_XCMS`, …) exist → Nextflow aborts at parse time
   with "Cannot find a matching workflow for BIOC_XCMS". No Batch job launches.

3. **Output name mismatch (secondary compile break).** main.nf reads
   `BIOC_XCMS.out.rds`, `BIOC_CAMERA.out.results`, `BIOC_METABOANNOTATION.out.results`,
   but the subworkflows emit `tables / plots / objects / versions` — no `rds` or
   `results` channels. Even with the include names fixed, the wiring is wrong.

4. **Semantic mismatch (would matter only if it compiled):** the XCMS
   subworkflow is `..._DIRECT_INJECTION_MS_PREPROCESSING` (single spectrum per
   sample, *no chromatographic dimension*), while MTBLS136 is LC-MS
   (chromatographic). The XCMS defaults are for DI-MS, not LC-MS peak-picking.

Making metabolomics runnable requires correcting the `include` names and the
`.out.*` channel wiring in the production `bioconductor_metabolomics/main.nf` (and
its subworkflows) — i.e. editing production workflow files to make a run pass.
**Forbidden** under the task constraints for this validation exercise.

---

## Total spend

**$0.00** — no Batch job dispatched, no data staged, no compute launched. All
checks were read-only AWS/DB/filesystem inspection.

---

## Recommendation (separate, non-validation work)

These are **real workflow-authoring bugs**, distinct from the "resolve root
causes" validation intent. They should be fixed as their own engineering task
(with the pre-sync checklist + a Nextflow `-stub-run`/`nextflow inspect` compile
gate), NOT as a benchmark-passing edit:

1. **Metabolomics:** rename the four `include { … }` aliases to the actual
   subworkflow workflow names (or add `as BIOC_XCMS` aliases inside each
   subworkflow), and align `.out.rds`/`.out.results` reads to the emitted
   `tables/objects` channels. Then a real MTBLS136 mzML stage + run becomes
   possible. Also decide DI-MS vs LC-MS XCMS variant for MTBLS136.
2. **Single-cell:** give `scrnaseq_standard_endtoend/main.nf` a real `workflow { }`
   entry that either (a) `include`s + calls nf-core/scrnaseq for STARsolo counts
   before the QC→Harmony→Leiden→CellTypist stages, or (b) adds a documented
   `--input_h5ad` branch that skips alignment (the plan's intended "cheap path").
   Until one exists, no SC run can be scored.
3. Add a **CI compile-gate** (`nextflow inspect` / `-stub-run`) for every indexed
   executable workflow so include-name / channel-name mismatches like these are
   caught before they reach a Batch dispatch attempt.

Once (1) or (2) lands (as reviewed, tested workflow-authoring PRs — not
benchmark hacks), re-run this validation; the infra is confirmed healthy and the
spend is ~$0.9 (metabolomics) / ~$0.7–4.6 (single-cell) as the plan estimated.
