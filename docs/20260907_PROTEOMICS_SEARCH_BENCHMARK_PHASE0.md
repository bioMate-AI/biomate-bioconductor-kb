# Proteomics DB-Search Benchmark — Phase 0 build

**Date:** 2026-09-07
**Design:** `docs/20260907_PROTEOMICS_DB_SEARCH_OPTIMIZATION_SURVEY.md` §14
**Status:** scaffolded + locally validated (stub DAG green; scoring & DB-prep self-tests pass). **No Batch run yet** — that is the next step and is intentionally gated (per the no-speculative-deploy rule).

---

## What Phase 0 delivers

The unified speed-vs-sensitivity benchmark the field lacks — using only engines BioMate already has (Comet, MS-GF+), on datasets already in the registry (PXD000612, PXD001854). It needs **no new modeling and no missing engine**, and it produces the first **real end-to-end proteomics-search run evidence** on BioMate (none exists today — see the capability audit).

## Files

| File | Role | Validated |
|---|---|---|
| `evaluation/datasets/proteomics_search_benchmark/cases.yaml` | benchmark spec: datasets, methods, entrapment config, fair-comparison controls, targets | — (spec) |
| `evaluation/datasets/proteomics_search_benchmark/main.nf` | Nextflow harness: PREPARE_DB → RUN_COMET / RUN_MSGF → NORMALIZE → SCORE; every process has a `stub` | ✅ `nextflow run … -stub-run` green, incl. multi-file fan-out (RUN_COMET 2/2, RUN_MSGF 2/2, NORMALIZE 4/4) |
| `evaluation/datasets/proteomics_search_benchmark/prepare_search_db.py` | builds combined target+entrapment+decoy FASTA + label map | ✅ `--selftest` passes |
| `evaluation/datasets/proteomics_search_benchmark/normalize_psms.py` | engine-native (pepXML/mzid) → one PSM schema | ⚠️ **integration point** — pyteomics parsers written but must be validated against real Comet/MS-GF+ output on the first Batch run |
| `scripts/score_proteomics_search_benchmark.py` | target-decoy q-values, IDs@1%FDR, entrapment-FMR, calibration curve, Pareto | ✅ `--selftest` passes |

## What was validated locally (no cost)
- **Scoring core** (`--selftest`): target-decoy q-values, ID counts (PSM/peptide/protein), and the entrapment-FMR estimator all behave correctly — including the negative control (loosening FDR raises entrapment IDs, i.e. miscalibration is detectable). The self-test also surfaced (correctly) that entrapment peptides scoring among the decoys leak in at 1% q-value → a real FMR > nominal, which is exactly the signal the benchmark exists to catch.
- **DB prep** (`--selftest`): targets preserved verbatim, entrapment shuffled (composition-matched, known-false), decoys reversed, label map correct.
- **DAG** (`-stub-run`): full topology executes; fixed a Nextflow queue-vs-value channel bug (DB FASTA must be broadcast via `.first()` or the second engine is starved when there are multiple mzML files).

## The two axes + honesty axis (recap)
- **Speed** — read from the Nextflow executor trace (`-with-trace`), never a tool's own log.
- **Match count** — #PSMs/#peptides/#proteins at 1% target-decoy FDR, computed uniformly downstream (same estimator for every engine).
- **Calibration** — entrapment FMR at claimed 1% (`FMR ≈ (E/ratio)/T`). A method that finds more IDs but sits above the calibration diagonal is **disqualified, not celebrated**.

## To run for real (the gated next step)
1. Stage `PXD000612` / `PXD001854` mzML + human SwissProt+cRAP FASTA on S3 (mzML conversion from RAW if needed).
2. `nextflow run main.nf --mzml 's3://…/*.mzML' --target_fasta s3://…/human_sprot_crap.fasta --entrapment_ratio 1.0 -with-trace -profile awsbatch`
3. **First run is a validation run, not a headline run:** confirm `normalize_psms.py` maps Comet/MS-GF+ columns correctly (score sign, accession/decoy-prefix propagation) on real output before trusting any number. Predicted outcome to check against: Comet and MS-GF+ should each return a few-thousand-to-low-tens-of-thousands peptides at 1% FDR on a single Orbitrap run, with measured FMR ≤ ~1.3%.
4. Results land in `evaluation/results/proteomics_search_benchmark_v1/`.

## Open decisions (cheap to fix once first accessions are staged)
- **Entrapment ratio:** 1.0 (conservative) vs 8.0 (more sensitive to miscalibration). Default 1.0.
- **Entrapment source:** shuffled-target (default; composition-matched) vs a distant organism.
- **HLA anchor:** which immunopeptidome dataset for the large-search-space case (Phase 1).

## Roadmap
- **Phase 1:** add ProteomeTools (synthetic) → precision/recall + retrieval `recall@k`; drop in off-the-shelf Faiss-over-AlphaPeptDeep retrieval and compare recall@k vs fragment index.
- **Phase 2:** add mokapot rescoring layer (absent today) → measure the DL-rescoring sensitivity gain, entrapment-clean.
- **Phase 3:** add Sage / MSFragger (fragment-index engines, absent today) for the open-search speed frontier; then PredictedSpec-ANN on the same Pareto front.

## Honesty notes
- `normalize_psms.py` is the one unvalidated seam — parsers are written but engine-format quirks (MS-GF+ SpecEValue sign, accession formatting) must be confirmed on real output. Flagged in-file.
- Phase 0 uses only Comet + MS-GF+; a *rigorous cross-engine* comparison (vs MSFragger/Sage/DIA-NN + rescoring) is Phases 2–3, not now.
- Speed numbers are meaningless until read from a real executor trace on fixed hardware; the scaffold plumbs the trace but has no numbers yet.
