# Bioconductor Workflows & Tools — Statistics (2026-06-13)

Source of truth: `backend/database/galaxy_ai_tools.db` (`source='bioconductor'`).
Companion dumps: `20260613_BIOC_WORKFLOW_REGISTRY.csv` (per workflow), `20260613_BIOC_PACKAGE_SUMMARY.csv` (per package), `20260613_BIOC_RISING_STARS_REGISTRY.csv`.

## 1. Totals
| | count |
|---|---|
| Bioconductor **workflows** | **3,310** |
| Distinct **packages** | **1,818** |
| Packages with **multiple workflows** | 805 |
| Avg workflows / package | 1.8 |

## 2. Tool/package categories — infra vs data vs other vs analysis
Explicitly labelled (the indexed set was generated to exclude non-analysis packages; a handful slipped in):

| Category | packages | workflows | note |
|---|---:|---:|---|
| **Analysis tools** | **1,753 (96%)** | 3,226 | genuine analysis workflows — the product |
| Infrastructure | 12 | 14 | S4/IO/container libs (Biobase, GenomicRanges, Rsamtools, SingleCellExperiment…) — used *inside* workflows |
| Data / annotation | 31 | 48 | data containers & annotation providers (alabaster.*, annotate, AnnotationHub…) |
| Other / utility / GUI | 22 | 22 | iSEE* GUIs, basilisk, *gui packages |

**Read:** ~**96% of indexed packages are analysis tools.** Bioconductor's large infra/data/annotation set (≈half of all Bioc download traffic — `S4Vectors`, `IRanges`, `BiocGenerics`, `org.*`, `TxDb.*`…) is **correctly excluded** from generation; only ~65 such packages slipped into the index.

## 3. Domain distribution (workflows)
transcriptomics 1,644 · genomics 571 · epigenomics 251 · proteomics 165 · variant_calling 134 · general 120 · systems_biology 95 · single_cell 77 · imaging 69 · metagenomics 57 · metabolomics 55 · genetics 23 · pharmacology 15 · drug_discovery 12 · immunology 9 · (others) ~14.

## 4. Coverage of the download universe
- **Top-650 by download (~85% of Bioc traffic):** 497 covered (76%); the uncovered ~153 are **dominantly infrastructure/data/annotation libraries** (correctly not workflows).
- **Of the *analysis-package* download traffic (the addressable ~48%): indexed covers ~83%; validated covers ~49%** (validated = stale/pre-fix; see §6).
- **Rising stars (recently-released, growing — first release ≥2021, 2025 ≥3000 distinct IPs): 292 packages → 489 workflows → 100% covered.**

## 5. Step-wise QC & output-visualization population (audited + refined this session)
Per-step metadata lives in DB column `step_metadata` (JSON array; each step = `{step, phase, outputs, visualizations, qc}`). Workflow-level rollups in `visualization_tools` / `qc_steps`.

| Field | Before | **After refinement** |
|---|---|---|
| workflows with `step_metadata` | 2,891 (87%) | **3,177 (95%)** |
| steps with **outputs** | 40% | **41%** |
| steps with **visualizations** | 22% | **24%** |
| steps with **QC** | 3% | **3%** |
| workflows with `visualization_tools` | — | 2,124 (64%) |
| workflows with `qc_steps` | — | 354 (11%) |

**What was refined:** the per-step enricher (`enrich_bioc_step_metadata.py`) splits steps by `# --- Step ---` markers and attributes viz/QC per section. It last ran *before* the B-1 fix added markers to 1,373 workflows — so **re-running it lifted coverage 87%→95%** (+285 workflows now have structured per-step metadata aligned to the real step markers). The QC vocabulary was also extended (voom, vsn, between-array normalization, normalization diagnostics, outlier).

**Honest read on QC = 3%:** this is **not** an under-population bug. QC operations (filtering, normalization, outlier/doublet detection) are genuinely concentrated in ~1 step per workflow; the QC_PATTERNS vocab is comprehensive (now 26 patterns) and extending it further added only +29 steps. ~24% of steps carry a visualization, which is the realistic rate (load/filter/transform steps don't plot).

## 6. Note on `runnable_status` (validation)
The registry's `runnable_status` reflects the **pre-fix** validation baseline (~1,092 workflows `ok`/`ok_warnings`). This session's execution fixes (B-2 input staging, dep bootstrap, heredoc, fixture corrections) target the `exec_error`/`fixture_failed`/unvalidated buckets but have **not been re-measured** — a validation wave would update these numbers.

## 7. Code alignment (checked)
- **Serving — aligned.** `_steps_from_db_metadata` (`nextflow_executor.py`) reads `visualizations`/`qc`/`outputs` per step and serves them; `get_nextflow_steps` prefers DB `step_metadata`, falling back to the parser only when a row is empty or degenerate (≤1 step) — fixed this session.
- **Residual gap (minor):** the ~133 workflows still without `step_metadata` (5%) are served by the `.nf` parser, which emits step **names only — no per-step viz/QC**. Closing it means either generating `step_metadata` for those 133 or teaching the parser to emit viz/QC (recommended follow-up; low impact).
