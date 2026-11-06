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

## Manuals — drift found (4 themes, ~20 locations; `W2`/`T3`/`T5` already current)

**Theme 1 — Composer label/order (old "Instructions"+"Experts").** Current =
a **"Skills & experts"** pill placed FIRST, then an **Instructions** affordance
(a button opening the project Instructions panel inside a project). Stale label/
order in: `I02-composer-talking-to-biomate.md` (:40, :120-128, :197, :213),
`I12-connectors-and-skills.md:84`, `I01-getting-started-cold-start.md:20`,
`overview/00-what-is-biomate.md:42`, `T0-getting-started.md:108`,
`T9-connecting-data-and-tools.md:235-236,245-246,254,280`, `A-glossary.md:20`.

**Theme 2 — Projects now DO carry per-project skills/experts.** The project
Instructions tab has a "Skills & experts" card persisting `skillPackIds` per
project. Docs saying the opposite: `T7-projects-and-collaboration.md:201-205`
("Experts are chosen per chat, not saved as a project switch … no per-project
switch") — now **FALSE**; `T9:235,252-255` ("the only skill/expert surface is the
composer") — stale; `I02:255` (lower confidence).

**Theme 3 — Residual "Outputs tab" language after the merge.** Outputs is a
**section inside Results**, not a tab. Fix: `I09-reports-and-reproducibility.md:52-54`
("the middle tab"), `I08-outputs-viewers-interactive.md:16,30` ("the Outputs tab").

**Theme 4 — Gated-off surfaces presented as live.** `/billing` + billing sidebar
are commented out (page crashes); `/drug-discovery-cro` + "CRO Library" sidebar
disabled; in-chat "Generate IND" handoff not wired. Fix: `I13-billing-quotas…md:32-33`
(+ billing section), `overview/00:61`, `I06-running-an-analysis.md:25`,
`tutorials/instruments/benchling-eln-lims.md:90,97`, `domains/drug-discovery-ind.md:77-78`.
(`S1-sidebar-navigation.md:255-264` correctly states these are off — the counter-reference.)

**Confirmed CURRENT (NOT drift):** Citations (`I09:70` honest hide-when-empty);
**Open Targets** — the research-agent path (`lookup_open_targets_gene`,
research_agent.py:990) IS wired; the `data_sources.py status="planned"` is a
*different* (data-plane) registry, and no manual claims that connector is live, so
no OT drift; DB/literature firing notes are honest; `W1` "three tabs" = the
workflow-panel tabs (unrelated).

**ZH mirrors** (`tutorials/zh/**`) inherit the same Theme-1/2/4 drift.

## Fix plan
- **Manuals (text edits, doable now):** Theme 4 first (dangerous — claims dead
  surfaces are live), then Theme 2 (a FALSE claim), then Themes 1/3 (label/merge).
- **Demos (pipeline):** re-capture 4 assets (`qsar-live-panel`, `t0-composer`,
  `t0-lane`, `outputs`) from current product → re-record 6 decks (d1/d2/drug-dev/
  t3/t0/t4, EN+ZH).
