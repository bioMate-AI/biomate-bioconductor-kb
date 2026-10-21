# 2026-10-21 — Tutorial deck screenshot drift map (video vs current product)

Honest, per-asset audit of the embedded `assets/live/*.png` screenshots in the
v2_final walkthrough decks against the **current** dev product. Verdicts are
marked **VERIFIED** (I compared the asset to the live product this session) or
**UNCHECKED** (not yet compared — do not treat as known). Earlier I wrongly
claimed the drift was "bounded to 3 decks" by inference; it is not — this map
only records what was actually compared.

## Root-cause product changes that stale a screenshot

1. **Composer redesign** — the old composer showed separate **"Instructions"**
   (left) + **"Experts"** (right); the current one is a single **"Skills &
   experts"** dropdown pill (changed THIS session per user request). Any shot
   that includes the composer is stale.
2. **After-run Outputs→Results merge** — the old after-run had an **"Outputs"**
   tab with a **"Step | File"** table (and the pre-fix "run" step bug); the
   current after-run is a single **"Results"** tab (Findings Summary + Key
   Results w/ a **Source** column) + a **Reproducibility record** tab. Any shot
   of the old Outputs tab is stale.
3. **CN1C phantom-param fix** — SMILES-bearing preruns captured before the fix
   show a spurious **"CN1C"** parameter row. The current product does not.

(There may be further UI changes between the Oct-5/6 capture date and now; only
the three above are confirmed as drift sources so far.)

## Per-asset verdicts

| Asset | Decks | Verdict | Reason |
|---|---|---|---|
| `outputs.png` | d2, drug-dev, t3 | **VERIFIED STALE** | Old "Step\|File" Outputs tab + "run" step; current product = merged Results view |
| `t0-composer.png` | t0, t4 | **VERIFIED STALE** | Old Instructions/Experts composer; current = "Skills & experts" pill |
| `qsar-live-panel.png` | d1 | **VERIFIED STALE** | Old composer **AND** shows the **CN1C phantom-param bug** (now fixed) — demos a fixed bug as normal |
| `generative-live-panel.png` | d3 | **VERIFIED CURRENT (structure)** | Right-panel-only prerun; structure matches live product. Content flag: a "Synthesizability" param holds an aspirin SMILES (looks mis-mapped) |
| `survival-live-panel.png` | s4 | **VERIFIED CURRENT (structure)** | Right-panel-only prerun; structure current. Content flags: "drug discovery" domain tag, "no configurable parameters" |
| `de-results.png` | m2 | **VERIFIED DATA** | A DESeq2 results table (34,371 genes / 1,242 sig) in deck styling, "real BioMate run output" — content, not UI chrome |
| `prerun.png` | d2, drug-dev, t3 | **UNCHECKED** | Likely current-structure prerun, but may include the old composer — verify |
| `running.png` | d2, drug-dev, t3 | **UNCHECKED** | Running state; verify step-card chrome vs current |
| `completed.png` | d2, drug-dev, t3 | **UNCHECKED** | Completed header; verify vs current after-run |
| `record.png` | d2, drug-dev, t3 | **UNCHECKED** | Reproducibility record; verify vs current |
| `fep-live-panel.png` | d4 | **UNCHECKED** | — |
| `nca-live-panel.png` | s1 | **UNCHECKED** | — |
| `search-answer.png` | m1 | **UNCHECKED** | — |
| `accession-resolve.png`, `accession-routing.png` | m3 | **UNCHECKED** | — |
| `de-volcano.png` | m2 | **UNCHECKED** (likely data/chart) | — |
| `qpcr-results.png` | qpcr | **UNCHECKED** (likely data/chart) | — |
| `t0-lane.png` | t0 | **UNCHECKED** | Lane-preview UI — verify |
| `t1-form.png`, `t1-pareto.png`, `t1-rejection.png`, `t1-results.png` | t1 | **UNCHECKED** | App-shell/form UI — verify |
| `t2-model-object.png`, `t2-registry.png`, `t2-rounds.png`, `t2-run.png` | t2 | **UNCHECKED** | Model registry/object UI — verify |
| `t4-data-hub.png`, `t4-dataset-object.png`, `t4-quality.png` | t4 | **UNCHECKED** | Data hub/dataset UI — verify |

## What's confirmed so far

- **4 of 6 checked assets are stale or flagged** (`outputs`, `t0-composer`,
  `qsar-live-panel` stale; `generative`/`survival` current-structure but with
  content flags). The series has **systematically** drifted via ≥3 product
  changes, and at least one deck (d1) demos a **now-fixed bug** (CN1C).
- The discriminator: a shot is stale if it includes **the composer**, **the old
  Outputs tab**, or a **pre-fix SMILES prerun (CN1C)**. Right-panel-only preruns
  are structurally current.

## Recommendation

- Treat the series as **needs re-verification**, not "mostly fine." The
  `UNCHECKED` rows must be compared to the live product before any claim of
  currency — do not infer from the pattern.
- `current_ui_baseline_20261021/` holds the captured current after-run views to
  re-record against.
- Priority re-record targets (verified stale): the 3 ADMET decks' after-run +
  the composer shots in t0/t4, and d1's CN1C/composer panel.
