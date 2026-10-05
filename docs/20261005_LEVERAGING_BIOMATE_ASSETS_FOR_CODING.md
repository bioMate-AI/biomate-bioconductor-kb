# Leveraging BioMate's accumulated workflows/code/docs for the coding capability

**Date:** 2026-10-05. The build has produced a large, *already-execution-verified* corpus. This is the
"data engine" from `20261005_LOCAL_LLM_CODING_CAPABILITY_AND_PLAN.md` §4 — except it **already exists**
(historical), so we can bootstrap the coding track NOW instead of only generating data live.

> **Scope correction (2026-10-05):** the asset is the **full ~4,209-workflow catalog**, not just the 1,092.
> The 1,092 is only the subset where we currently hold *committed execution receipts* (`real_exec_status
> ok`); **"no receipt" ≠ "broken."** The other ~3,100 are curated, indexed workflows (real descriptions,
> params, steps, `nextflow_path`; many nf-core/Bioconductor pipelines that genuinely run) — fully usable for
> retrieval/adaptation and pattern training. The 1,092/4,209 distinction binds **only** for *execution-graded
> gold* (a positive "it ran" label); and it is a **floor we grow**, not a ceiling — stub-running / running
> more of the 4,209 mints new receipts cheaply and expands the verified set toward the whole catalog.

## Inventoried assets (counted 2026-10-05, this repo)
| Asset | Count | Value |
|---|---:|---|
| `.nf` files (repo) | **5,088** | code corpus (but see honesty: not all tested) |
| — of which real-execution-**validated** | **~1,092** (`real_exec_status IN ('ok','ok_warnings')`) | **GOLD** — known-good .nf w/ execution evidence |
| — nf-core-workflows / modules | 47 / 12 | curated, runnable patterns |
| — biomni_workflows generated stubs | 4,491 | syntax/structure exposure only (weaker signal) |
| session docs | **2,129** | decision + **fix-chain** corpus |
| git commits w/ "fix" touching `.nf` | **841** | (broken→fixed) repair pairs |
| executor fix-commits | **159** | execution-path repair knowledge |
| enriched catalog DB | 324 MB | index: intent↔params↔steps↔nextflow_path↔exec-status |
| Bioc-KB validated steps | 15,641 | structured R/Bioconductor code knowledge |

## Four uses (mapped to skills + training)
1. **Retrieval / adaptation library (skills — biggest immediate win for "convert existing → Nextflow").**
   Embed the **whole ~4,209-workflow catalog** (all their .nf + descriptions) so the `convert-to-nextflow` /
   `adapt` skill retrieves the nearest known-good workflow and modifies it (reuse the existing
   `UnifiedWorkflowSearch` infra). **Breadth is the value here** — more templates = better coverage;
   adaptation from any curated workflow is far more tractable for a 9B than blank-page generation.
2. **Positive code-SFT pairs (training).** Each catalog workflow (all ~4,209) + its description/params/steps
   → `(intent/spec → .nf)` pairs (and the reverse, code→explain), giving broad Nextflow-pattern supervision;
   the **1,092 execution-validated** carry a graded "it ran" positive label (highest weight), the rest are
   curated-but-unreceipted (still real signal, labelled by provenance). The Bioc-KB structures 15,641 steps
   this way. Curated/tested code is the antidote to the synthetic-SFT regression we saw on out-of-catalog
   (0.124→0.099).
3. **Repair/fix SFT (training — the hardest data to get, and we have it for free).** Mine the **841 + 159
   fix-commits**: `git diff` (broken→fixed .nf) + the commit message (the *why*) = `(broken code + error →
   fix + rationale)` triples. Augment with the docs fix-chains (PRE_SYNC incidents, the GSE22055 6-fix
   chain, executor container-resolution, PEP-604-on-3.9, DSL-version drift). This is exactly the
   autofix/repair-competence signal the harness can't manufacture.
4. **Benchmark task source (measurement).** Derive the Nextflow benchmark's convert/fix/write tasks from
   **real** tested workflows and **real** historical bugs — authentic and gradeable (we know the correct
   output because it ran). Held out from training.

## Pipeline (ordered)
1. **Harvest** (CPU, cheap): (a) extract validated-.nf gold + metadata from the 324 MB DB; (b) mine the
   841+159 fix-commits into repair triples via `git log -p`; (c) extract docs fix-chains. Emit
   provenance-labelled JSONL.
2. **Clean/split:** dedup; **provenance-label** every record (source, exec-status, commit SHA); **leakage-
   split by workflow family** so the benchmark + a held-out eval are never trained on. (Include all +
   provenance-label; separate train/eval by reporting, not by exclusion — per the no-data-exclusion rule.)
3. **Wire to the two tracks:** retrieval library → the `convert/adapt/fix` skills; spec↔code + repair
   triples → the execution-grounded code-SFT dataset.
4. **Train** (code-SFT/RL) → **measure** on the held-out Nextflow benchmark → iterate, with the live
   verify-fix loop adding fresh verified trajectories on top of the historical seed.

## Honesty flags
- **The asset is the full ~4,209 catalog; use all of it** for retrieval + pattern-SFT. The 1,092 is only
  the *execution-receipt* subset → it gets the highest weight as graded positives and anchors the benchmark
  gold, but it is NOT the limit of usable workflows and absence of a receipt ≠ broken. (Separately: 5,088
  `.nf` *files on disk* ≠ 4,209 *catalog workflows* — the file count includes duplicates + generated stubs;
  dedup against the catalog's `nextflow_path` and provenance-label stubs vs curated vs receipted.)
- Fix-commit mining is noisy (not every "fix" commit is a clean repair pair) → needs filtering; report
  yield honestly, don't claim all 841 as usable pairs until extracted.
- Benchmark/eval workflows must be **held out** from the SFT corpus (family-split), or the coding numbers
  are leakage-inflated.
