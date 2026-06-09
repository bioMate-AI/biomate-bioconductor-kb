# Bioconductor Real-Execution Validation — Third-Party Verification Guide

*Snapshot date: 2026-06-08. Validation is ongoing — counts climb; this guide describes the method,
which is stable.*

## 1. The claim (precise)
We claim a set of Bioconductor analysis workflows are **executable**, defined strictly as:

> A real `nextflow run` (**no `-stub`**) in a dependency-complete container image, on a
> **synthesized realistic input**, runs to completion **and produces the workflow's declared,
> non-trivial outputs** (non-empty files derived from the input).

This is **not** "parses", "indexed", or "passes `nextflow -stub`" — those are weaker gates that
massively overstate runnability (only ~40% of stub-valid head workflows actually run; see §6).

- **Authoritative list:** [`bioc_validated_executable.csv`](./bioc_validated_executable.csv) —
  one row per executable workflow: `package, workflow, nextflow_path, domain, status,
  outputs_produced, validated_at`. `status ∈ {ok, ok_warnings}`.
- As of this snapshot: **724 workflows** across transcriptomics (362), general (114), genomics
  (83), epigenomics (50), proteomics (46), variant_calling (30), imaging (18), metagenomics (10).

## 2. Scope (what is and isn't in the denominator)
- **Head = top-650 by download ∪ 286 rising-stars** (by download velocity), infra-excluded =
  **882 packages / 1,629 workflows**. This is the guaranteed/validated target; rank-651+ non-rising
  is on-demand, not standing-validated.
- **Closed cycle**: head workflows **+ the analysis tools they use**. Of the 882 analysis tools
  used by head workflows (that have a workflow and aren't infra/data), **875/882 are attempted** —
  the dependency loop is essentially closed.
- **Excluded (not counted as failures):** 70 infrastructure packages (S4 containers, IO readers,
  data-access hubs — libraries, not pipelines; validated *transitively*); deprecated/removed
  packages; tail viz/API tools no head workflow uses (215 of 400 viz/API are out-of-cycle).

## 3. How a third party can verify — three paths

### Path A — through BioMate (no infrastructure setup)
1. In BioMate, issue a natural-language request that maps to a workflow in the CSV (e.g.
   *"run ABSSeq differential expression on this count matrix"*).
2. BioMate routes **only to real-execution-validated workflows** (it gates on `real_exec_status`),
   runs it on managed compute, and returns outputs.
3. Verify the outputs are **non-empty and derived from your input** (change the input → outputs
   change). This is the end-user-facing proof.

### Path B — reproduce the validation harness (strongest, needs the container image)
1. Obtain the workflow corpus and the per-workflow fixture (`<workflow>.fixture.R`) next to each
   `.nf` (in the project tree).
2. Obtain a dependency-complete container image for the domain. Image dependency manifests:
   `backend/scripts/bioc_domain_requirements.json` — a third party can **rebuild** the image from
   these (R + the listed Bioconductor packages) if the prebuilt image isn't shared.
3. Run the harness on any subset:
   ```
   python3 backend/scripts/realrun_test_bioc_workflows.py \
       --pkg-file <packages.txt> --workers 6 --audit result.json
   ```
   The harness: builds the realistic fixture input → `nextflow run` (no `-stub`) → asserts the
   declared non-trivial outputs are produced. `result.json` reports `status` per workflow.
4. Compare `result.json` `status` to the `status` column in the CSV. They should match for the
   same code + image.

### Path C — manual single-workflow spot-check (most transparent)
For one row, e.g. `transcriptomics / absseq / main`:
1. Read `.../bioconductor/absseq/main.nf` (the workflow) and `.../absseq/main.fixture.R` (the
   input generator).
2. In the package's public biocontainer (`quay.io/biocontainers/bioconductor-absseq:...`), run the
   fixture R to create the input, then run the workflow's R.
3. Assert the declared outputs (`*.csv` / `*.pdf` / `*.rds`) appear and are non-empty.
4. Tamper test: change the fixture input → confirm the outputs change (proves input-derived, not a
   hardcoded demo).

## 4. Per-workflow evidence
Every validated workflow carries, in the DB and in the harness audit JSONs:
`real_exec_status`, `real_exec_produced` (number of declared outputs actually produced),
`real_exec_at` (timestamp), and the captured stdout/stderr (the real R error for non-ok ones).
Request the audit JSONs for the captured logs behind any specific claim.

## 5. Is BioMate updated with this work?
- **Yes (data + routing):** the DB records `real_exec_status` for all attempted workflows; the
  router surfaces a Bioconductor workflow **iff** it is real-execution-validated; the panel renders
  the curated per-step `step_metadata` (visualizations + QC).
- **Dev deploy lag:** the dev environment was last synced at an earlier snapshot (518 validated);
  the current 724 requires a re-sync to be live on dev. Production routing reads the same DB field.

## 6. Honest caveats (read before testing)
- **Ongoing, not final.** 724 is a snapshot; it climbs each validation wave. Do not treat any count
  as a final number.
- **~40% real-execution rate among *attempted*.** Most attempted head workflows currently **fail**
  real execution (706 `exec_error`, 309 `fixture_failed`, etc.). We report this openly — the
  executable set is the minority that genuinely runs, and is exactly the CSV.
- **Container images are private** (internal registry). Path B's strongest form needs image access
  or a rebuild from `bioc_domain_requirements.json`. Paths A and C avoid this.
- **Binary-input + API tools are partial.** Binary example-data sourcing is solved for some formats
  and open for others (heterogeneous ExperimentData access); API/query tools are network-dependent.
  These limitations are documented in the methods, not hidden.
- **Failure classes are NOT claimed executable** — only the `{ok, ok_warnings}` rows in the CSV are.

## 7. Files for verifiers
| File | Purpose |
|---|---|
| `docs/verification/bioc_validated_executable.csv` | the authoritative executable list (724) |
| `backend/scripts/realrun_test_bioc_workflows.py` | the validation harness (Path B) |
| `backend/scripts/bioc_domain_requirements.json` | image dependency manifests (rebuild path) |
| `.../bioconductor/<pkg>/<wf>.nf` + `<wf>.fixture.R` | each workflow + its input generator |
| `docs/BIOCONDUCTOR_VALIDATION_MASTER.md` | full methodology + architecture |
