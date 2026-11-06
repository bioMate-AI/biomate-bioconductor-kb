# Manual / Tutorial Screenshot Re-capture Spec (committee bucket "all other screenshots")

**Date:** 2026-10-13. **Source:** vision committee first-pass (`docs/20261013_SCREENSHOT_COMMITTEE_REVIEW.md`, 3 frontier models, 56 assets). **Scope:** the 39 assets the committee rated major (n_major≥2) that are NOT the 6 B-recipe pilots nor the 3 A product fixes — i.e. "all the other screenshots".

## Finding
The overwhelming majority are **stale or wrong-state captures, not product bugs**. Two systemic causes, both already solved in principle:
1. **Redesign drift** — the after-run surface was redesigned (merged **Results** view; "Download report" → **"Download findings"**; 3-tab nav → Results/Reproducibility; idle/running/completed states). ~21 images predate it.
2. **Fixture pollution + wrong recipe** — old captures used the polluted `E2E File Tree 1789…` project (duplicate "IL-17A Cyclic Peptide Pilot" cards, timestamped names, 1× DPR, full-page crop). The **B recipe** fixes this: clean `MG PBMC — sample data demo` project, content-column crop, deviceScaleFactor=2. Proven on the 6 B pilots (5/6 → minor/ok) and i05-1/i05-2 re-captures.

So the bulk is a **comprehensive re-capture pass against current UI, driven into the correct state per shot** — not code. A small set needs the fixture driven into a state first (instruments, members, versions, seeded chats), one is a possible viz bug (pareto), and one is a route decision (CRO).

## Execution plan
1. **Blocked until the GPU capture fork frees dev** (captures can't share dev with the GPU run-discovery). Build/iterate the harness then.
2. Extend `frontend/e2e/manual-screenshots.e2e.ts` with the B recipe to cover every RECAP + STATE shot below (after-run shots reuse `/debug/afterrun/<run>` with the ADMET run `c79a9ccc`; completed/record states already render there).
3. Sync the A fixes (8916ae90d) first, then the 4 CODE+RECAP shots.
4. Re-score the re-captured set via the 3-model committee; target: 0 major.
5. **Decisions needed:** the 10 `unreferenced` orphans — delete or wire into a manual page? CRO `i13-1` — un-hide `/drug-discovery-cro` or drop the figure?

## Shot list

### ✅ Done (no action) (5)

| Asset | Manual page | Route | Target state | Required elements |
|---|---|---|---|---|
| `i05-1-file-tree` | I05 files | /files → clean demo project | idle (tree) | inputs tree + quality dots; reader-facing project name |
| `i05-2-dataset-header` | I05 dataset | /files → counts_matrix.csv | Preview+Quality | green Good pill, rich table, consistent Notes |
| `m0-1-intent-bar` | T0 getting-started | / | cold-start | intent bar + module cards |
| `m1-1-search-module` | M1 search | / | cold-start | Search & evidence module |
| `m2-1-data-analysis-module` | M2 data-analysis | / | Validated-workflows tab | domain rows + demo chip |

### Re-capture after A-fix sync (4)

| Asset | Manual page | Route | Target state | Required elements |
|---|---|---|---|---|
| `i11-3-multi-objective` | I11 design | live design run | candidates table | verdict tooltip/help (A2) |
| `i12-1-connectors-dialog` | I12 connectors | sidebar → Connectors | Scientific Databases tab | where-it-runs from residency (A5) |
| `r-fail-state` | W2 (unref) | failed run | running/failed | overall bar ≤99 while running (A3) |
| `t11-2-design-candidates` | T11 (unref) | live design run | candidates | verdict vs envelope clarity (A2) |

### Re-capture (stale / wrong state) (21)

| Asset | Manual page | Route | Target state | Required elements |
|---|---|---|---|---|
| `i05-0-data-hub` | T10 datasets | /files → select demo project | two-pane w/ CSV open | file tree + open dataset (de_results.csv); no dup project cards |
| `i08-1-outputs-tab` | I08 outputs | /debug/afterrun/<run> | Results→outputs | generating-step identity (not all 'run'); scroll cue |
| `i09-1-three-tabs` | I09 (unref) | /debug/afterrun/<run> | Results landing | no stale 'Download report' |
| `i09-2-reproducibility-record` | I09 reports | /debug/afterrun/<run> | Reproducibility record | 'Download findings' label |
| `r-merged-results-view` | W2 after-run | /debug/afterrun/<run> | completed Results | merged Results tab; 'Download findings' (not report); no 3-tab nav |
| `r1-prerun-param-strip` | T11 drug-dev | live design send | pre-run | generated candidates/objective columns view |
| `r2-running` | T11 drug-dev | running run | running | QC gate upper-bound comparison shown correctly |
| `r2b-running-metrics` | T11 (unref) | running run | running+metrics | no stale 'Generating workflow…' once running |
| `r5-outputs` | W2 after-run | /debug/afterrun/<run> | completed Results→outputs | populated Findings first, then inline outputs |
| `r6-reproducibility` | W2 after-run | /debug/afterrun/<run> | Reproducibility record tab | Results/Reproducibility nav (not 3-tab) |
| `r8-completed-chat-and-panel` | W2 after-run | live completed run | completed chat+panel | merged Results nav; consistent name |
| `t10-1-dataset-preview` | T10 datasets | /files → results CSV | preview | real CSV headers+rows |
| `t3-1-workflow-panel` | T3 run+report | live send | idle pre-run | Workflow settings idle (not completed After-run) |
| `t3-2-after-run-summary` | T3 run+report | /debug/afterrun/<run> | Results tab | either show findings OR the withheld-state copy consistently; include tab nav |
| `t3-3-after-run-outputs` | T3 run+report | /debug/afterrun/<run> | Results→outputs | visible step grouping (not all 'run') |
| `t3-4-after-run-reproducibility` | T3 run+report | /debug/afterrun/<run> | Reproducibility | Results/Reproducibility nav |
| `w1-0-panel-overview` | W1 (unref) | live run panel | overview | current after-run tabs + label |
| `w1-2-workflow-settings` | W1 panel | live send | idle settings | file field w/ Browse + AI-filled value badge/Override; numeric controls |
| `w2-failed-run` | W2 (unref) | failed run | failed | clear failure cause (not bare Graphviz WARN); current tabs |
| `w3-1-step-row` | W3 (unref) | run panel step | step row | unc_clipped param line + workflow row; one language |
| `w3-2-fullstep-provenance` | W3 (unref) | run panel step | provenance | 'ADMET' caps; '0 non-default parameters' |

### Drive fixture into state, then capture (8)

| Asset | Manual page | Route | Target state | Required elements |
|---|---|---|---|---|
| `s1-1-sidebar` | S1 sidebar | / with chat history | populated | a few chats incl. colored status dots |
| `t10-2-dataset-lineage` | T10 datasets | /files → dataset Lineage | lineage w/ run | Status row present; live provenance retained |
| `t10-4-dataset-versions` | T10 datasets | /files → dataset Versions | v2 exists | added v2 entry: note, author, timestamp |
| `t6-1-instruments-tab` | T6 instruments | Settings→Instruments | 1 instrument registered | instrument row w/ status + residency badge |
| `t7-0-project-overview` | T7 (unref) | project overview | filled | unobscured Standing-instructions heading; logo not clipped |
| `t7-1-standing-instructions` | T7 collab | project → Standing instructions | filled | filled content + 'Read by the assistant…' subtitle; Private + Notes |
| `t7-2-members-roles` | T7 collab | project → Members | 2 members added | postdoc(Editor)+collaborator(Viewer) w/ role dropdowns; share link+Copy/Revoke |
| `w1-1-phases` | W1 panel | running run | mid-run | one step DONE + one RUNNING; consistent elapsed |

### Content / product look (1)

| Asset | Manual page | Route | Target state | Required elements |
|---|---|---|---|---|
| `t11-3-pareto` | T11 (unref) | design run pareto | pareto plot | non-dominated frontier shown (not all dominated) |

### Needs your decision (1)

| Asset | Manual page | Route | Target state | Required elements |
|---|---|---|---|---|
| `i13-1-cro-library` | CRO (unref) | /drug-discovery-cro | library | real CRO page (route is hidden → 404) |

## Orphans — resolution (2026-10-13, per "if useful, add into manual")

All 10 confirmed truly unreferenced (grep across `docs/user-manual/**.md`). Decision per asset:

**Wired into a manual page (5)** — each goes to a page that *lacked* that figure; they now get re-captured with everything else:
- `w3-2-fullstep-provenance` → `tutorials/W3-full-step-view.md` §1 (the full step view object — the tutorial's subject; page had no figures).
- `w3-1-step-row` → `modules/I07-full-step-view-provenance.md` (the step-row Details entry point; page had no figures).
- `w2-failed-run` → `tutorials/W2-after-run-panel.md` §8 "When a run failed" (no failed-run figure existed).
- `i09-1-three-tabs` → `modules/I09-reports-and-reproducibility.md` (the Results-landing figure; only the reproducibility figure existed).
- `t7-0-project-overview` → `tutorials/T7-projects-and-collaboration.md` intro (establishing project overview).

**Held (1):** `t11-3-pareto` — do NOT wire until the re-capture confirms the Pareto frontier actually renders (committee: "all dominated, no non-dominated front" — a possible viz bug, not just a stale shot). Wire into `modules/I11` only after the viz is verified correct.

**Left un-referenced, NOT deleted (3):** `r-fail-state` (redundant with the wired `w2-failed-run`), `r2b-running-metrics` (redundant with `r2-running`), `w1-0-panel-overview` (redundant — W1 already has 5 current figures). Kept on disk pending explicit removal instruction.

**Blocked on a route decision (1):** `i13-1-cro-library` — shows a 404 because `/drug-discovery-cro` is intentionally commented out. Cannot be captured truthfully until the route is un-hidden; not wired.
