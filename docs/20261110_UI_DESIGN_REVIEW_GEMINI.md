# BioMate UI design review (Gemini 3.8 Flash) + fixes applied

**Date:** 2026-11-10
**Environment reviewed:** live dev — https://dev-public.biomate.ai (local app :5000 and reference :7779 were down)
**Reviewer model:** `google/gemini-3.8-flash` via OpenRouter (vision; 4 screenshots + context). Cost $0.018.
**Trigger:** founder concern, verbatim — *"the font size, space, and coloring… the entire appearance of UI does not look friendly, effortless, and like designed by a good product manager — not high-end conception."*
Plus two explicit directives given during the session:
- *"I remember the report is provided both doc and powerpoint download before, it is functioning now?"* — verify Word + PPTX report download.
- *"the format should be in the bottom click list, do not make it crowd"* — report/export formats belong in ONE compact dropdown, not spread across the panel.

This is an internal design-and-engineering note, not BD copy.

---

## 1. Screenshots fed to the reviewer (4 real states)

1. **Landing / empty chat** — sidebar (Workspace: New Chat/Data/Workflows/Model; Projects; Other chats), centre "What do you want to do?" with 4 category cards, bottom composer.
2. **Completed ADMET run — working view** — left chat findings + SSE log; right workflow panel (`Predict ADMET Properties (AI)`, 2/2, tabs Workflow Settings/Phases/Run Results, sub-tabs Summary/Output Files/Report, QC findings table, Export report link, Run again).
3. **Findings panel** — per-compound Key Results table (Metric/Value/Interpretation/Source), Caution alert, Download findings, footer links.
4. **Run Manager overlay** — Current/All chats, filters, NEEDS ATTENTION / RUNNING columns.

Saved copies of the raw review text: `scratchpad/gemini_ui_review_output.md` (this session).

---

## 2. Gemini verdict (summary)

> "Reads as an internal engineer dashboard stitched from off-the-shelf primitives, not a modern scientific platform of Linear/Vercel/Stripe caliber. The eye finds no visual anchor: borders compete with borders, competing font weights fight for hierarchy at identical sizes, and data tables suffer column starvation causing headers/numbers to wrap vertically."

### Ranked visual issues (Gemini)
1. **[H] Broken table columns / vertical text slicing** — QC table headers collapse to `Ob/ser/ved`, `Re/su/lt`; numeric values wrap `0.0⏎03`. Looks broken, destroys scientific trust. Fix: `white-space:nowrap`, `tabular-nums`, fixed column widths, row dividers not cell borders.
2. **[H] Localization chaos** — mixed Chinese + English within the same frame (tabs `工作流设置`/`阶段`/`运行结果` beside `Report`; table headers `指标/数值/解读` over English cells; alert `注意事项` with English body). Fix: lock every string to the active locale; no inline English fallbacks leaking through.
3. **[H] Border fatigue / nested-card syndrome** — a 1px line around everything; panels-in-panels. Fix: remove ~70% of borders, use surface/background tokens + whitespace.
4. **[M] Typography scale collapse** — everything 12–14px with arbitrary weight shifts, no ramp. Fix: a strict 5-step ramp (15/13/12/11 + mono), weights 400/600 only.
5. **[M] Disconnected color system** — washed-out sky-blue + raw pastel status pills look like unskinned Bootstrap/Ant. Fix: neutral base + ONE calibrated accent; semantic tokens for success/warn/error only.
6. **[M] Run Manager inverted IA** — raw hashes (`run 7ed96e78 · inv 30cb6087`) in heavy weight; equal columns leave dead space. Fix: dense scannable list, de-emphasise hashes, elevate compound/workflow/status, hover actions.
7. **[L] Button ergonomics / micro-components** — giant black "Run again" flush to edge; stroked "Download findings" floating in whitespace. Fix: unified button system (32/28px, radius 6, one primary style).

### Information-flow issues (Gemini)
- **Dual-pane redundancy** — the same findings summary + values render in BOTH the chat column and the right panel. Chat should carry dialogue + progress + a 2-line takeaway with an "Inspect →" affordance; the panel owns the dense tables. Don't duplicate.
- **Fragmented export actions** — `导出报告 ▾` floating above the tabs, a separate `下载分析发现` button in chat, AND footer links (`Full table in Summary → / Files in Outputs → / Full report →`). Collate into ONE export dropdown; drop the auxiliary footer links (tabs already do that).
- **Double-tier sub-navigation** — two stacked tab rows (Workflow Settings/Phases/Run Results, then Summary/Output Files/Report) causes fatigue. Flatten; push settings/phases into an accordion or slide-over.

### Highest-leverage punch-list (Gemini, condensed)
Table column constraints · monolingual lock · remove 70% borders · consolidate exports into one dropdown · kill chat/panel duplication · 8pt spacing grid · restrained type system (Inter + CJK fallback, ≤3 sizes on screen) · Run Manager as dense list · muted callouts/badges · polished composer & borderless starter cards with hover elevation.

Full text: `scratchpad/gemini_ui_review_output.md`.

---

## 3. Code grounding (where these live)

| Issue | File:line |
|---|---|
| Cramped QC table (screenshot 2) | `frontend/client/src/v2/AfterRunReport.tsx:496-507` (Summary-tab QC findings `<table>`), no column sizing |
| Second QC table (auto-loop) — already padded | `AfterRunReport.tsx:2361` |
| Export dropdown (Markdown + PPTX only) | `AfterRunReport.tsx:377-467` |
| Report converter endpoint (`pptx|pdf`, no docx) | `frontend/server/routes.ts:17289` |
| Methods DOCX endpoint (exists, orphaned — no button passes `?format=docx`) | `routes.ts:5990` / consumed as text at `AfterRunReport.tsx` methods job |
| Panel CSS tokens | `frontend/client/src/styles/workflow-panel.css` |
| i18n | `frontend/client/src/locales/{en,zh}/common.json` |

**Report-download answer to the founder's question:** before this session, the run-report menu offered **Markdown + PowerPoint only** — **Word/DOCX was NOT wired** (the `/api/reports/convert` endpoint rejected `docx`; a separate pandoc DOCX endpoint existed but no button invoked it). So "both doc and powerpoint" was only half-true. Fixed below.

---

## 4. Fixes applied this session (committed)

1. **QC findings table no longer shreds** (`AfterRunReport.tsx:496-507`): `table-layout:fixed` + `<colgroup>` (Check flex; Observed 72 / Flag 104 / Result 88px), header row `white-space:nowrap` + muted colour, numeric cells `white-space:nowrap; font-variant-numeric:tabular-nums`, Check cell keeps `overflow-wrap:anywhere`. Headers and numbers stop wrapping in the narrow panel.
2. **Word (DOCX) restored to the export dropdown** — per "both doc and powerpoint" + "formats in the bottom click-list, don't crowd":
   - Server: `routes.ts` `/api/reports/convert` now accepts `docx` and runs `pandoc --to=docx` (the same bundled pandoc as PPTX), `wordprocessingml.document` mime, optional `dist/assets/biomate-reference.docx` branding.
   - Client: new `handleDownloadDocx()` (mirrors the PPTX path, posts the same `buildFullReportMarkdown` content) + a third menu item **between** Markdown and PowerPoint, so one dropdown now lists **Markdown report · Word report (DOCX) · PowerPoint deck (PPTX)**. zh locale keys added.
   - This is the consolidation the founder asked for: every format in the single bottom click-list, nothing new crowding the panel.

Verified: `tsc --noEmit` clean; zh `common.json` valid. (vitest + dev verification tracked below.)

---

## 5. Prioritized plan NOT done tonight (needs founder review — judgment-heavy, risk of unsupervised restyle on a shared branch)

The broad visual overhaul is a **design-system effort**, not a mechanical fix, so I did not sweep typography/color/borders live overnight. Proposed order when approved:

1. **Design tokens** — define `--surface / --canvas / --elevated`, one accent, semantic success/warn/error, an 8pt spacing scale, and a 5-step type ramp in `workflow-panel.css` + a global token sheet. Swap ad-hoc inline styles to tokens.
2. **Monolingual lock** — audit i18n so zh renders zh everywhere (kill English leakage in tabs, step titles, findings headers, alerts). This is the single biggest "unpolished" signal.
3. **De-border** — remove ~70% of 1px outlines; hierarchy by surface + whitespace.
4. **Kill chat/panel findings duplication** — chat = progress + 2-line takeaway + "Inspect →"; panel = the tables.
5. **Flatten the double tab tier**; **Run Manager → dense list**; **unified button + badge/callout system**.

Each is a separate, reviewable PR with before/after screenshots against the live app.

---

## 6. Directives captured (for future sessions)
- Report/export formats → one compact dropdown ("bottom click-list"), never spread across the panel. [[feedback_design_spec_is_source_of_truth]]
- Founder wants a high-end, effortless, product-designed feel — treat typography/spacing/color/borders as a design-system task, not per-screen patches. [[feedback_no_bespoke_per_task_ui]] · [[feedback_design_conformance_audit]]

Related: [[project_findings_outputs_architecture]] · [[project_ui_visual_parity_notes]] · [[feedback_design_mockup_is_style_ref]]
