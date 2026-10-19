# Run History / QC Report / Step View — Diagnosis, Plan, Work Queue

**Date:** 2026-10-19
**Status:** Diagnosed (empirically on dev); plan + parallel work queue below.

---

## Issue 1 — After-run QC tab shows "QC passed" instead of the formatted QC document

**Not a regression of the formatting.** The rich QC document still exists:
`QcAuditTab` in `client/src/v2/AfterRunReport.tsx` renders a 4-stat header (Gates
evaluated / Passed / Auto-corrected / Manual), the audit-log table (Time · Gate ·
Threshold · Observed · Result · Action, with pass/fail→loop treatment), and the
chain-of-custody block — **but only when `qcEvents` is non-empty.**

The big "All quality gates passed" is `QcAuditTab`'s **empty-state fallback**
(`events.length === 0`). It shows because **`qcEvents` comes back empty** for the run.

**Root cause (confirmed below):** QC events are **not durably persisted** per run, so a
reopened/historical run returns `source: not_found`, `events: []`.

---

## Issue 2 — Reopening a project run loses the after-run panel

### What the code does
- **Reopen path (project page):** clicking a run sets `selectedRunId` →
  `NextflowWorkflowViewer` with `runId` + `workflowDefinition` + `status=completed`.
  It does **not** pass `invocationId`; `AfterRunReport` falls back to
  `idForBackend = invocationId || runId`, and the qc-events proxy resolves
  `backendId = storage.getInvocation(id)?.galaxyInvocationId || id`.
- **Reuse path (`reuseWorkflow`, e.g. dataset "open run"):** fetches the run, **strips
  `galaxyInvocationId` + `nextflowRunId`**, loads a blank template for a **fresh** run —
  history intentionally discarded. This is a *different* action from reopen.

### Empirical confirmation (dev, a real completed run — runId `300e4067…`, invId `f49ef474…`)
| Data | By runId | By invId | Persisted? |
|---|---|---|---|
| **Outputs** (`/api/invocations/:id/outputs`) | returns files | returns files | ✅ yes |
| **QC events** (`/qc-events`) | `source:not_found`, `events:[]` | same | ❌ no |
| **Findings** (`/api/workflows/runs/:id/findings`) | `status:"pending"` (recompute-on-access) | — | ❌ not stored |

**So history is only partially maintained:** outputs persist; **QC events and findings
do not.** On reopen the QC tab falls back to "passed", and findings re-trigger/show
"pending". The frontend id-passing is secondary — the *data* is `not_found`.

> Caveat to confirm: `source:not_found` could also mean a workflow with no QC gates.
> Verify against a QC-gated run (ADMET-hERG). But findings being "pending" + QC absent
> while outputs persist is the clear structural gap.

### The architecture (answers "where to keep history" / "reuse vs reopen")
1. **Keep history (source of truth):** at **run completion**, durably persist the
   after-run **QC events** and **findings** the same way outputs already are — a DB row
   and/or an S3 report JSON keyed by invocation/run id. (Outputs already do this.)
2. **Reopen = read-only history:** clicking a run loads its persisted after-run record
   (outputs + the full QC gate table + findings) by invocation/run id. Also pass the
   real `invocationId` from the run object into `NextflowWorkflowViewer` so every
   after-run fetch resolves without relying on the runId fallback.
3. **Reuse = a separate, explicit "Run again" action:** the `reuseWorkflow` path (load
   definition, strip ids, fresh run). Never the default click.

### Fix plan
- **Backend (primary):** persist QC events + findings at completion
  (`nextflow_executor.py` completion path → storage/S3), keyed by invocation id; serve
  them from the persisted store on `/qc-events` and `/findings` for historical runs.
- **Frontend (secondary):** `project-detail.tsx` reopen passes
  `invocationId={run?.execution?.galaxyInvocationId}`; keep reopen (history) and reuse
  (`reuseWorkflow`) as distinct, clearly-labeled actions.
- **Verify:** reopen a QC-gated completed run (ADMET) and confirm the gate table +
  findings render from persisted data.

---

## Step View — status

**Implemented:** `client/src/components/steps/step-detail.tsx` is the full step view,
opened as an **in-artifact panel** (not a Dialog) via `button-full-step-view-*`.
`buildStepDetailStep` derives everything from **real run fields** (missing → "tool not
reported" / "(version n/a)"; no invented values). Surfaces: provenance row
(inputs → tool+version → N outputs · duration), output tabs + **evidence-class dots** +
**rendered ⇄ raw**, **editable resolved parameters** (origin badges + per-row revert +
**Apply & re-run from here**), footer download. EN + 中文. States handled: running,
no-outputs, no-params, binary/unreadable, unknown origin.

**Intentionally excluded (user calls, 2026-10-19):** prev/next step traversal; open-as-
dataset (outputs already auto-file).

**Tested:** 8 unit tests (`step-detail.test.tsx`) + one live visual confirm.
**NOT done:** a fresh all-states / edge-case / spec-08 conformance pass — so it is
**not** "finished + detailed-tested." Exceptions to verify:
- Apply & re-run actually re-runs from edited params (live, not just wired).
- Rendered viewer across output types (image / table / FASTA / VCF / text / binary).
- Long param values + many outputs (overflow / tab wrapping).
- A running step's live refresh as it completes.
- Evidence-dot correctness per extension.

**Plan:** a step-view conformance + edge-case audit — capture every state on a real run,
spec-by-spec vs the design (same method as the i18n capture-audit).

---

## Work queue + parallelization

| # | Stream | Owner | Notes / sequencing |
|---|---|---|---|
| 1 | **Run-history persistence** (persist QC+findings; reopen≠reuse) | main session | Backend-led; the direct fix for Issues 1+2. |
| 2 | **Step-view conformance + edge-case audit** | subagent | Capture-based, independent — runs in parallel. |
| 3 | **QC-on-ingest flow Phase 0** (sample/full in QC request + auto-filing notice) | main session | Plan approved (`20261019_QC_ON_DATASET_FLOW_PLAN.md`); no backend. |
| 4 | **Tutorial walkthrough redesign** | handed to Claude design | Brief: `20261019_TUTORIAL_WALKTHROUGH_REDESIGN_BRIEF.md`. |
| 5 | **Prepare video-build materials** (NOT rebuild the videos) | main session | Get the inputs ready so the build is ready-to-go: ① corrected **narration** (done), ② **regenerated audio** from that narration (edge-tts), ③ **updated screenshots** in the asset slots. |

> **Scope note (2026-10-19):** do **not** re-record/re-mux the videos now. Only
> *prepare the materials*. The final assembly (`fit-scene-slots` → re-record webm →
> re-mux) happens **after** the walkthrough redesign (#4), on the user's go — because
> the redesign changes the slide HTML (so `fit` + re-record would be redone otherwise).
> Materials that are **redesign-independent** and prepared now:
> - **Audio** — regenerated from the corrected narration (text-only; independent of the
>   slide visual design).
> - **Screenshots** — captured from the current dev UI into the walkthrough asset slots
>   (the redesign brief keeps the `<img src="assets/…">` slots, so captures stay valid).

Manuals screenshots are done; narration source fixes are committed.
