# DIA-NN at cohort scale: why hundreds of runs take days on A100s — diagnosis, fix, and BioMate status

**Date:** 2026-09-08
**Context:** A user reported DIA-NN taking **days on parallel A100s** for a **cohort of hundreds of DIA runs**, with the **search phase** as the bottleneck; they want it *faster* and returning *more* results.
**Related:** `docs/20260907_PROTEOMICS_DB_SEARCH_OPTIMIZATION_SURVEY.md` (§6 DIA, §11 proposal, §14 benchmark)

---

## 1. Root cause — a hardware/algorithm mismatch, not a DIA-NN speed bug

DIA-NN is genuinely fast in the *easy* regime (normal proteome, empirical/modest predicted library, short gradients). "Days on A100s over hundreds of runs" means the workload is in the *hard* regime, and two things are almost certainly true:

1. **The A100s are idle during the slow part.** DIA-NN's **search and quantification are CPU-bound**; the GPU accelerates only the one-time deep-learning **spectral-library prediction** (fragment intensity / RT). So a search-phase bottleneck on GPU boxes means the expensive resource (A100) is doing nothing while CPU-starved search grinds. **The A100 is the problem, not the solution.**
2. **The per-run search space is being paid repeatedly.** In library-free mode DIA-NN predicts the whole in-silico library; doing that (or an equivalently heavy search) once per run across hundreds of runs is massively redundant. The cost is O(runs × spectra × candidates).

A search-phase bottleneck over hundreds of runs = **under-parallelized and/or library regenerated per run** — a wiring problem, not an algorithmic wall.

## 2. The fix — the standard large-cohort DIA-NN pattern (days → hours, no new tools)

1. **Generate the spectral library ONCE** (GPU does this fast) and reuse it for all runs — never per run. (Predict from FASTA, or build an empirical/consensus library from a subset.)
2. **Fan the per-run searches across many CPU nodes**, each run searched against that fixed library. This is the bottleneck phase and it is embarrassingly parallel.
3. **One joint step at the end** for match-between-runs (MBR) + quantification + global FDR (DIA-NN's "analyze separately, then combine": per-run `.quant` files → one joint pass).
4. **Reallocate the A100 budget to CPU cores.** GPUs help only the one-time library prediction.

**Magnitude:** if a single library-based run search is ~10–30 min, 200 runs serially ≈ 1.5–4 days (matches the report). Fan 200 across ~50 CPU nodes → ~1 h of search + one joint step. **Days → hours, no algorithm change.**

Secondary speed knobs: fix mass calibration (skip the auto-calibration re-search), tighten tolerances, restrict variable mods / digest specificity to what's biologically justified, run MBR only if needed (or in blocks). Version: DIA-NN 2.0 (2025) has speed/memory/large-experiment improvements over 1.8/1.9 — worth upgrading — but **no version changes the fundamental scaling of a giant per-run search**.

## 3. Getting MORE results (sensitivity)

- Higher-quality **predicted library** (Prosit/AlphaPeptDeep-grade fragment+RT).
- **Match-between-runs** across the cohort recovers peptides missing in individual runs.
- A **rescoring** pass (predicted-vs-observed features).
- **Validate the extra IDs with entrapment** — 2025 work shows DIA tools can under-control FDR, so "more" must be shown to be *real*, not FDR inflation.

## 4. Faster AND more, together — the retrieval reframing (long-term)

The per-run search is slow because it **scores the whole library against every spectrum**. Build the library into an **embedding + ANN index once, and query it from all hundreds of runs** — retrieve the few plausible candidates per spectrum in milliseconds (the DrugCLIP/Foldseek trick), exact-score only the shortlist. Build-once/query-hundreds-of-times is the ideal amortization case: the more runs, the bigger the payoff. This is the §11 PredictedSpec-ANN proposal, and this cohort workload is a direct real-world instance of the gap it targets.

---

## 5. Is this realized in BioMate already? — **Partially: the pattern is vendored, but NOT wired as a runnable capability.**

| Component | Status in BioMate | Evidence |
|---|---|---|
| **DIA-NN cohort subworkflow** (library-once → per-run → joint) | ✅ **Vendored nf-core code exists** — the exact 5-stage pattern | `backend/nf-core-modules/subworkflows/nf-core/dia_proteomics_analysis/main.nf`: `DIANN_INSILICOLIBRARYGENERATION` → `DIANN_PRELIMINARYANALYSIS` → `DIANN_ASSEMBLEEMPIRICALLIBRARY` → `DIANN_INDIVIDUALANALYSIS` (per-run fan-out) → `DIANN_FINALQUANTIFICATION` (joint) |
| DIA-NN module + in-silico library gen | ✅ vendored | `backend/nf-core-modules/modules/nf-core/diann/main.nf` (+ `diann/insilicolibrarygeneration`) — **pinned to DIA-NN v1.8.1** (old; not 2.0), biocontainer, `label 'process_high'` |
| **Exposed as a runnable BioMate workflow** (routing / workflow DB / registry) | ❌ **Not wired** | no reference to `dia_proteomics_analysis`/`diann` in routing, workflow DB, or registry (only conda-dependency noise); the vendored subworkflow is not reachable from chat/execution |
| **On AWS Batch with per-run fan-out** | ❌ not confirmed | no proteomics awsbatch profile / scatter wiring found for this subworkflow |
| **End-to-end run evidence** | ❌ none | no proteomics search run logged to S3 (consistent with the broader proteomics-untested finding) |
| What IS exposed | ⚠️ **downstream only** | `msqrob2` (`dia_precursor_workflow.nf`) and `DEqMS` consume DIA-NN's `report.parquet` for differential abundance — i.e., BioMate handles the **after-search** analysis, not the search fan-out |

**Bottom line:** BioMate has the *ingredients* — the canonical nf-core DIA-NN cohort subworkflow (library-once + per-run + joint) is vendored in `backend/nf-core-modules/`, and the downstream differential-abundance workflows are live. But the **cohort-scale search fan-out is not realized as a usable capability**: it isn't exposed/routed, isn't confirmed wired to Batch per-run parallelism, is pinned to old DIA-NN v1.8.1, and has no run evidence. So today BioMate could **not** out-of-the-box solve the user's "hundreds of runs, days on A100" problem — realizing it requires (a) exposing/wiring `dia_proteomics_analysis` as a runnable workflow, (b) confirming the per-run `DIANN_INDIVIDUALANALYSIS` step fans out across Batch CPU nodes, and (c) bumping DIA-NN to 2.x.

## 6. Recommended next steps (BioMate)
1. **Expose `dia_proteomics_analysis`** as a routable BioMate workflow (add to workflow DB/registry) and confirm `DIANN_INDIVIDUALANALYSIS` scatters per-run on Batch CPU queues (not GPU).
2. **Bump DIA-NN to 2.x** in the module container.
3. This becomes a real product capability — "**DIA cohort at scale: library once → parallel per-run search → joint quant**" — and shares infrastructure with the Phase-0 search benchmark (`evaluation/datasets/proteomics_search_benchmark/`).
4. Longer term, slot the embedding/ANN retrieval index (§11) into the per-run search step so the build-once/query-hundreds amortization kicks in.
