# License-clean proteomics search capability — Option C (DDA) built; A/B next

**Date:** 2026-09-08
**Branch:** `docs/proteomics-search-benchmark`
**Context:** DIA-NN is license-blocked for commercial BioMate hosting (see `reference_proteomics_engine_licenses` / `docs/20260908_DIANN_COHORT_SCALE_DIAGNOSIS.md` §5). Building the license-clean search suite instead: **C = DDA (this doc), A = OpenSWATH DIA, B = EncyclopeDIA library-free.**

## Repo-state findings that reshaped the plan
- **`nf-core/diaproteomics` is a phantom DB registration** — no backing `.nf` resolves; cannot run.
- The only vendored DIA search subworkflow is `dia_proteomics_analysis` = **DIA-NN** (license-blocked).
- **No OpenSWATH / PyProphet / EncyclopeDIA vendored** anywhere.
- **Vendored + license-clean:** `modules/nf-core/openms/*` (BSD: decoydatabase, peptideindexer, id{filter,merger,ripper,scoreswitcher,massaccuracy}, peakpickerhires, filefilter) + `openmsthirdparty/cometadapter` (Comet, Apache). Enough for a **DDA** search core today; **no `FalseDiscoveryRate`/Percolator module vendored** (FDR gap).
- The audit-cited `register_missing_biomate_workflows.py` **does not exist** — registration is a dev-only DB operation (the full workflow DB is gitignored, lives on dev + S3, never rebuilt locally).

## C — what was built (committable, stub-validated)
`backend/nf-core-modules/proteomics_dda_search/` — `main.nf` + `nextflow.config` + `assets/`.
- **Stack (license-clean):** Comet (Apache) via OpenMS `CometAdapter` + OpenMS (BSD) `DecoyDatabase`, `PeptideIndexer`; container `biocontainers/openms-thirdparty:3.4.1`.
- **Cohort fan-out (engine-agnostic):** `DECOYDATABASE` builds target+decoy **once** → `COMETADAPTER` searches **per run** (fans out on Batch CPU nodes) → `PEPTIDEINDEXER` annotates target/decoy per run.
- **Validated:** `nextflow run … -stub-run` green with 2 runs → DECOYDATABASE ×1, COMETADAPTER ×2, PEPTIDEINDEXER ×2, correct emit. The per-run fan-out (the days→hours lever) is confirmed at the DAG level.
- **Search params** (enzyme/mods/tolerances) surfaced as `ext.args` in `nextflow.config`, identical for every run (fair-comparison / reproducibility).

## Known gaps / follow-ons for C
1. **FDR/reporting:** no OpenMS `FalseDiscoveryRate` module is vendored. FDR at 1% is computed downstream by `scripts/score_proteomics_search_benchmark.py` (target-decoy q-values) after an idXML→PSM-table step (add an idXML branch to `evaluation/datasets/proteomics_search_benchmark/normalize_psms.py`). Alternative: vendor `openms/falsediscoveryrate` (upstream nf-core module) for an all-in-pipeline FDR.
2. **Batch validation (gated — costs money):** stub-run proves the DAG, not real search. First real run stages an mzML + FASTA on S3 and confirms CometAdapter `ext.args` map to real Comet flags. This would be BioMate's first real license-clean proteomics search run.

## Registration (dev-only DB step — NOT committable locally)
Add a row to the `workflows` table on dev (the local DB is a stub; never `--rebuild`):
- `name = "proteomics_dda_search"`
- `filename = "nfcore/proteomics_dda_search/main.nf"`  ← resolves via `_resolve_nextflow_path` to `backend/nf-core-modules/proteomics_dda_search/main.nf`
- `format = "nextflow"`, `domain = "proteomics"`, `source = "biomate"`, `executable = 1`
- `docker_image = "biocontainers/openms-thirdparty:3.4.1--h9ee0642_1"`, `input_types = "mzml,fasta"`, `output_types = "idXML"`
- `tools_used = "Comet, OpenMS"`, `tags = "proteomics,dda,comet,openms,search,peptide-identification,license-clean"`
- `workflow_json = <contents of main.nf>`

## A / B — next builds (each needs external vendoring; B needs a license check)
- **A — OpenSWATH DIA:** vendor upstream nf-core modules `openms/openswathworkflow` + `pyprophet` (+ a spectral-library step), build a DIA subworkflow reusing the same library-once → per-run → joint fan-out. Community-standard license-clean DIA (BSD). Needs a spectral library.
- **B — EncyclopeDIA / nf-encyclopedia:** vendor the MacCoss library-free pipeline. **Gate: confirm the license is permissive (believed Apache-2.0) before shipping.**
