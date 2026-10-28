# Data panel: unified file actions + auto analysis (distribution + data-QC) — design

**Date:** 2026-10-28
**Status:** Design, from user direction (2026-10-28 session). Captures the data-panel vision so
it's built as one coherent feature, not piecemeal. Frontend vs backend split called out.

## Vision (user directives, verbatim intent)
1. **Unify file actions into the dataset (data) panel.** Open-in-Jupyter / RStudio / **Analyze**
   live on the dataset object, not duplicated per-file in the Outputs tab. "Each output can be
   opened in files anyway" → an output row opens INTO the dataset panel, which owns the actions.
2. **dataset-object = 3 tabs** (Preview · Versions · Where-it-came-from) **+ Analyze / Jupyter /
   RStudio actions** — "are enough." Do NOT expand to the design's 6-tab set.
3. **Auto-generate distribution figures** for appropriate data types (follow the design), shown
   in the data panel.
4. **Auto DATA-QC**, shown in the data panel "wherever appropriate." **DATA QC ≠ WORKFLOW QC** —
   this is dataset quality (completeness, missing %, distribution/outliers, type/format validity,
   domain checks e.g. RIN / A260·280), NOT the run's QC gates/audit (those stay in the run).
5. **Random-pick sampling for large data** — both the distribution figures AND data-QC compute on
   a *random* sample (not head-N, not full) when the dataset is large.
6. **Compute once per data VERSION, cache it.** The analysis "should only be done once unless the
   version of data is updated" — "we don't want it hanging there" (recomputing on every view). So
   the analysis is computed at ingest/version time, cached keyed by (dataset, version), and the
   panel READS it. Re-run only when a new version lands.
7. **Data manipulable wherever feasible** — the data table supports sort / filter / (where
   feasible) edit / transform, not a static dump.

## Architecture (the caching model is the crux)
The "once per version, cached" rule makes this fundamentally a **backend/profiler** feature with a
**frontend display** layer. Client-side-compute-on-render (a histogram recomputed every open) is the
exact "hanging there" the user rejects.

### Backend (the real feature)
At dataset ingest / new-version creation, the profiler computes **once** and **persists** (keyed by
`{datasetId, version}`):
- **column profile** (names, types, % missing, distinct) — the Columns tab's real data.
- **distribution figures** per appropriate numeric column (histogram / density), from a **random
  sample** when `rows > N` (store the sample size + seed for honesty).
- **data-QC report**: completeness, out-of-range/outliers, type/format validity, duplicates, and
  domain-aware checks where the modality is known (RIN/RNA purity, FASTQ Q-scores, etc.), with
  pass/warn/fail per check — on the **same random sample**.
Served via the dataset profile endpoint (extend the existing one) so the panel reads cached results;
a version bump invalidates + recomputes. Large-data safety = sample, never full-scan on read.

### Frontend (display + manipulate)
- **dataset-object panel** reads the cached profile/distribution/QC for the current version and
  renders: Preview (Table/Columns/**Plot=distribution**), a **Data-QC** summary (badges + the
  check list) "wherever appropriate", the 3 tabs, and the **Analyze / Jupyter / RStudio** actions.
- **Manipulable table**: sort + filter (client-side on the sample; "full paging uses the table
  viewer" for the whole set) where feasible.
- **Outputs tab**: an output row's primary action opens it **in the data panel** (dataset object) —
  the single place for preview + actions — instead of per-file RStudio/Jupyter buttons.

## Build plan (phased; stop/confirm between)
**Phase 1 — frontend-only (no backend), low risk:**
- dataset-object: add **Analyze / Jupyter / RStudio** actions (keep 3 tabs).
- Outputs tab: route "open" to the dataset panel; drop the redundant global Interactive panel /
  per-file duplication → unified.
- Table: add client-side **sort + filter** on the sample.
- Keep the **client-side sample histogram** (`dataset-sample-plot.tsx`, already shipped) as the
  *instant preview* of the already-fetched sample — it's tiny/instant, not "hanging", and is honest
  ("N-row sample"). Mark it as the interim until the backend-cached distribution lands.

**Phase 2 — backend (the real "compute once per version, cached"):**
- Profiler computes + persists column-stats + distribution + data-QC per `{dataset, version}` on a
  random sample for large data; endpoint serves cached results; version bump recomputes.
- Frontend swaps the interim client histogram for the cached distribution + renders the Data-QC
  panel from the cached report.

## Not this (scope guards)
- Do NOT conflate with **workflow QC** (run gates/audit) — different surface, stays in the run.
- Do NOT re-expand the dataset-object to 6 tabs.
- Do NOT recompute analysis on every panel open (the whole point of the cache).
- Do NOT build the redundant inline chart primitives in the findings/figure path (reverted — produced
  plot images already cover run outputs; see `docs/20261028_UI_WORKFLOW_DESIGN_COMPARISON.md`).

## Status so far
- Plot tab un-stubbed with the client-side sample histogram (`3c8675b09`) — Phase-1 interim.
- Reproducibility-record accordion (WORKFLOW QC/repro) commented out of the Report tab (`17c15083e`).
