# 2026-10-21 — Tutorial deck screenshot drift map (COMPLETE)

Per-asset audit of every embedded `assets/live/*.png` in the v2_final walkthrough
decks vs the CURRENT dev product. All assets were viewed directly (6 by the lead,
21 by three parallel agents). Verdicts: **STALE** (UI the product no longer has),
**CURRENT** (structure matches live product), **DATA** (deck-styled table/chart —
content, not UI chrome).

## Root-cause product changes that stale a screenshot
1. **Composer redesign** — old = separate "Instructions" (left) + "Experts"
   (right); current = single "Skills & experts" pill. Any shot with the old
   composer is stale.
2. **After-run Outputs→Results merge** — old = an "Outputs" tab with a
   "Step | File" table (+ the pre-fix "run" step); current = a single "Results"
   tab (Findings + Key Results w/ Source column) + a "Reproducibility record" tab.
3. **CN1C phantom-param fix** — pre-fix SMILES preruns showed a spurious "CN1C"
   param row. (Note: a `CN1C=…` string *inside* a Smiles List value is caffeine,
   NOT the bug.)

## STALE — needs re-capture/re-record (only 4 assets)
| asset | decks | why stale |
|---|---|---|
| `outputs.png` | d2, drug-dev, t3 | old "Step\|File" Outputs tab with "run" step; product is now the merged Results view |
| `t0-composer.png` | t0, t4 | old Instructions/Experts composer |
| `t0-lane.png` | t0 | old Instructions/Experts composer (lane-preview shot) |
| `qsar-live-panel.png` | d1 | old composer **AND** the CN1C phantom-param bug (demos a now-fixed bug) |

**Decks to re-record:** d1, d2, drug-dev, t3, t0, t4.

## CURRENT (structure matches live product) — no UI drift
fep-live-panel (d4), nca-live-panel (s1), survival-live-panel (s4),
generative-live-panel (d3), t1-form (t1), t2-model-object/registry/rounds/run
(t2), t4-data-hub/dataset-object/quality (t4), search-answer (m1), and the shared
ADMET `prerun.png` / `running.png` / `completed.png` / `record.png` (d2/drug-dev/t3).
Notably `completed.png` + `record.png` already reflect the merged Results /
Reproducibility-record design — only `outputs.png` from that set is stale.

## DATA (content, not UI chrome)
de-results, de-volcano (m2); qpcr-results (qpcr); t1-pareto, t1-rejection,
t1-results (t1); accession-resolve, accession-routing (m3).

## Content/quality oddities (not UI drift, but worth fixing)
- **Degenerate/placeholder data:** t1-pareto points collapse to a flat line;
  t1-results `property_envelope` all `0`; qpcr is explicitly "(demo)" data.
- **Cold-start/empty:** the whole t2 set is empty-project (all `0`,
  `not_evaluated`); `t2-rounds` is the **empty-state** card — the closed-loop
  *trajectory* is shown with NO loop running, not a populated trajectory.
- **Mis-labels:** `nca` name renders as slug "Nca Pknca" and PKNCA is tagged
  "drug discovery"; `generative` "Synthesizability" param holds an aspirin SMILES;
  `survival` tagged "drug discovery" with "no configurable parameters".
- **Test debris:** `t4-data-hub` shows a junk 1-byte `editor.txt` with a red
  quality dot and a test-project name ("E2E Team Test …").
- **Render glitch:** `search-answer` has overlapping tab labels near Citations.

## Re-record scope (bounded)
Re-capture 4 assets from the current product — `qsar-live-panel`, `t0-composer`,
`t0-lane`, `outputs` — and re-record the 6 decks that embed them (d1, d2,
drug-dev, t3, t0, t4), EN + ZH. Everything else is current or data. The content
oddities above are a separate data-quality pass (not UI drift).

## Manuals
`W2-after-run-panel.md`, `T3`, `T5` verified CURRENT earlier. Full manual audit in
progress (separate agent) — results appended when in.
