# Workflow Panel — Extra Sections Audit
*2026-04-21 — Sections not covered by the Claude reference design*

These 12 sections exist in `nextflow-workflow-viewer.tsx` but have no equivalent in the
reference design (`reference/claude_design/biomate/src/`). For each one: what it is,
where it came from, whether it's essential, and a keep/cut recommendation.

---

## 1. Input Analysis Panel

**What it is**
A collapsible section inside "Workflow settings" that appears when the user clicks
"Analyze inputs". It calls `POST /api/workflows/analyze-inputs` with the current
parameter values. The backend (Claude Haiku) returns a list of recommendations — each
with a `parameter`, `risk_level` (high / medium / low), `reason`, and optionally a
`recommended_value`. Low-risk items are auto-applied silently. High-risk ones show a
yellow warning with an "Apply" button.

**When does it show?**
Only when `status === 'idle' || status === 'pending_review'` and there are rendered
parameters. The user must explicitly click "Analyze inputs" to trigger it.

**Is it used in demos / E2E tests?**
`button-analyze-inputs` testid exists. It's referenced in the UX E2E suite but not in
the demo scripts.

**Verdict: KEEP — but simplify**
The concept is valuable (AI sanity-checks params before running). But the current
implementation is buried inside the settings strip, which nobody opens. Consider
surfacing it as a one-line hint below the phase list instead of a full collapsible panel.

---

## 2. Validate Environment

**What it is**
A ghost button labelled "Validate environment" that runs `nextflow run ... -profile test`
on the backend for up to 120 seconds. Returns pass / fail / timeout, and a log tail.
Only shown for Nextflow workflows in idle/pending_review state.

**When does it show?**
Only when the workflow has a `nextflow_path` and is not yet running.

**Is it used in demos / E2E tests?**
`button-validate-environment` testid exists. Not used in any current demo or E2E test.

**Verdict: CUT**
Nobody uses it. A `-profile test` dry-run takes 2+ minutes and the output is
incomprehensible to non-developers. It was a developer debugging aid that leaked
into the UI. Remove entirely.

---

## 3. QC Settings Section

**What it is**
A collapsible section below the parameters strip with:
- A toggle switch: "Pause workflow when a QC gate fails"
- A list of editable number inputs — one per QC threshold metric (e.g. `min_resolution_angstrom`,
  `min_ctf_fit_score`). Values can be overridden per-run.
- A "Reset all" button.

The values come from `/api/qc/profiles` which returns 32 QC profiles. The active profile
is set per workflow (`workflowDefinition.qc_profile`).

**When does it show?**
Only when `availableQcProfiles.length > 0 || qcGateData !== null`.

**Is it used in demos / E2E tests?**
`qc-settings-section` testid exists and is asserted in Demo 5 (auto-loop QC). The
`pauseAtQcFailures` toggle directly controls whether the autoloop fires.

**Verdict: KEEP — but collapse by default and use reference CSS**
This is core to the QC/autoloop story. The reference design doesn't have number inputs
but the concept maps to `.param-row` style. Port the threshold editors to use
`var(--font-mono)` and `var(--border)` styling.

---

## 4. Autofix Status Panel + Active Banner

**What it is**
Two separate things:

**Autofix status panel** (`data-testid="autofix-status-panel"`) — shows
`autofix.state`, `autofix.totalAttempts`, `autofix.source`, `autofix.message`.
The `autofix` prop comes from the chat session's execution run metadata. It reflects
the backend's auto-retry loop (if a Nextflow process fails, the backend tries to
fix the NF script and resubmit automatically).

**Autofix active banner** (`data-testid="autofix-active-banner"`) — a blue
"Auto-fix is in progress" alert shown while `isAutofixActive === true`. It
disables the run button to prevent duplicate submissions.

**When does it show?**
Only when `autofix` prop is present on the current run, or when `autofix.state` is
`analyzing/fixing/restarting`.

**Is it used in demos / E2E tests?**
`autofix-status-panel` and `autofix-active-banner` testids exist. The autofix
mechanism was built in Session 3 UX. Not in demo scripts but does fire on real
failed Nextflow runs.

**Verdict: KEEP banner, CUT status panel**
The active banner (blue "fixing…" alert) is essential — without it the user would
click Run again and create a duplicate job. The status panel (state/attempts/source)
is debug noise for scientists. Replace with a simpler one-line `.alert.info` message.

---

## 5. Prereq Checklist

**What it is**
A red block listing "hard blockers" — prerequisites that prevent execution. Each item
has an `id`, `label`, `reason`, and optionally a `chatPrompt` link ("Continue in chat →").

The checklist comes from `normalizePrereqChecklist(panelWorkflow?.prerequisitesValidation)`.
Current known blocker types: `domain_guard` (wrong domain selected), `license_required`
(CryoSPARC license), `required_parameters` (unfilled required fields).

The `isPrereqBlocked` flag derived from this checklist disables the run button.

**When does it show?**
When `prereqChecklist.canRun === false` AND the blockers are not just missing input
data or parameters (those are handled by the "Required" badge on the settings strip).

**Is it used in demos / E2E tests?**
`workflow-prereq-checklist` and `prereq-chat-link-*` testids exist. Used in the
routing / license gating E2E tests.

**Verdict: KEEP — but render as `.alert.err` not a custom card**
This is a genuine UX need. A scientist must know why they can't run. The current
card design is fine functionally. Port it to use `.alert.err` with `.act` buttons
so it matches the reference visual system.

---

## 6. Dataset Session Panel

**What it is**
A small card inside "Workflow settings" listing files the user has uploaded in
this browser session (`.mrc`, `.tif`, `.fastq`, etc.). Each file has a "Use" button
that assigns it to the first unset file-type parameter. There is also a "Browse all
datasets…" link that opens the `GalaxyDatasetBrowser` modal.

The data comes from `sessionDatasets` state, which is populated from
`GET /api/datasets/session`.

**When does it show?**
When `sessionDatasets.length > 0`, inside the expanded "Workflow settings" strip.

**Is it used in demos / E2E tests?**
`session-dataset-panel` testid exists. Used in the cryo-EM file upload E2E tests
(6/6 passing).

**Verdict: KEEP — important for file upload workflow**
File upload is a core user action for cryo-EM (MRC files) and genomics (FASTQ files).
But the "Use" button UX is poor — it silently assigns the file to "the first empty
param" which may not be what the user wants. Consider showing a parameter selector.
No visual redesign needed beyond using design tokens.

---

## 7. Live Nextflow Process List

**What it is**
A table of every Nextflow process from the trace file — name, status
(SUBMITTED / RUNNING / COMPLETED / CACHED / FAILED), with an icon per status.
Data comes from `nextflowStatus.processes` which is polled from
`GET /api/workflows/runs/:id/status`.

**When does it show?**
When `Array.isArray(nextflowStatus?.processes) && nextflowStatus.processes.length > 0`.
In practice this only appears once the Nextflow trace file has been parsed on the backend
(usually 30–60 seconds after job start on AWS Batch).

**Is it used in demos / E2E tests?**
`nf-process-list` testid exists. Not directly asserted in demos but appears visually.

**Verdict: CUT — the phase cards already show this**
The `PhaseGroupSection` renders the same information (running/completed/failed steps)
more cleanly. The process list is a raw dump from the Nextflow trace file and shows
internal process names like `CRYOSPARC_SPA:EXTRACT_PARTICLES` that mean nothing to
a biologist. It was added as a debugging aid. Remove.

---

## 8. Logs Panel

**What it is**
A monospace `<pre>` block showing the last ~120 lines from `nextflowStatus.log_tail`.
These are the raw Nextflow execution logs — a mix of `INFO`, `WARN`, and Nextflow
framework messages. Lines are stripped of ANSI color codes via `stripAnsi()`.

**When does it show?**
Always — either shows the log lines or one of: "Waiting for logs...", "No logs available."

**Is it used in demos / E2E tests?**
`workflow-running-hint` testid (the "Workflow is running, logs take time to appear"
message) is asserted in some E2E tests. The log content itself is not asserted.

**Verdict: KEEP — but make it collapsible and hidden by default**
Raw logs are essential for debugging failed runs. Scientists need them when a workflow
fails unexpectedly. But showing them by default for successful runs is visual noise.
Make the log block collapsed by default (toggle: "Show logs / Hide logs") and only
auto-expand on `status === 'failed'`.

---

## 9. Download Commands Panel + Reproducibility Export

**What it is**
Two separate components defined at the top of the file:

**DownloadCommandsPanel** — calls `GET /api/workflows/runs/:id/download_commands`.
Returns a list of output files with presigned S3 URLs. Only renders when there are
files with actual URLs and non-zero sizes. Shows filename + file size + download link.

**ReproducibilityExportButton** — calls `GET /api/workflows/runs/:id/reproducibility`.
Returns a bundle of `nextflow.config`, pipeline version, params JSON, and environment
info as a single `.txt` file. Lets users reproduce the exact run on their own cluster.

**When does it show?**
Both only show when `status === 'completed' || status === 'failed' || status === 'running'`
and `runId` exists. `DownloadCommandsPanel` returns `null` if there are no presigned files.

**Is it used in demos / E2E tests?**
`download-commands-panel` is asserted in UC-7 (download validation test).
`ReproducibilityExportButton` has no E2E assertion.

**Verdict: KEEP DownloadCommandsPanel, CUT ReproducibilityExportButton**
Presigned file download links are essential — scientists need individual file access
(e.g., download just the VCF, not the whole archive). However `ReproducibilityExportButton`
is a developer feature that 0 pilot users have asked for. Cut it from the panel and move
it to a settings/advanced page if needed later.

---

## 10. Error Recovery Card

**What it is**
A red block shown when `status === 'failed'`. It calls `GET /api/workflows/runs/:id/findings`
on mount (via a `useEffect` triggered by the failed status) to get an AI-generated
error explanation. The explanation has:
- `human_summary` — plain-English description of what went wrong
- `suggested_fix` — what to do
- `chat_prompt` — a pre-filled chat message to send
- `error_type` — category (e.g. "docker_pull_error", "oom_killed")

If the AI explanation hasn't loaded yet, it shows the raw `errorMessage` prop.
Clicking "Fix & Retry via Chat" sends `chat_prompt` to `onAdjustViaChat`.

**When does it show?**
`status === 'failed'` only.

**Is it used in demos / E2E tests?**
`button-error-fix-chat` testid exists. Used in some E2E failure paths.

**Verdict: KEEP — but use `.alert.err` CSS**
This is genuinely valuable. When a batch job fails with an obscure Docker error at 3am,
the "Fix & Retry via Chat" flow is the core BioMate value prop. The current Tailwind
styling just needs to be ported to `.alert.err` + `.act` buttons.

---

## 11. Output Results + ChatOutputAttachments + FindingsCard

**What it is**
Three things shown when `invocationId && showResults` (triggered by clicking "View results"):

**ChatOutputAttachments** — renders output files from the Galaxy invocation
as cards: images, CSV previews, HTML reports, download links. This is the primary
output viewer — it shows what the workflow produced.

**FindingsCard** — calls `GET /api/workflows/runs/:id/findings` and shows an
AI-generated summary of the scientific results (e.g., "Best docking score: −8.4 kcal/mol,
GOLD level"). Has a "Continue analysis" button linking to chat.

**Runtime artifacts panel** — a small info box listing S3 file paths detected in the
trace output, used as a debugging aid when outputs seem missing.

**When does it show?**
Only after the user clicks "View results" (`showResults` state). The link is shown
only when `invocationId || status === 'completed'`.

**Is it used in demos / E2E tests?**
`button-view-results-link` testid is asserted in 7 of the 8 full workflow E2E tests.
`FindingsCard` is asserted in the cryo-EM tests via `findings-card` testid.

**Verdict: KEEP all three — these are the end product**
ChatOutputAttachments and FindingsCard are the scientific payoff of running a workflow.
Remove only the "Runtime artifacts" debug panel (the blue box showing raw S3 paths).

---

## 12. AI Analysis Panel

**What it is**
A full structured AI analysis triggered by clicking the "AI analysis" link (in the
post-run results links row). It calls `GET /api/workflows/runs/:id/ai-analysis` which
uses Claude to analyze the output files and return:
- `summary` — one-paragraph plain-English summary
- `key_findings` — bulleted findings with significance
- `quality_assessment` — data quality evaluation
- `next_steps` — recommended follow-up experiments
- `citations` — tool references with relevance notes
- `limitations` — caveats

**When does it show?**
Only when `analysisState === 'loading' || 'done' || 'error'` — triggered by clicking
"AI analysis" in the results links row.

**Is it used in demos / E2E tests?**
`ai-analysis-panel` testid exists. `button-analyze-results` is asserted in some E2E tests.
Demo 5 (auto-loop) references AI analysis of docking results.

**Verdict: KEEP — core differentiator, but visually port it**
This is one of BioMate's strongest differentiators vs. Galaxy/Nextflow Tower — the
AI reading your results and explaining them. The panel needs visual cleanup: use
`var(--text)`, `var(--surface)`, `var(--font-mono)` instead of Tailwind. The reference
`.findings-card` CSS maps directly to this concept.

---

## Summary Table

| # | Section | Keep? | Action |
|---|---------|-------|--------|
| 1 | Input analysis panel | Keep, simplify | Surface as hint, not buried in settings |
| 2 | Validate environment | **Cut** | Developer debug aid, remove |
| 3 | QC settings | Keep | Port to reference CSS `.param-row` |
| 4 | Autofix panel + banner | Keep banner, cut panel | Panel → one-line `.alert.info` |
| 5 | Prereq checklist | Keep | Port to `.alert.err` + `.act` |
| 6 | Dataset session panel | Keep | No visual change needed |
| 7 | Live process list | **Cut** | Duplicate of phase cards, raw names |
| 8 | Logs panel | Keep, collapsed by default | Auto-expand on failure only |
| 9 | Download commands + repro export | Keep commands, cut repro | Repro → advanced settings |
| 10 | Error recovery card | Keep | Port to `.alert.err` |
| 11 | Output results + findings | Keep all except S3 debug panel | Remove runtime artifacts box |
| 12 | AI analysis panel | Keep | Port to `.findings-card` CSS |

**Net result: cut 4 items** (validate env, live process list, autofix status panel,
reproducibility export, runtime artifacts debug box) — reducing the panel by ~20% of
its current content with no loss of scientist-facing value.
