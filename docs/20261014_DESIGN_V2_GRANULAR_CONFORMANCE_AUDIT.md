# Design v2 — Granular Conformance Audit (2026-10-14)

Comprehensive, element-level comparison of the live dev UI (dev-public.biomate.ai)
against the `reference/claude_design/data_centroid_design_v2` reference (15 spec
surfaces 00–14 + `dataui/*.jsx` + CSS tokens). Five parallel auditors, one shared
rubric, comparing at the level of **color tokens, typography, spacing, shape,
component states, element presence, interaction pattern, and IA** — not "does it
render." Per-cluster source tables live in `scratchpad/audit_{1..5}_*.md`.

**Scope of certainty:** clusters 1, 4, 5 captured live dev screenshots; clusters 2
and 3 are code-level (one fork env lacked Chromium, one hit the slow chat→panel
flow) — ground truth for tokens/typography/spacing, but a browser render pass is
still owed for a few items (tagged **[LIVE?]**). None of these auditors changed
source — audit only.

## Totals
**~55 deviations: 10 HIGH · 27 MED · ~18 LOW.**

| Cluster | Surface | HIGH | MED | LOW |
|---|---|---|---|---|
| 1 | Foundations, tokens & shell | 3 | 5 | 2 |
| 2 | Composer & chat | 1 | 6 | 3 |
| 3 | Workflow panel & step view | 2 | 8 | 9 |
| 4 | Search, data & models | 2 | 4 | 2 |
| 5 | Reports, panes & previews | 2 | 4 | 3 |

---

## The keystone finding (fix first)

**The oklch token migration is only half done.** Most of the app still renders on
the inherited **shadcn HSL** tokens (`--background: 206 56% 99%`,
`--primary: 202 100% 37%`, `--muted`, `--card`, `--popover`…); only `--accent`,
`--border`, and the `.wf-panel`-scoped `workflow-panel.css` were moved to the
design-v2 **oklch** palette (`themes.css`). So **only the workflow panel truly
looks like design v2** — every other surface (sidebar, composer, chat, models,
data, reports) renders on the old palette. This single fact is the structural root
of "it doesn't look like design v2," and almost every other theme below descends
from it (`index.css:18-70`, `reference-design.css:10-80` vs `dataui/themes.css`).

## Cross-cutting themes (what makes it read as "not professional")

1. **Incomplete token migration** (keystone) — two color systems coexist. → C1#1
2. **Hard-coded hex instead of tokens** (no dark-mode adaptation), all descending
   from #1:
   - QC gate measured/threshold numbers use `var(--red,#dc2626)`/`var(--green,#16a34a)`
     — `--red`/`--green` are **undefined**, so generic hexes, a different red/green
     than the rest of the panel (`nextflow-workflow-viewer.tsx:2925,2929`). → C3#6
   - Model / model-case verdict dots use Tailwind `#22c55e/#ef4444/#f59e0b/#94a3b8`
     (`model-object.tsx:24-27`, `model-case.tsx:36-40`). → C4#1
   - Param origin badges use Tailwind `amber-100/blue-100` classes. → C3#7
   - Status/domain chips use shadcn `Badge` outline, not `.chip` tokens. → C4#7
3. **Typography: sans where the design specifies mono.** Design uses `--font-mono`
   for object-titles (600 17px/-0.01em), section eyebrows (`.k2` 9.5px uppercase
   .12em dim), and chat who-labels (`.who` 9.5px mono .13em mixed-case). Impl uses
   the UI sans font + different sizes/tracking throughout. → C2#5, C4#3, C4#4
4. **Generic shadcn primitives vs the design's dense token cards.** `Card`
   (rounded-lg, ~24px padding, elevated white) where design wants `.card2`
   (1px `--border`, `--r-md`, `--bg-elev`, 14px padding). → C4#5, C3#8, C2#1
5. **Nav / IA gaps.** "Workflows" demoted out of primary nav (→ Settings); no Data
   rail / no "Data" nav entry for the first-class dataset object; project tree
   shows only "Instructions" (no Files/Runs/Models). → C1#3, C1#5, C1#6, C1#8, C4#6
6. **Interaction completeness.** Full step view is a read-only preview (spec 08
   wants params **editable in place** + prev/next/lineage traversal; the revert
   button is currently dead code); panes are fixed-width (no resize grip /
   collapse-to-rail per `Resize.jsx`); a non-previewable `.rds` opens a ~90%-empty
   full-height pane that looks broken. → C3#1, C3#2, C5#5, C5#1
7. **Distinct bugs.** Double composer on cold-start (centered launcher **and**
   bottom bar both render). → C1#2

## What is already conformant (verified — don't touch)
- Per-phase **status colors are faithful** to `wfpanel.css` (running=`--accent`,
  completed=`--ok`, failed=`--err`); steps mirror it. (C3)
- Report/preview surfaces are **right-anchored panes, not modals**; after-run opens
  with the **RUN ORIGINAL** immutable badge; **reproducibility bundle** present;
  findings are **evidence-linked** with a Source column; the full `Viewers.jsx`
  evidence set (pLDDT / PAE / seq-tracks / hit-grid) is wired. (C5)
- Body font **Inter**; `.sidecap` "WORKSPACE" caption styling exact; 4 cold-start
  capability cards match the design lane set; logo un-clipped at 1440w. (C1)

---

## Fix plan (leverage-ordered)

**Phase 0 — Token foundation (keystone; careful visual QA, repaints whole app).**
Complete the oklch migration: map every shadcn HSL token in `index.css` /
`reference-design.css` (`--background/foreground/primary/secondary/muted/card/
popover/input/ring/destructive…`) to the design-v2 oklch palette; align dark
`--bm-*` values to `themes.css` exactly (C1#4); add the `--r-sm/--r-md/--r-lg`
radius scale (C1#9). Then re-capture every surface to QA contrast before sync.

**Phase 1 — Eliminate hard-coded colors.** Replace all Tailwind-hex status colors
with tokens: QC numbers → `--err`/`--ok` (C3#6); model/case verdicts →
`--ok/--err/--warn/--text-dim` (C4#1); origin badges → `--warn`/`--accent` (C3#7);
chips → `.chip` tokens (C4#7). Depends on Phase 0.

**Phase 2 — Typography system.** Mono object-titles (C4#3), mono `.k2` eyebrows
(C4#4), mono who-labels (C2#5). One shared text-role set.

**Phase 3 — Composer.** Contained 660px elevated `.composer2` card with the `.crow`
top divider + `bg-elev` (C2#1–3); collapse the three attach controls to one
"+ data" (C2#4); remove the double composer on cold-start (C1#2); drop the
tailed user bubble + proactive-suggestion avatar (C2#6, C2#7).

**Phase 4 — Nav / IA.** Restore top-level "Workflows" (C1#3); add a "Data" entry /
datarail (C1#5, C1#8, C4#6); project tree Files/Runs/Models (C1#6).

**Phase 5 — Component density & panes.** shadcn `Card` → `.card2` density
(C4#5, C3#8); resizable/collapsible panes per `Resize.jsx` (C5#5); size
non-previewable panes to content (C5#1); table shape header + column profile +
rounded cells (C5#4); route the model worked-case (C4#2).

**Phase 6 — Step-view interactivity.** Editable-in-place params + Apply&re-run
(C3#2), prev/next/lineage footer (C3#1), evidence badges (C3#3), open-as-dataset
(C3#4), dock/full-window toggle (C3#5), port `.deep*`/tab CSS (C3#8, C3#9).

**Phase 7 — Chrome micro-spacing** (C3#11–19): panel name 17px, letter weight 600,
phase/step paddings + dot offsets, param-row 160px, footer/button heights, etc.

**Browser-pending verifications:** PDF figure thumbnails render as gray boxes
(C5#2 — confirm it's not a headless artifact); composer + phase/section tab render
(C2, C3#9, C3#19); the cryo "Dataset Id" panel (server data is clean per dev logs
— confirm no composite is user-visible).

---

## Note on the parallel cryo `dataset_id` thread
Dev logs (read-only SSM) show the server data is clean: Node sends
`manifest_dataset_id` + `file_path` as separate clean keys; Python returns
`required_params=[movies_path]` only; no server map carries a composite `dataset_id`.
Five earlier Node normalization commits added defensive `normalizeCompositeDatasetRef`
(tested, harmless) but were not the live bug. A live render of the cryo pre-run panel
is the outstanding confirmation (folded into Phase-0 QA).
