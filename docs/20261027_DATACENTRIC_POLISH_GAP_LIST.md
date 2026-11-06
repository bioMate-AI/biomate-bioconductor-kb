# Data-centric UI polish — gap list & plan (vs `claude_code_core` reference)

Date: 2026-10-27. Reference package: `~/Downloads/claude_code_core` (prototype + specs:
`HANDOFF_OVERVIEW`, `AFTER_RUN_AND_CHAT_SPEC`, `INSTRUMENT_DATA_PANEL_SPEC`, `d2 design screens feedback`).
Current production mapped in `frontend/client/src/`. **Local-only; no dev sync until signed off.**

Principle of the reference: **one run object renders every screen** (chat, settings, after-run) through
shared code — chat/Summary/Report/Record all read the same computed result so they cannot disagree.

## P0 — VISUAL FIDELITY (follow the design's APPEARANCE exactly, not just function)
The user's directive: *"not just the function, the appearance of the design should be followed exactly.
The current platform is too ugly."* So this is a **design reproduction**, look + behavior, not a
behavioral patch over the existing (ugly) styling.

Target design system (port into production as the foundation, then every area inherits it):
- **Tokens** — `claude_code_core/src/tokens.css`: cool-neutral **oklch** palette (`--bg 0.99`, surfaces,
  `--border`, `--text 0.22`, muted `0.48`), a **single cool accent** (`oklch(0.55 0.14 245)`), status
  colors (ok/warn/err/run + soft variants), radii `4/6/8/12/16`, three subtle shadows, **Inter** +
  **JetBrains Mono**, 14px base, `letter-spacing:-0.005em`, custom thin scrollbar, sidebar 220 / panel 500.
- **Atoms** — `.chip` (pill, soft status variants + dot), `.btn` (32px, `.primary`=ink, `.accent`,
  `.ghost`, `.sm`), `.linkish` (dotted-underline). These exact styles must be reproduced.
- **Screen styles** — `tutorials_v2/_ui/bm-ui.css` (364 lines, everything under `.bmx`): the look of
  chat column, settings (input cards + step params), summary findings table, outputs file list, record
  accordion, report document. **This is the pixel target** for the four areas below.
- **Pixel reference**: before implementing each area, capture the prototype screen
  (`BioMate Data-Centric Prototype.html` → cold start → worked example) as a screenshot and match it.

Approach: (1) introduce the token set + atom styles into the production theme (map onto the existing
CSS-var/Tailwind theme, or add a scoped `.bmx`-equivalent layer), (2) rebuild each of the four areas'
markup to the reference component structure, (3) screenshot-diff against the prototype until it matches.
This replaces the current styling in these areas, which the user considers too ugly.

## USER OVERRIDES of the reference (take precedence over the spec)
- **Chat answer must NOT cap at ≤3 rows.** The spec's "up to three headline rows" loses information.
  Show the **full result in chat with a scrollbar** (capped height, `overflow:auto`). Applies to the
  chat answer block and anywhere the spec truncates rows.
- **Appearance is binding, exactly** (P0 above) — match the prototype's look, don't approximate.
- **Keep Settings and Phases as TWO tabs** (the reference §1.1 merges them into one Settings screen — do
  NOT merge). Workflow-panel top tabs stay **Settings · Phases · After-run**; inside After-run the tabs are
  **Summary · Outputs · Report** (§2). Params-under-steps content can still live in the Phases tab.
- **Phase panel: color updates + transitions must be implemented AND tested** (§8) — live status coloring
  and smooth transitions as cards go pending → running → completed / failed, SSE-driven, Playwright-tested.

---

## 1. Chat view / information flow
Files: `chat-message.tsx` (ChatMessage :237), `chat-with-artifacts.tsx`, `chat-progress-fold.tsx`
(ProgressStreamBox :156), `findings-card.tsx` (FindingsCard :96 — panel-only today).

Has today: user bubble + file chips; **plan** header; **progress lines** (SSE, speaker pills); **wf-chip
status row** (name + Completed/Running/Failed chip + generic "Open" button, only after panel opened).

Gaps:
- **G1.1 No structured verdict/answer block in chat.** The verdict + key-results table live only in
  `FindingsCard`, rendered inside the panel — chat shows findings as plain `find`-speaker text lines.
  → Render an answer block in the completed chat turn: **bold verdict sentence** (named entities +
  numbers) + the **full key-results table, scrollable** (per USER OVERRIDE — not ≤3 rows).
- **G1.2 No per-tab deep links from chat.** Only a generic panel "Open". → Add "Open in Summary /
  Outputs / Report" links that open the panel to that specific tab (needs a tab-target param on
  `onOpenInPanel` / `setPanelWorkflow`).
- **G1.3 Status row only appears after the panel was opened** (`everInPanel`). → Show it on completion
  regardless.

## 2. After-run panel
Files: `v2/AfterRunReport.tsx` (2 tabs today: **Results** = Summary+Outputs merged :318; **Record** :385),
embedded by `nextflow-workflow-viewer.tsx` :2834. Report = download menu only (Markdown/PPTX), no tab.

**DECIDED (user): after-run = three tabs — Summary · Outputs · Report.** No separate Record tab; its
content distributes: **Methods · Software · Citations · Quality-checks → Report** sections; **resolved
Parameters → Report** (Method/Data) + the Settings/Steps view; the downloadable **reproducibility-record
JSON → Report footer link** (`run original <id> · N outputs · Reproducibility record ↗`); **Trajectory →
the per-step detail panel** (G2.4), not a tab.

- **G2.1 Collapse to 3 tabs.** Split the merged "Results" into **Summary** (the answer/findings) and
  **Outputs** (files), and **remove the Record tab** — fold its sections into Report + the step detail.
- **G2.2 In-panel Report tab.** Editable report doc, **8 fixed sections in order** (Question · Answer ·
  Data · Method · Results · Quality checks · Caveats · Citations), **scrolls**, Edit / Ask-BioMate /
  Download, footer with the reproducibility-record link. Content largely exists (`buildFullReportMarkdown`
  :2320); render it in-panel instead of download-only. Software/Methods/Citations/QC that lived in the old
  Record tab now live here.
- **G2.4 Per-step detail panel (step deep-view) — implement as previously designed** (prototype
  `dataui/StepDeep.jsx`). Clicking any step (or a provenance claim in Summary) opens one object:
  header (step N of M · phase · name · status chip) → **inputs** (data chips / upstream output) →
  **output artifacts rendered from their own bytes** (output tabs: sortable/filterable table · figure /
  volcano · "raw first bytes") → **the per-step log / trajectory tail** ("follows the tail while the step
  runs") → **resolved parameters this step ran with** (editable in place, defaults grey, project/user
  edits marked with their reason) → **Re-run from this step** with the **was→now diff** up front and the
  cache note ("upstream reused · only this + downstream re-run"). Prev/next-step nav. **Trajectory lives
  here, per step** — this is the user's explicit requirement.
- **G2.5 (polish)** collapsed sections show a one-line preview; never render a SHA-256 column of dashes
  (say "not yet computed · N outputs · Compute" once).

## 3. Files / outputs preview
Files: `OutputsTab` in `AfterRunReport.tsx` :1026; `step-output-preview.tsx` (resolveViewer :99 — rich
typed previews: table/image/pdf/html/structure/vcf/sequence/density/r-object/singlecell).

Has: per-file **size** ✓, **type chip** ✓, **real typed previews** ✓ (strong), per-card step tag.

Gap:
- **G3.1 Flat list, not grouped by producing step.** Spec wants files under **per-step section headers**.
  → Group `OutputsTab` cards by `f.step` into collapsible sections; keep the rich previews. Contained.
- **G3.2 (polish)** preview header should read `name · type · size · from <step> · version <n>`; show
  version as "not recorded" until persisted (data gap). Typed JSON previews already exist.

## 4. Instructions / project setup page
Files: `pages/project-detail.tsx` (instructions tab :939), `components/project-guidance-cards.tsx`.
Data: `GET/PATCH /api/projects/:id/instruction-settings` `{skillPackIds, outputRequirements}`;
`project.instructions` (free text).

Has: **Standing instructions** (free text ≈ Rules), **Output requirements** (free text ≈ Formats),
**Skills & experts** (toggle list ✓), **Notes** (human-only, agent never reads).

Gaps vs spec (Rules · Output formats · Skills & experts · Memory):
- **G4.1 Rules is free text, not structured.** Spec: numbered list, inline edit, Remove, add-at-bottom,
  header chip `N rules · M formats on`. → Restructure to an editable list (needs `rules[{id,text}]`).
- **G4.2 Output formats is free text, not per-format rows.** Spec: one row per format with on/off +
  Preview + Add a format (`formats[{kind,name,detail,on,version}]`). → Structured, needs schema.
- **G4.3 Skills & experts** ✓ (closest match; keep).
- **G4.4 No agent Memory.** Only human-only Notes. Spec's **Memory** = agent-proposed facts, reviewable,
  **Forget** / **Make a rule** (promotes to Rules), master "remember from chats" switch. **Biggest lift:
  needs a backend memory data model** (`memory:{enabled, items:[{id,text,source:{chatId,msgId}}]}`),
  write path (agent proposes on correction/preference), and session-context injection (rules + memory →
  composer chip). Rules pre-set params with origin "from project instructions"; memory never silently
  sets params.

---

## Recommended order (visual foundation first, then area-by-area to pixel-match)
0. **Design-system port (P0 foundation)** — bring `tokens.css` + the `.chip`/`.btn`/`.linkish` atoms +
   the `.bmx` screen styles into production; capture prototype screenshots as the pixel reference. Every
   area below then inherits the look. Do this first — it's what makes the result not-ugly. (~1–2 days)
1. **G5.1 Multi-value param editor** (user-reported, urgent) — named-entity list editor, full-width, add/
   remove; + **G7 phase-panel status colors & transitions implemented + Playwright-tested**. These are the
   two concrete bugs the user flagged; small blast radius. (~1–1.5 days)
2. **G3.1 Outputs grouped by step** — rebuilt to the reference file-list look. Contained. (~0.5–1 day)
3. **G1.1 + G1.2 chat answer block** (verdict + **scrollable full table**, per override) + tab deep-links,
   styled to the reference chat column. (~1–1.5 days)
4. **After-run = Summary·Outputs·Report** (G2.1 split + G2.2 Report tab) + **G2.4 per-step detail panel
   with trajectory inside** (step deep-view, as designed). Keep Settings · Phases as two tabs. (~2–3 days)
5. **G4.1–G4.2 Instructions structure** (Rules list + Formats rows) in the reference look. (~1–1.5 days)
6. **G4.4 Memory** — biggest; backend data model + write path + context injection. (multi-day, phase it)

## 5. Settings / parameter editor (pre-run)
Files: `nextflow-workflow-viewer.tsx` param rows `:709-773`; params built `:294-320`
(`required_params`/`optional_params` → `{type (inferred), value, options, …}`). Reference: §1.1
(one Settings screen, params under the step), d2 feedback ("inputs as named entities").

- **G5.1 Multi-value-same-type inputs are broken (user-reported).** A list param (e.g. a multi-compound
  `smiles_list`) hits the `isLong` branch (`:740`) and renders as **one raw-JSON `<textarea>`, 220px wide,
  squeezed into the right `auto` column** of a `1fr auto` grid (`:710`). Two defects:
  - **Placement**: a multi-line field crammed into a fixed 220px right column — not full-width, cramped.
  - **Function**: you hand-edit JSON (`["CC(=O)...","OC(..."]`) — brackets/quotes/commas — instead of
    per-item entities. The reference: *"a raw JSON array in a text field is not acceptable."*
  → **Fix**: detect a list/multi-value param (value is an array, or `type==='list'`, or name `*_list`) and
    render a **named-entity list editor**: one **item per row** (value in mono, individually editable),
    **Add / Remove** controls, and a **full-width layout** (label on its own line, editor spans the row —
    not the `1fr auto` squeeze). For compounds: optional name + SMILES-in-mono per the d2 note. Serialize
    back to the array on change (keep the wire format a real array, not a hand-typed string).
- **G5.2 Inputs vs params.** Reference splits Settings into **Inputs** (named-entity cards: name, mono
  value/SMILES, origin chip, real preview, input checks) then **Steps** with params under each step.
  Today params + inputs are one flat list. (Part of the Settings rebuild; G5.1 is the urgent slice.)
- **G5.3 Long single-value fields** (one long SMILES, a path) should also drop to a **full-width row**, not
  a 220px right box — same placement fix, simpler (no add/remove).

---

## 6. Chat output + after-run content ACROSS task/workflow patterns
The reference defaults to one shape — a **findings** block (entity × metric table + verdict). That fits
qPCR / ADMET / QSAR, but BioMate runs ~10 distinct result *patterns*; a single findings table
under-serves most of them and loses info. The fix is **not bespoke per-task UI** (ruled out — the harness
routes each task to an existing category) but a **block catalog the chat answer and each after-run tab
compose from, chosen by the run's pattern.** The reference already has primitives (`B`: findings, table,
figure, figs, kv, tiles, callout, prose; `FIG`: scatter/hist/bars — curves/volcano are *placeholders*).
Below: the patterns, the chat-answer + after-run adjustment each needs, and the primitives to add.

| # | Pattern | Example workflows | Chat answer block | After-run emphasis | Key interactions |
|---|---|---|---|---|---|
| A | **Per-entity comparison** (findings) | qpcr, d2 ADMET, d1 QSAR, s4 survival, flow | Verdict + entity×metric table — **full & scrollable** (override), sortable, cell→source | Summary = full table; no constant columns | sort, click-cell→Outputs file |
| B | **Scalar / gate decision** | pq protocol QC, qc sample QC | Verdict (Pass/Flagged) + **gate list** (criterion·value·outcome); no big table | Summary = gate table; halt vs advisory color | edit threshold → recompute |
| C | **Ranked selection** | d3 generative, d6 novelty, tid target-id, d5 poses | Verdict (N selected) + **ranked list** (scrollable, top highlighted, rejected shown w/ reason) | Summary = full ranked table; Outputs = candidate file | sort, show-rejected toggle, filter |
| D | **Curve / kinetics / dose-response** | s1 NCA PK, s2 PBPK, plate 4PL, d7 stability, d4 FEP | **Figure is primary** — curve inline + key scalars (Cmax·AUC·t½ / IC50 / shelf-life / ΔΔG±SE) | Summary = figure + params; Report = figure block | hover readout, zoom, param overlay |
| E | **Large table + volcano** | t3/m2 DE, somatic/nanopore variants, lcms/advprot | **Summary stats** (N up/down @FDR; N variants by type) + volcano thumbnail + "full table in Summary". **Never inline 20k rows** | Summary = **virtualized** sortable/filterable table + volcano; Outputs = big CSV/VCF typed preview | filter FDR/effect, search gene, volcano→row |
| F | **Image / structure / density** | cryoem (3D map), micro (segmentation), structure pred | **Thumbnail + key metrics** (resolution Å / cell count / pLDDT) | Outputs = 3D/structure/image viewer (exists in step-output-preview); Summary = metrics + thumb | open viewer, rotate/zoom |
| G | **Plan / routing / decision** | pf param prefill, m3 accession→workflow, rbrt routing | The **decision** block — routed workflow(s) + resolved params with origin + rationale; not a findings table | Summary/Record = resolved plan + param table | edit resolved params, confirm→run chain |
| H | **Pipeline / multi-stage** | drugdev (design→ADMET→rank→exposure) | Stage progress + **consolidated verdict** across stages + small per-stage key result | Summary = per-stage sections | jump to a stage's outputs |
| I | **Loop / campaign** | loops-sm, loops-pep, auto-loop QC remediation | Round-by-round progress + remediation **diff** (was→now params) + per-round gate table | After-run = round history | expand round, accept/reject remediation |
| J | **Agentic text / code** | run_code, research_query | Answer text / code result inline (**scrollable**); files → Outputs | Outputs = produced files | copy, re-run |

### Primitives to add / finish (so the catalog covers every pattern)
- **ranked-list** (with rejected + reason) — pattern C. **gate-list** (criterion·value·outcome, halt/advisory) — B.
- **Real curve + dose-response + volcano figures** — D/E (reference marks these *placeholder*; must be real).
- **diff** (was→now) for remediation — I. **plan/decision** block (routed workflows + resolved params) — G.
- **Reuse the structure/image/density viewers** (already in `step-output-preview.tsx`) inside Summary & as chat thumbnails — F.
- **Size-aware table mode** on every table/findings block: small N → full inline (scrollable, per override);
  large N → counts summary + top slice + link to the virtualized Summary table. This is the single most
  important adjustment — it makes "show the full result" safe for a 20,000-row DE run.

## 7. Phase panel — status colors & transitions (implement AND test)
Files: `nextflow-workflow-viewer.tsx` step rows `:778-816` (`stepStatus` pending/running/completed/failed,
`data-status` `:792`, status chips `:813-815`), phase/overall badges, footer button. SSE drives status.

- **G7.1 Live status coloring & transitions.** Every phase card, step row, the overall badge and the footer
  must reflect live state with the design tokens — **pending** (neutral/grey) → **running** (`--run`/
  `--run-soft` + spinner) → **completed** (`--ok`/`--ok-soft`) / **failed** (`--err`/`--err-soft`) — and
  **animate the change** (color/background transition, the CLAUDE.md "Real-time status tracking" contract):
  pre-run `data-status="idle"` + cards `pending`; on run → footer "Running…" + overall `running`; each
  phase start → card `pending→running`; each step done → row `completed`; all done → overall `completed` +
  footer "Run again"; any failure → `failed` + footer "Restart". Match the prototype's PhaseCard look
  (status chip vocabulary + soft-background transitions).
- **G7.2 Test it.** Playwright E2E that observes at least one **idle→running→terminal** transition live
  (not mocked) via `waitForFunction` on `data-status`, per the CLAUDE.md UX-E2E standard (live dev stack,
  real SSE, fixture `lifeifei163361@163.com`). Assert colors/classes at each state.

### Cross-cutting interaction standard (apply to all patterns)
Click any value → its **source file** in Outputs (provenance); sort/filter/search on tables; expand/collapse
and **scroll, never clip**; figure zoom + structure/image viewers; edit params / skip step / accept-reject
remediation / re-run; **chat→panel deep-links** (Summary/Outputs/Report); download (file · report · record
JSON · bundle). The run object carries a `pattern` (or it's inferred from the result shape) that selects the
block set — one renderer, many compositions, no per-task component.

## Parallel work split (disjoint file ownership — streams never touch the same file)
Local-only (no dev sync). Each stream: use the design tokens, match the prototype render
(`tutorials_v2/_ui/bm-ui.js` + `bm-ui.css` are the exact target markup/look), `tsc --noEmit` its files,
no spawning, STOP if it would edit a file outside its set.

- **Stream 0 — Design system (ME).** New global token/atom CSS layer from `src/tokens.css` (oklch palette,
  radii, shadows, Inter/mono, `.chip`/`.btn`/`.linkish`), wired app-wide; capture reference; own the
  cross-stream contracts (C1/C2 below). Files: a new `bmx-tokens.css` + the global import site only.
- **Stream 1 — Workflow panel.** Files: `components/nextflow-workflow-viewer.tsx` (+ `wfpanel.css`-equiv,
  new E2E test). Work: §5.1 multi-value param editor (named-entity list, full-width), §5.3 long-field
  placement, §7 phase status colors + transitions **+ Playwright test**, and add **C1** plumbing
  `onOpenInPanel(opts?:{tab})` + pass `targetTab` down to AfterRunReport. Keep Settings · Phases two tabs.
- **Stream 2 — After-run.** Files: `v2/AfterRunReport.tsx`, `components/step-output-preview.tsx`, new
  `v2/StepDeep.tsx`. Work: §2.1 split to **Summary · Outputs · Report**, §2.2 Report tab (8 sections,
  scroll; reuse `buildFullReportMarkdown`), §3.1 Outputs grouped-by-step, §2.4 per-step detail/step-deep
  with **trajectory inside**; accept **C2** `targetTab` prop. (Record tab removed; folds into Report.)
- **Stream 3 — Chat info flow.** Files: `components/chat-message.tsx`, `components/chat-with-artifacts.tsx`
  (+ reuse `findings-card.tsx`). Work: §1.1 chat answer block = verdict + **full scrollable result** (no
  ≤3 cap), §1.2 tab deep-links calling **C1** `onOpenInPanel({tab})`, §1.3 status row on completion.
- **Stream 4 — Instructions.** Files: `pages/project-detail.tsx`, `components/project-guidance-cards.tsx`,
  a server route. Work: §4 rebuild to Rules (numbered list, add/edit/remove, count chip) · Output formats
  (type-chip rows, on/off, Preview, Add) · Skills (keep) · **Memory** (agent-proposed, Forget / Make-a-
  rule, master switch) — UI against a memory stub; pixel-match `01_instructions.png`.

Cross-stream contracts (frozen): **C1** panel `onOpenInPanel(opts?:{tab:'summary'|'outputs'|'report'})`
(Stream 1 adds, Stream 3 calls). **C2** `AfterRunReport` accepts `targetTab?:'summary'|'outputs'|'report'`
(Stream 2 adds, Stream 1 passes). Design-token names from `src/tokens.css` (`--bg/--surface/--border/
--text/--text-muted/--accent/--ok/--warn/--err/--run` + soft variants, radii `--r-*`, Inter/JetBrains Mono).

## Open decisions for the user
- **D1. DECIDED** — after-run = **Summary · Outputs · Report** (3 tabs); Record folded into Report +
  per-step detail; **trajectory inside the per-step detail panel** (G2.4).
- **D2.** Start order — recommend 1→2→3 (visible UI wins) before the Instructions/Memory backend work.
- **D3.** Memory scope — ship the UI against a stub first, or build the backend data model up front?
- **D4.** Pattern coverage — confirm the §6 pattern set and the "compose from a block catalog by pattern"
  approach (vs the reference's findings-only default). Which patterns to prioritize first for chat +
  after-run (recommend A/C/D/E since they cover the most workflows and the worst current info loss)?
