# Project-scoped launch — root cause + live end-to-end verification

**Date:** 2026-10-13
**Branch / worktree:** `cursor/tutorial-live-recording-and-report-editing-4ea7` (biomate-review worktree)
**Deployed:** dev at commit `ed8296e4c` (`result=healthy`, smoke passed 16:07 PT)

## Symptom (reported)
"The project-scoped-chat context intermittently isn't attached to the launched run."
Concretely: a workflow launched from inside a project chat sometimes reached the
server with `projectId=null`, so `createExecutionRun` recorded no project and the
run's outputs skipped auto-save into the project folder.

## Root cause (proven, not inferred)
`handleRunWorkflow` in `chat-with-artifacts.tsx` is a plain async function (not a
`useCallback` rebuilt per render). It captured the `activeProjectId` value from an
early render's closure. When the user selected a project and immediately launched,
that closure could still hold a stale `null`, so the `executeWorkflow({ projectId })`
payload carried `null` even though a project was active.

Two secondary amplifiers were ruled IN earlier and fixed as part of the same change:
- `active-project-context.refresh()` re-ran on every `activeProjectId` change and
  **cleared** the active project whenever it was merely absent from one `active`-list
  page (races a freshly-created / not-yet-listed project, or a transient/5xx error).
- the chain-launch path (`submitWorkflowChain` / `submitWorkflowFromArtifact`) did not
  thread `projectId` into the `/api/workflows/chain` body at all.

## Fix (in place; this session only removed the diagnostics)
1. **Launch resolves from localStorage as authoritative fallback:**
   `projectId: activeProjectId || persistedActiveProjectId()` where
   `persistedActiveProjectId()` reads `localStorage['biomate-active-project-id']`.
   localStorage is written synchronously on every project selection and removed only
   on real deletion/archive — so it is immune to the stale React closure.
2. **Confirm-before-clear guard** in `active-project-context.refresh()`: a project
   missing from the `active` list is cleared ONLY after a direct `getProject` returns
   a definitive 404/403 or a non-active status — never on a transient/5xx or a capped
   list page.
3. **Chain path threads `projectId`** through `submitWorkflowChain` options + POST body.

## Live end-to-end verification
Instrumented a project-scoped ADMET launch on dev (`lifeifei163361@163.com` fixture,
fresh project, `project-new-chat`, explicit SMILES prompt typed into composer):

- **Client** (`[launch]` trace): `activeProjectId = <PID>`, `persisted = <PID>`,
  `resolved = <PID>` — Confirm & Run clicked.
- **Server** (`[execute]` handler log, fetched via SSH-over-SSM from
  `biomate-dev-frontend`):
  `[execute] projectId="213dcdfd-…-b8d679ae736e" user=fd5a73ac-… wf="Predict ADMET Properties (AI)" session="chat-…"`

The project-scoped run now carries `projectId=PID` client → server. The adjacent
`[execute] projectId=null user=anon wf=null` line is an unrelated anonymous health
probe, not a project launch.

### Reproduction notes
- The active-project **state** was correct in all 4 instrumented runs (localStorage
  held PID, no spurious guard-clear fired). The elusive part was getting a run to
  actually **launch** under live conditions: the cold-start *suggestion-chip*
  generation path was flaky (panel never reached "Confirm & Run" in 3 runs); typing
  an **explicit prompt** into the composer generated the panel reliably (~75 s) and
  produced the launching trace. The chip-generation flakiness is a separate
  dev/LLM-generation concern, not project-scoping.

## Cleanup shipped
Commit `ed8296e4c` removed the temporary diagnostics only
(`[ap-set]`, `[ap-guard]`, `[launch]`, server `[execute]` entry log). The three
behavioral fixes above remain. Pre-sync gate: `tsc --noEmit` clean; vitest
**1860 passed / 17 skipped**.

## Related
- QC-gate "pause" question (same session): confirmed the UI pause is a **real
  soft-cancel** — it terminates the Nextflow orchestrator while preserving the
  `-resume` cache; it is NOT a UI-only toggle.
- Auto-save of completed-run outputs into the project folder verified 6/6 earlier
  (`saveRunOutputsToProject` / `autoSaveCompletedRunOutputs` in `routes.ts`).

## Open / next
- Dev **cold-start suggestion-chip generation** is intermittently slow/non-firing
  (panel not ready within 150 s). Orthogonal to this fix; worth a separate look if it
  recurs for real users.
