# After-Run Panel — Design Document

**Status:** v0 shipped behind `?afterrun=v2`; this doc covers the full intended design
**Date:** 2026-06-01
**Owner:** yzhang
**Component:** `frontend/client/src/v2/AfterRunReport.tsx`
**Replaces:** v1 scattered after-run UX (FindingsCard + methods-report download link + QC modal)
**Related docs:**
- `docs/20260528_AFTERRUN_FINDINGS.md` (A3 audit — backend coverage per tab)
- `docs/20260528_WORKFLOW_PANEL_PRIORITY_PLAN.md` (Phase 4 plan)
- `docs/20260527_V2_INCREMENTAL_MERGE_PLAN.md` (parent merge plan)

---

## 1. Problem statement

When a BioMate workflow completes, the user needs a single place to:
1. Understand **what happened** (was it good? what does the data mean?)
2. Get **the outputs** (preview the interesting ones, download all the rest)
3. See **how it was run** (parameters submitted, software versions, methods)
4. Verify **QC passed** (which gates fired, when, with what values)
5. **Cite it** in a paper or compliance document

Today (v1) those five needs are spread across:
- A `FindingsCard` injected below the chat message after run completion
- A separate "Methods Report" download link on the workflow panel
- A "QC settings" modal (read-only after run; designed for pre-run config)
- Per-step file preview inside the live `NextflowWorkflowViewer`
- No single "this run produced these N files" surface; no bulk download from the after-run flow
- No software-versions surface; no citations surface

Result: users say "I clicked Run, it finished, I don't know what to look at next." The Methods Report download is the most-used affordance because it's the only thing labelled "report" — but it's only the methods narrative, not the findings or outputs.

## 2. Goals

**G1.** Single tabbed surface that surfaces every post-run artifact in the same place.
**G2.** Zero loss of v1 functionality — every download / preview that worked before still works.
**G3.** Graceful empty states. No "Coming soon" placeholders; if a workflow doesn't have data for a tab, the tab is hidden.
**G4.** Works for both Galaxy invocations (have `outputDatasets`) and Nextflow-native runs (have `s3_output_files`).
**G5.** Comprehensive offline-readable export. User can email/archive the report as a single `.md` file.
**G6.** Behind a feature flag (`?afterrun=v2`) until validated against the 6 CLAUDE.md scenarios; v1 stays default.

## 3. Non-goals

- **No new chat surface, sidebar, or pre-run UX changes.** This document is scoped to the *after-run* panel only.
- **No DOCX/PDF export in v0.** Markdown download is sufficient; user can pandoc-convert if needed.
- **No backend changes for v0 ship.** Subsequent rollout adds 3 backend routes (Software, Citations, Methods caching/streaming).
- **No replacement of the live execution panel** (`NextflowWorkflowViewer`). The after-run report appears *above* it when the run completes; the viewer stays for live status and per-step inspection.
- **No replacement of FindingsCard for the in-chat usage.** The card stays inline beneath chat messages; the after-run panel embeds it as one tab.

## 4. Target users

| Persona | Concern |
|---|---|
| Wet-lab scientist | "Did my experiment work? Show me the headline number and the plot." |
| Computational biologist | "Show me the parameters, methods, software versions — I need to reproduce this for a paper." |
| QA / compliance reviewer | "Show me the QC audit trail and the citations for the gates." |
| Bioinformatician handing off to another team | "Bundle every output file into one ZIP I can send." |
| Future-me opening a 6-month-old run | "Remind me what this run did and let me re-run with the same params." |

## 5. Information architecture

The panel renders **above** the existing `NextflowWorkflowViewer` in the right-hand workflow panel, when:
- `useAfterRunFlavor() === 'v2'`
- `currentRun.execution.status === 'completed'` or `'ok'`
- `currentRun.id` is defined

Stacking order (top → bottom):
1. Panel chrome (Tutorial + Close buttons) — unchanged from v1
2. **AfterRunReport** (this design)
3. `NextflowWorkflowViewer` (live status, step list, QC gate alerts, run-again controls)

When the run is still in flight, the panel hides; the live viewer occupies the full panel height as today.

### 5.1 Header

```
[After run]                              [↓ Download report]
─────────────────────────────────────────────────────────────
[Findings] [Outputs] [Methods] [Parameters] [QC audit]
```

- `[After run]` is a small uppercase kicker establishing the section
- `[↓ Download report]` triggers a comprehensive client-side markdown export (see §10)
- Tab bar shows only **visible** tabs (hidden tabs are removed entirely; no greyed-out placeholders)

### 5.2 Default tab

Always **Findings** — answers the user's first question ("did it work?"). User's last-selected tab is **not** remembered across sessions (would create whiplash for users who run different workflow types).

## 6. Tabs — detailed spec

Visibility rules summarised:

| Tab | Always shown? | Hidden when |
|---|---|---|
| Findings | Yes | — |
| Outputs | Yes | — (empty state instead) |
| Methods | No | `/methods-report` returns stub (<200 chars or "No QC events recorded") |
| Parameters | Yes | — |
| QC audit | No | `/qc-events` returns 0 events |
| ~~Software~~ | (post-v0) | Backend route `/api/invocations/:id/software` not implemented |
| ~~Citations~~ | (post-v0) | Backend route `/api/workflows/:name/citations` not implemented |

### 6.1 Findings tab

**Purpose:** AI interpretation of the run's outputs in plain language.

**Data source:** `GET /api/workflows/runs/:id/findings` (existing). Backend runs `OutputAnalyzer` + `FindingReporter` (Claude-powered) over the output files and produces:
```json
{
  "status": "ready",
  "summary": "47 BBB-penetrant candidates after all QC gates.",
  "key_results": [
    { "label": "Final candidates", "value": "47" },
    { "label": "Mean logBB", "value": "0.41 ± 0.18" }
  ],
  "citations": [{ "title": "...", "doi": "..." }],
  "caveats": ["..."],
  "next_steps": ["Run MM-GBSA rescoring on top 10 poses"]
}
```

**Component:** reuses the existing `FindingsCard` directly (no fork).

**States:**
- `pending` (analysis async, may take 30-60s): spinner + "Generating findings…"
- `ready`: structured summary + key results table + caveats + next-steps list
- `error` (e.g. files unreadable): caveats explain why; summary degrades to "Outputs not yet readable — open the Outputs tab"

**Interaction:** clickable next-steps that fire a new chat message ("Continue: <step text>"). Already wired in FindingsCard via `onContinueAnalysis` callback.

### 6.2 Outputs tab

**Purpose:** the file list — visualise the interesting ones, bulk-download the rest.

**Data source (dual):**
- **Galaxy mode:** `currentRun.execution.outputDatasets[]` (structured, with `galaxyDatasetId`, `extension`, `size`)
- **Nextflow-native mode:** `currentRun.execution.nextflowStatus.s3_output_files[]` (S3 key list; step name derived from path prefix)

Parent component (`chat-with-artifacts.tsx`) passes both — AfterRunReport prefers `outputDatasets` when populated, falls back to S3 list otherwise.

**Layout:**
```
[↓ Download all (N) as ZIP]  [↓ Reproducibility bundle]

STEP A
  ▸ ligand_prepared.maegz                            maegz
  ▸ ligand_prep.log                                  log

STEP B
  ▸ glide_poses.maegz                                maegz
  ▸ glide_docking_summary.json                       json
  ▸ glide_scores.csv                                 csv
  ▸ rmsd_plot.png                                    png   [preview]
```

**Bulk actions (top):**
- **Download all as ZIP** → `GET /api/invocations/:id/download-all` (existing; uses `archiver` zlib-9). Filename: `{workflowName}_outputs_{invocationId.slice(0,8)}.zip`. Streams server-side so large bundles don't block.
- **Reproducibility bundle** → `GET /api/nextflow/runs/:id/reproducibility` (existing). Returns `nextflow.config`, `.command.sh`, `.command.run`, `.log`, `**/versions.yml`, `pipeline_info/*.html`, `pipeline_info/*.json`. Use case: re-run elsewhere.

**Per-file row (v0):** name is a download link → `GET /api/workflows/runs/:id/step-file?path=…&download=1`. No inline preview yet.

**Per-file row (v1 follow-up):** clicking name opens existing `StepOutputPreview` inline (image, table, 3Dmol structure, density map, etc.). Right-side download icon stays. Cap inline preview at ~5 MB; larger files show "File is too large to preview — Download" instead.

**Empty state:** "No output files registered yet." + bulk-download buttons still visible (a partial bundle may exist on the backend).

**Grouping:** by step. When step name is empty (e.g. Nextflow runs where the path prefix doesn't map to a clean step), files group under a `(unspecified step)` heading.

### 6.3 Methods tab

**Purpose:** publication-quality narrative of the methods used.

**Data source:** `GET /api/invocations/:id/methods-report` (existing). Returns plain text — typically 5-15 KB of structured prose:
```
BioMate AI — Report
Generated: 2026-06-02T00:54:18.702Z
Workflow: v10-p2
Wall Time: 3h 38m 55s

# ABSTRACT
A comprehensive cryo-electron microscopy data processing workflow...

# 1. COMPUTATIONAL ENVIRONMENT
All computational analyses were performed on Amazon Web Services Batch...

# 2. INPUT DATA AND PARAMETERS
...

# 3. METHODS
...
```

**Component:** scrollable `<pre>` block, max height 480 px. Monospaced for code/output preservation; the narrative is plain text so still readable.

**Stub detection:** response is treated as stub when:
- Text length < 200 chars, OR
- Contains the literal string `"No QC events recorded"`

Tab is **hidden** when stub-detected. Per A3 audit, this covers ~44% of workflows (non-QC domains).

**Performance:** endpoint currently takes >20s on first request (synchronous Claude call). Frontend uses `fetch()` with no timeout cap; tab hides if request errors. **Backend caching + streaming** is the v1 follow-up (see §13).

### 6.4 Parameters tab

**Purpose:** show what the user actually submitted.

**Data source:** `extractSubmittedParams(currentRun)` (existing helper in `useRunAgainParamCarryover.ts`). Walks the run's parameter blocks and produces `Record<string, unknown>`.

**Layout:** 2-column table. Key in monospace bold, value in monospace.

```
Parameter            Value
─────────────────    ──────────────────────────────────
ligand               ligand.sdf
receptor             /data/receptors/4EYR.pdb
gaff_version         gaff2
n_steps              5000000
mmgbsa_startframe    500
```

**Empty state:** "No parameter values recorded."

**Future:** "Run again with these params" button → calls existing run-again flow. Currently the v1 viewer has this in the footer; the AfterRunReport defers to it.

### 6.5 QC audit tab

**Purpose:** show the gate evaluation history — time-ordered, with measured / threshold / status / message for each event.

**Data source:** `GET /api/invocations/:id/qc-events` (backend exists at `nextflow_executor.py:4478`; Node proxy added 2026-06-01 in `routes.ts`).

**Shape:**
```json
{
  "events": [
    {
      "ts": "2026-06-01T09:38:02Z",
      "gate": "docking_score",
      "status": "pass",
      "measured": -10.2,
      "threshold": -8.0,
      "message": "Glide score within thresholds"
    }
  ]
}
```

**Layout:** table with columns Time / Gate / Status / Measured / Threshold / Message. Status colour-coded:
- `pass` / `ok` / `advisory` → green
- `halt` / `fail` / `block` → red
- other → default

**Hidden when** 0 events (per A3 audit, ~44% of workflows have no QC gates — these include all bulk-genomics nf-core wrappers).

**Future:** download as JSONL via existing `/api/invocations/:id/qc-audit-download` (already in v1 viewer footer; AfterRunReport will mirror).

### 6.6 ~~Software~~ tab (deferred to v1)

**Purpose:** per-run tool versions for reproducibility.

**Data source (to add):** `GET /api/invocations/:id/software`. Backend walks the run's work directory for `**/versions.yml` files (~98% Nextflow modules emit one) and merges into `{tool_name: version}`. ~30 LOC. Prefer `pipeline_info/software_versions.yml` if present (nf-core convention, one consolidated file).

**Layout when shipped:** 2-column table grouped by category (Alignment / Calling / Annotation / QC).

**v0 behaviour:** tab not rendered at all. Restoration template kept inline as comment in `AfterRunReport.tsx`.

### 6.7 ~~Citations~~ tab (deferred to v1)

**Purpose:** DOIs for methods / gates / tools used in this workflow.

**Data source (to add):** `GET /api/workflows/:name/citations`. Three tiers:
- **Cryo-EM (5 workflows):** query existing `cryo_em_knowledge` RAG index — 11 publication-grounded topics
- **21 domains in `qc_evidence.yaml`:** return `paper_doi` field from each gate (pbpk, admet, cyp_ddi, nca_pk, docking, etc.)
- **17 nf-core pipelines (v1 stretch):** read each module's `meta.yml` for `tools.<name>.doi`

**Layout when shipped:** linked title + DOI per row. Click to open in new tab.

**v0 behaviour:** tab not rendered at all.

## 7. Download report (header action)

**Trigger:** `[↓ Download report]` button in the panel header.

**Output:** single `.md` file, filename `biomate-run-{runId}.md`. Generated client-side from already-fetched tab data — **no backend route needed**.

**Structure:**
```markdown
# BioMate Run Report

- Run ID: `b5007ef4-…`
- Workflow: schrodinger_glide_docking
- Generated: 2026-06-01T09:42:13Z

## Findings
[currently a pointer to /api/workflows/runs/:id/findings — see §13.1 v1 fix]

## Outputs
### LIGAND_PREP
| File | Type |
|------|------|
| ligand_prepared.maegz | maegz |
...

## Methods
```
[methods-report text dumped in a fenced code block]
```

## Parameters
| Parameter | Value |
|-----------|-------|
| ligand | ligand.sdf |
...

## QC Audit
| Time | Gate | Status | Measured | Threshold | Message |
|------|------|--------|----------|-----------|---------|
...
```

**Why client-side first:**
- Zero backend dependency
- Works offline once tabs are loaded
- Same data the user sees in the UI → no surprise content
- Server-side DOCX/PDF can swap the `onClick` later without changing the UX

**Why markdown (not DOCX/PDF):**
- Renders fine in GitHub, GitLab, Notion, Obsidian, Slack
- `pandoc -s biomate-run-X.md -o report.docx` converts in 1s for users who need DOCX
- DOCX generation server-side would block on layout decisions (logos, headers, page breaks) we don't want to make in v0

## 8. Edge cases

| Case | Behaviour |
|---|---|
| Run still in flight | Panel hidden; live viewer shows full height |
| Run failed | Panel still shown; Findings tab gives "Run failed — see error in viewer below"; Outputs tab shows partial files; Methods/QC tabs may be empty (hidden) |
| Findings API returns 404 | Tab hidden (rare — auth issue) |
| Findings stays `pending` >2 min | Spinner stays; FindingsCard polls every 5s indefinitely. (Should add a 5-min "give up" with retry button — v1 polish) |
| outputDatasets empty AND s3_output_files empty | Outputs tab shows "No output files registered yet" but bulk-download buttons remain (in case backend has a partial bundle) |
| One file is >1 GB | Per-file row stays a download link (no preview attempt). Download all ZIP still works — `archiver` streams |
| methods-report endpoint times out | Tab hides silently. User sees fewer tabs than expected. (v1: add a retry button when fetch rejects) |
| qc-events 404 (e.g. workflow has no qc_evidence.yaml entry) | Tab hides silently (correct — not all workflows have QC gates) |
| User closes panel mid-fetch | All `useEffect` cleanups set `cancelled = true`; no setState-on-unmounted warnings |
| Many tabs visible at <500 px panel width | Tab bar wraps to 2 rows; horizontal scroll as fallback |

## 9. States

Per-tab loading states:

| Tab | Loading indicator |
|---|---|
| Findings | Existing FindingsCard skeleton (already implemented) |
| Outputs | No spinner — `outputs` prop is sync from parent; if parent has stale data, list updates on re-render |
| Methods | None (silent); tab hides if fetch fails. **v1:** add `<Loader2>` spinner + retry button |
| Parameters | Sync prop, no async state |
| QC audit | None (silent); tab hides on 404 |

## 10. Visual design

**Typography:**
- Kicker `After run`: 10.5 px uppercase 600-weight, muted colour
- Tab labels: 12.5 px regular; active tab uppercase 500-weight + 2 px underline in accent colour
- Tab body: 12.5 px primary text colour; tables 11.5 px monospace for values
- Methods body: 11.5 px monospace, max-height 480 px, scrollable

**Spacing:**
- 12 px padding around the panel
- 8 px gap between header / tab bar / body
- 4 px row padding in tables

**Colours:** scoped to `[data-v2-ui]` to avoid clobbering v1 tokens. Inline styles in v0 (no token dependency) so the component can mount inside the v1 chrome without CSS isolation issues. Will migrate to v2 tokens when the whole panel ships under `?ui=v2`.

**Accessibility:**
- Tab bar uses `role="tablist"` + `role="tab"` + `aria-selected`
- Tables have proper `<thead><th>` headers
- Download buttons are `<a download>` so screen readers announce "link, download"
- Colour-coded QC status also has text ("pass" / "halt") so colour is not the only signal

## 11. Telemetry

New `UxEventName` entries to add (none yet — current v0 has no telemetry):
- `afterrun.panel_shown` — fires when AfterRunReport mounts (so we can A/B against v1 viewer-only)
- `afterrun.tab_clicked` — payload: `tab` (one of `findings/outputs/methods/params/qc`)
- `afterrun.download_report_clicked` — comprehensive .md export
- `afterrun.download_all_clicked` — ZIP bulk download
- `afterrun.reproducibility_bundle_clicked` — provenance bundle
- `afterrun.file_downloaded` — payload: `ext`, `step`, `size_bytes`

Use this to measure:
- Does the new panel reduce "where do I find my outputs" support tickets?
- Which tab is most clicked? (Hypothesis: Outputs and Findings dominate)
- What fraction of users use bulk download vs per-file?
- What fraction download the comprehensive report?

## 12. Rollout plan

**v0 — opt-in preview (current, 2026-06-01):**
- Live behind `?afterrun=v2` URL param (+ `localStorage.biomate_afterrun = 'v2'` persistence)
- 5 tabs working with real data on dev; 2 tabs hidden
- Validate against the 6 CLAUDE.md scenarios (ADMET, RNA-seq, WGS, CryoEM, CRO compliance, drug discovery IND)
- Internal users + selected pilot accounts test

**v1 — feature parity (target +1 week):**
- Backend routes added: Software, Citations
- Methods endpoint cached
- Per-file inline preview wired
- Findings included in download report (lift FindingsCard fetch into AfterRunReport)
- Telemetry events added
- All 7 tabs render

**v2 — default flip (target +2 weeks):**
- `useAfterRunFlavor()` default → `'v2'`
- v1 after-run UX kept for one week as rollback
- Delete v1 FindingsCard inline render from `chat-interface.tsx`
- Delete v1 viewer's findings + methods-report download (consolidated in panel)

## 13. Open questions

### 13.1 Should Findings text be in the downloaded report?
Today it's a pointer ("see the live endpoint"). To include the prose would require lifting FindingsCard's fetch up into AfterRunReport. **Recommendation:** yes, lift it (~20 LOC) for v1 so the downloaded report is self-contained.

### 13.2 Should the panel auto-expand the right panel width when shown?
Today the workflow panel defaults to 520 px. The 7-tab bar fits at 380 px, the Methods body wants ≥600 px to avoid awkward wrapping. **Recommendation:** auto-grow to 720 px on first mount, persist user resize.

### 13.3 What happens for chained / pipeline runs (workflow_chain feature)?
Each sub-run produces its own outputs. **Open:** does the panel show one combined AfterRunReport for the chain, or one per sub-run with a chain-level summary on top? Probably the latter — needs a separate `<ChainSummary>` component above N `<AfterRunReport>`s.

### 13.4 Should methods-report be markdown rather than plain text?
The current backend returns plain text with `#` headers (markdown-ish). If we treated it as markdown and rendered with `react-markdown`, the user would get rendered headings + tables. **Recommendation:** yes, switch in v1 — no backend change needed, just frontend rendering.

### 13.5 Re-run from After-run?
A "Run again" button in the Parameters tab would short-circuit the v1 viewer's existing run-again-with-edits flow. **Recommendation:** wire it for v1 — single biggest UX win for power users iterating on params.

## 14. Out of scope (don't expand without re-review)

- Multi-run comparison (Compare run A vs run B) — separate `ComparisonCard` feature in v2 sandbox; tracked under Phase 5
- Streaming updates of After-run sections while run is in flight — over-scope; live updates are the viewer's job
- AI chat-back-into-context ("Ask AI about these findings") — already covered by FindingsCard's `onContinueAnalysis`; do not duplicate
- Sharing a run link with non-BioMate users — out of scope; needs auth + permission model work
- IND / regulatory export — separate IND-report module already exists; do not bundle

---

## 15. Appendix — diff vs v1

| User action | v1 path | v2 (this design) |
|---|---|---|
| See what the run found | scroll chat for FindingsCard | Findings tab |
| Open an image output | Outputs section in viewer step list | Outputs tab → click row (v1 follow-up for inline preview) |
| Bulk download outputs | Footer "Download All" button on viewer | Outputs tab → Download all ZIP |
| Get methods narrative | Sidebar Methods Report download link | Methods tab (in-panel) + included in comprehensive report |
| See submitted params | Read from chat user message | Parameters tab |
| Inspect QC gates | Live alerts during run; QC modal | QC audit tab (timeline of events) |
| Get reproducibility bundle | No surface (URL only) | Outputs tab → Reproducibility bundle button |
| Cite the workflow in a paper | No surface | Citations tab (v1) |
| List software versions | Pre-run docs only | Software tab (v1) |
| Comprehensive offline report | None | Download report button (v0) |
