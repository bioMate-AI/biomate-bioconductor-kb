# Known workflow-failure fixes — code-only, root cause (Thread D)

**Date:** 2026-10-03
**Author:** Yaoyun Zhang
**Scope:** `docs/20261003_PARALLEL_WORKSTREAM_PLAN.md` Thread D / `20261003_SCIENTIFIC_VALIDATION_AND_TEAMWORK_FOLLOWUP.md` §1 execution-order step 1 — *close the known failures at their code root cause before launching more compute.*
**Hard constraints honored:** NO Batch/cloud dispatch, NO `sync_to_dev.sh`, no fabrication, specific files committed (never `git add -A`), no conflict markers.

Local tooling used: `nextflow 25.10.6` (`-preview` DAG build), `python3` (`ast.parse`, R brace/escape audit). `Rscript` is not installed locally, so R was verified by parse-structure + API-against-NAMESPACE review, not execution. Each fix is marked **fix applied — awaiting owner-approved validation run.**

---

## 1. Metabolomics — MetaboAnalystR API drift

**Failure (real, recorded — `docs/20260923_DOMAIN_VALIDATION_RESULTS.md` UPDATE 2026-09-29c):**
```
[1] "Successfully passed sanity check!"
Error in ReplaceMin(mSet) : could not find function "ReplaceMin"
Execution halted
```
Batch statusReason: `zombie Rserve daemon after R error (ReplaceMin not found)`.

**Root cause:** `ReplaceMin()` is no longer exported by MetaboAnalystR 4.x. The missing-value
min-imputation was renamed `ReplaceMin` → `ImputeMissingVar(method="min")`. Verified against the
package NAMESPACE: every other function the workflow calls (`InitDataObjects`, `Read.TextData`,
`SanityCheckData`, `FilterVariable`, `PreparePrenormData`, `Normalization`, `FC.Anal`,
`Ttests.Anal`, `Volcano.Anal`, `PlotVolcano`, `PLSR.Anal`, `PlotPLS2DScore`, `PLSDA.CV`,
`PlotPLS.Imp`, `CrossReferencing`, `CreateMappingResultTable`, `SetMetabolomeFilter`,
`SetCurrentMsetLib`, `CalculateHyperScore`, `Setup.MapData`) is still exported — `ReplaceMin` was
the single drifted call.

**Fix (already applied + committed — root cause, no workaround):**
`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/metaboanalystr/main.nf`.
- `ReplaceMin(mSet)` → `ImputeMissingVar(mSet, method = "min")`, and gated to run **only when
  missing values actually remain** (`dataSet$missingCount > 0`). On a clean CONC table
  `SanityCheckData` already replaces residual missings with half the minimal positive value, and
  an unconditional `ImputeMissingVar` desynchronises `proc.cls` from the preproc matrix
  (`.get.latest.proc.matrix` → "Unable to resolve class labels for matrix source"). Gating keeps
  `proc.cls` intact for the common complete-data case (commits `c183d99b8`, `3155e04fe`).
- Related API-shape drift in the same block, also fixed: `FilterVariable` in 4.x returns an
  **integer status code** (not the mSet) in the off-web path; the chained `mSet <- FilterVariable(...)`
  clobbered `mSet` with an atomic `2` and broke `PreparePrenormData`. Now only re-binds `mSet` when
  the call returns an mSet-shaped list (commit `38a5e2ae0`).
- Rserve zombie: `.bm_finish()` `pkill -9 -f Rserve` + `quit(status=…)` on both success and error
  paths so the Batch container exits promptly (commit `c183d99b8`).

**Verification (local):** no `ReplaceMin(` call remains (only explanatory comments); `ImputeMissingVar`
present at line 166; R script-block paren/brace/bracket balance = 0; the earlier CSV-assembly chain
(`eb0c683a5`, `602778a15`) already cleared SanityCheck on the last real Batch run.

**Status: fix applied — awaiting owner-approved validation run.** (A prior real Batch run proved
ingest + sanity-check + 2-group detection now pass; this rename is the next downstream line.)

---

## 2. Spatial — missing container (`visium_voyager_spatial_esda`)

**Failure (real, recorded — `docs/20260928_DOMAIN_VALIDATION_UNTESTED.md`):**
> `visium_voyager_spatial_esda/main.nf` references ECR image `biomate/bioc-spatial:v1` (later
> `biomate/bioc-domain-spatial:3.20-deps`) which **does not exist** (no spatial repo in ECR), and its
> stages call bespoke `/opt/biomate/voyager/*.R` scripts that live only inside that never-built
> image. **BLOCKED — do not run.**

**Root cause:** two coupled container/dependency gaps — (a) the process `container` pointed at an
image that was never built, and (b) the process invoked `Rscript /opt/biomate/voyager/esda_run.R`,
a bespoke script baked only into that unbuilt image. So the task failed at container-pull /
missing-script before any analysis. Swapping the container alone would not help — the bespoke
script would still be absent in any other image.

**Fix (applied + committed):**
`backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/visium_voyager_spatial_esda/main.nf`.
- `container` → the **EXISTING, Batch-ready** ECR image
  `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim`
  — the exact image the sibling `bioconductor/voyager/main.nf` uses for the Voyager stack. It is an
  ECR image with a working aws-cli/libz, so it avoids the raw-quay-biocontainer libz S3-staging
  failure entirely (the `_needs_host_libz` executor gate currently covers only `/nf-core-workflows/`
  and `/nf-core-modules/`, not `/single_cell/`, so a raw quay image here would exit 127; an ECR
  `bioc-domain-*` image sidesteps that whole class).
- The ESDA R logic (formerly `backend/scripts/domain_images/voyager/esda_run.R`, which is present in
  the repo) is now **inlined** into the process `script:` block, so there is no dependency on a
  baked bespoke script. Params are injected via Groovy (`${params.sfe_dataset}` etc.); R's own `$`
  are escaped `\$`.
- A BiocManager **`.bm_deps` runtime resolver** installs the
  Voyager/SpatialFeatureExperiment/SFEData/scater/scran/jsonlite stack if the image lacks any of it.
- **Honest-fail guard:** the `library(...)` loads are NOT wrapped in an error-swallowing
  `quit(status=0)`; if the stack cannot be resolved (e.g. `sf`/`spdep`/GDAL unavailable) the run
  fails with a non-zero exit — no fabricated spatial output (CLAUDE.md: no fabrication).

**Owner DB note:** set workflow **id 14438** `docker_image` to
`399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/bioc-domain-transcriptomics:3.20-slim`
(was the non-existent `bioc-domain-spatial:3.20-deps`). The local `galaxy_ai_tools.db` is a
gitignored stub (`reference_workflow_db_canonical`); the DB is set on dev — not edited here.

**Verification (local):** `nextflow run … -preview` builds the DAG cleanly (DSL2 parse OK); no
leftover placeholders; 6 `${params.*}` injected; all `$` escaped; reconstructed R paren/brace/bracket
balance = 0; Voyager calls (`findVisiumGraph`, `runUnivariate`) + `.bm_deps` present.

**Residual risk (honest):** the Voyager spatial stack needs `sf`/`spdep` (system GDAL/GEOS/PROJ). If
`bioc-domain-transcriptomics:3.20-slim` lacks those system libs, the runtime `sf` install fails and
the workflow honest-fails. This is the same residual the sibling `bioconductor/voyager` carries; it
can only be confirmed by the owner-approved Batch run. If it fails there, the follow-up is to add
`sf`/`spdep`/GDAL to that image's deps or build the `bioc-domain-spatial` image — not a code change.

**Status: fix applied — awaiting owner-approved validation run.**

---

## 3. ChIP-seq — pipeline did not reach peak calling (MACS2)

**Failure (recorded — `docs/20260928_DOMAIN_VALIDATION_UNTESTED.md`):** prior ChIP-seq launches
produced only `pipeline_info`, never real peaks; peak calling was never reached.

**Root cause (read from the source, not guessed):**
`backend/biomni_workflows/nextflow_nfcore/subworkflows/genomics/perform_chipseq_peak_calling_with_macs2/main.nf`
(DB id 10680, `executable=1`). The process declared `input: val(meta)` — **no staged file inputs** —
`params.chip_seq_file`/`params.control_file` defaulted to `null`, and the standalone entry workflow
built `ch_input = Channel.of([id: 'run'])` (meta only, no files). So inside the Python body
`chip_seq_file` was always `None`, the guard
```python
if chip_seq_file is None or not os.path.exists(str(chip_seq_file)):
    log += "Running in demo mode with simulated results.\n"
    return log            # <-- returns BEFORE building/running `macs2 callpeak`
```
fired every time and returned a fabricated "demo"/"simulated" success log — the `macs2 callpeak`
subprocess (lines ~163-196) was never reached.

**Fix (applied + committed):**
- Process input is now `tuple val(meta), path(chip_seq_file), path(control_file)` — Nextflow
  localises both alignments into the task work dir, so `os.path.exists(...)` is true and peak
  calling is reachable. The script exports the **staged basenames**
  (`export PARAM_CHIP_SEQ_FILE="${chip_seq_file}"`), not the raw params.
- The standalone `workflow {}` entry requires `--chip_seq_file`/`--control_file` and builds the
  staged `[meta, chip, control]` channel (`file(..., checkIfExists: true)`); it `error`s on missing
  input instead of silently entering demo mode.
- The missing-input and missing-MACS2 branches now **honest-fail** (`raise … → exit 1`) instead of
  returning fabricated demo/simulated peaks (CLAUDE.md: no fabrication).
- Real MACS2 artefacts are published: `*_peaks.narrowPeak`, `*_peaks.xls`, `*_summits.bed`
  (optional emits).
- `nextflow_nfcore/test_data/run_tests.nf` TEST block updated to the new 3-input arity.

**Verification (local):** `nextflow run … -preview --chip_seq_file … --control_file …` builds the
DAG cleanly (DSL2 parse OK, 3-input process wiring valid); embedded Python body `ast.parse` OK
(270 lines).

**Note:** the container `biomate/biomni-tools` must ship `macs2` on PATH (the body now honest-fails
if absent). This is verified only by the owner-approved Batch run. The separate `nf-core/chipseq`
(DB id 1492) remains a non-executable stub with invented tool flags — intentionally NOT modified
("do not run" per the readiness table); real ChIP-seq annotation is already validated via
ChIPseeker.

**Status: fix applied — awaiting owner-approved validation run.**

---

## Commits (this thread)

| Fix | File(s) | Commit |
|---|---|---|
| Metabolomics API drift | `…/bioconductor/metaboanalystr/main.nf` | already committed (`c183d99b8`, `3155e04fe`, `38a5e2ae0`) — verified this session |
| Spatial missing container | `…/single_cell/visium_voyager_spatial_esda/main.nf` | this session |
| ChIP-seq peak-calling reachable | `…/genomics/perform_chipseq_peak_calling_with_macs2/main.nf`, `…/test_data/run_tests.nf` | this session |

No Batch/cloud run was dispatched; no `sync_to_dev.sh` run. Deploy + validation are owner-gated
per the parallel-workstream serialization plan (D → B → A → C).
