# Leveraging BioMate's accumulated workflows/code/docs for the coding capability

**Date:** 2026-10-05. The build has produced a large, *already-execution-verified* corpus. This is the
"data engine" from `20261005_LOCAL_LLM_CODING_CAPABILITY_AND_PLAN.md` §4 — except it **already exists**
(historical), so we can bootstrap the coding track NOW instead of only generating data live.

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
   Embed the **validated** .nf + catalog so the `convert-to-nextflow` / `adapt` skill retrieves the nearest
   known-good workflow and modifies it (reuse the existing `UnifiedWorkflowSearch` infra). Converting by
   adaptation from a tested template is far more tractable for a 9B than blank-page generation.
2. **Positive code-SFT pairs (training).** Each validated workflow + its catalog description/params/steps →
   `(intent/spec → correct .nf)` pairs (and the reverse, code→explain). The Bioc-KB already structures
   15,641 steps this way. These are **real, tested** → the antidote to the synthetic-SFT regression we saw
   on out-of-catalog (0.124→0.099).
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
- **5,088 .nf ≠ 5,088 tested.** The gold is the ~1,092 execution-validated + nf-core curated; the 4,491
  generated stubs are syntax/structure exposure, NOT correctness gold — label and weight accordingly.
- Fix-commit mining is noisy (not every "fix" commit is a clean repair pair) → needs filtering; report
  yield honestly, don't claim all 841 as usable pairs until extracted.
- Benchmark/eval workflows must be **held out** from the SFT corpus (family-split), or the coding numbers
  are leakage-inflated.
