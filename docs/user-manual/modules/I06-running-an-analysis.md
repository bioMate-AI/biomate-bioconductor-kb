# Running an analysis (the run lifecycle)

> One-line promise: after this page you know exactly how a workflow goes from a sentence you type to
> a finished, reproducible result — and where each thing lives. For everyone.

<!-- Every claim here is code-verified (tier C); see coverage-ledger.md "## I.6 Running an analysis". -->

## What this is for

BioMate is a **conversation**, not a dashboard. You describe a goal in plain language; BioMate proposes
a validated workflow; you confirm it; it runs on the cloud; and the result comes back **in the same
place you were talking** — the run panel that opens beside the chat. This page maps that whole flow so
nothing feels like a black box.

## Where things live (the surfaces)

There is **no separate "runs" page.** The platform is the chat.

| Surface | Route | What it is |
|---|---|---|
| **The platform** (chat + cold-start modules + run panel) | `/` | Where you work: describe goals, run workflows, read results. `App.tsx` → `RootRoute` → `AppSidebar` + `ChatWithArtifacts` (`App.tsx:684`, `:218`). |
| **Cold-start modules** | `/` (first screen) | The entry doorway — the function-module cards you start from (see I.1). |
| **Files / data hub** | `/files` | Datasets as first-class objects (quality, lineage, versions) — see I.5 (`App.tsx:673`). |
| **Models / Design & generate** | `/models`, `/design` | Focused tool surfaces (see I.10, I.11). |
| **IND report / Drug-discovery CRO** | `/ind-report`, `/drug-discovery-cro` | Domain workspaces (see the Drug-discovery chapter). |
| **Workflow deep-link** | `/workflow/:id` | Opens a specific generated workflow in the run panel (`App.tsx:681`, `WorkflowDeepLink.tsx`). |
| **Billing** | `/billing` | Usage & quota (see I.13). |

> **Pitfall — there is no `/dashboard`.** The old dashboard route is retired (commented out in
> `App.tsx:608`). **A run is not a standalone page** — it belongs to the **chat session** it was
> started in. To revisit a run, open its session in the sidebar (sessions carry a run-status dot);
> the run panel and its after-run report re-open there.

## The run lifecycle, step by step

1. **Describe the goal** in the composer (see I.2). BioMate routes it — Instant answer vs a Cloud
   workflow (see I.1's two-lane model).
2. **BioMate proposes a workflow card** in the chat. When you open it, the **run panel**
   (`NextflowWorkflowViewer`) opens to the right; `chat-with-artifacts.tsx:181-184` sets the panel
   workflow and calls `onWorkflowPanelOpenChange(true)`.
3. **Pre-run (idle).** The panel shows the workflow name, a **parameter strip** with values pre-filled
   from your request, the input slots (inputs-mapped), any QC-gate settings, and a **"Confirm and run
   workflow"** action (`nextflow-workflow-viewer.tsx:3011`, action bar `:3638`).
   - If a required input or param is missing, the panel **blocks** with a "Fix now / Confirm anyway"
     alert rather than launching blind.
   - You can edit parameters here, or just tell BioMate in chat ("use GRCh38", "drop sample 3") — the
     panel applies the edit (`applyWorkflowEdits`, `chat-with-artifacts.tsx:224, 278`).
4. **Confirm & Run.** `handleRunWorkflow` (`chat-with-artifacts.tsx:1074`) calls `executeWorkflow`
   (`:1179`), which launches the pipeline on **AWS Batch** and returns a `runId`.
5. **Running (live).** The panel subscribes to a server-sent-events stream —
   `new EventSource('/api/workflows/:invocationId/events')` (`nextflow-workflow-viewer.tsx:2100`) — and
   updates in real time: the overall badge goes `data-status="running"`, and each phase/step card
   flips `pending → running → completed` (or `failed`) as the pipeline progresses (`:608, :744`).
   Long runs (cryo-EM, MD, large WGS) can be **detached** — see the Pitfalls.
6. **QC gates & auto-loop.** When a QC gate trips, the panel surfaces it; for domains with an auto-loop
   (e.g. ADMET), a remediation card shows the was→now parameter change and re-runs. Gates are HALT
   (stops + remediates) or ADVISORY (logs, continues). *(Details per domain; see the domain chapters.)*
7. **Completed / Failed → the after-run report.** The panel swaps to `AfterRunReport`
   (`chat-with-artifacts.tsx:2371`) with three tabs — **Summary** (headline findings, the immutable
   "run original"), **Outputs** (files, with in-app viewers — see I.8), and **Reproducibility record**
   (parameters, software, citations, checksums — see I.9). A failed run shows the offending step, the
   error, and a path forward instead of a spinner.
8. **Iterate.** "Run again with edits" re-launches with adjusted parameters via
   `/api/workflows/runs/:id/rerun` (`nextflow-workflow-viewer.tsx:1663`), or the after-run report
   dispatches the same re-run into the chat panel (`chat-with-artifacts.tsx:447`).

## What you control before running

- **Parameters** — edit in the param strip, or in chat by describing the change.
- **Inputs** — attach in the composer (see I.2) or from `/files`; the panel shows how each input mapped.
- **QC thresholds** — per-metric gate settings where the workflow exposes them.
- **Lane** — override Instant↔Cloud when you want the other behavior (see I.1).

## Reading live progress

- **Overall badge** — `idle → running → completed/failed`.
- **Phase cards** — one per pipeline phase; expand to see steps and their live status.
- **Step outputs** — appear as each step finishes; open them in the in-app viewers (I.8).

## After the run

Everything the run produced is in the after-run report (I.9) and, as first-class dataset objects, in
`/files` (I.5). Outputs carry provenance back to the step that made them (I.7). Numbers in the Summary
link to the output they came from.

## Pitfalls & tips

> **Tip — the run lives in its chat session.** Closing the panel doesn't lose the run; reopen the
> session to get it back.

> **Pitfall — long runs and the browser.** Cloud runs continue on AWS Batch even if you navigate away;
> for very long runs (cryo-EM/MD/large WGS) detach rather than holding the tab open
> (`docs/20260422_BIOMATE_USER_TUTORIALS.md §13`).

> **Tip — you don't need workflow names.** Describe the goal; routing picks the workflow (see I.1).
> Add a disambiguating word when two workflows fit (e.g. "germline" vs "somatic") to skip the
> clarify step.

## What's not covered

- A standalone run-history/detail page (runs live in their chat session; there is no `/runs` route).
  If a cross-session "all my runs" view is wanted, that's a design decision — Appendix E.
- Cost/runtime shown before Confirm & Run — intentionally off (see I.13; the estimate badge is
  disabled). Expected timing is set by the domain chapter, not a per-run number.

---
_Verification: coverage-ledger.md "## I.6 Running an analysis" — all tier C (source-read); no Batch
runs fired._
