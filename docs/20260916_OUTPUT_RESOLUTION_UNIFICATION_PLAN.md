# Output-resolution unification — nextflow-centric single resolver (staged plan)

**Date:** 2026-09-16
**Origin:** the "should we unify to nextflow?" question, after a session of patching one output-resolver bug after another (owner-403 on outputs, single-file download 404, reproducibility-record 0-outputs, findings "output files could not be read"). Two read-only audits (resolver-fragmentation map; Galaxy-execution liveness) confirmed the root cause and the fix.

Supersedes/extends `docs/20260518_OUTPUTS_SERVICE_CONSOLIDATION_SPEC.md` (adds the auth-unification + backend-persistence scope the earlier spec omitted).

---

## Root cause (one line)

The only **persisted** facts live on the `ExecutionRun` (owner `userId`/`projectId`, `nextflowOutputDir`, sometimes `nextflowStatus.s3_output_files`) — but the surfaces that break read outputs from **`WorkflowInvocation` and `OutputDataset` maps that are in-memory only (no Postgres table)** and die on every container restart. So a completed run's outputs are downloadable on one endpoint and 403/404/0 on another after a gunicorn recycle.

Every output patch shipped this session (galaxy-id auth fallback in `output-access.ts`, the S3 branch in `/api/outputs/:id/download`, findings "Fallback A") is a **symptom fix** for this and becomes unnecessary once the resolver is unified.

## The fragmentation (from the audit)

- **10 resolvers (R0–R9)**, each with a different expected id and store. `R0` = `runs-outputs-service.ts` is the canonical one and **survives restart** (persisted ExecutionRun + live S3), but only ~3 of ~8 surfaces use it.
- **5 id types** in play: `runId` (ExecutionRun UUID) · `galaxyInvocationId` · `nextflowRunId` · `WorkflowInvocation` PK · `OutputDataset` PK.
- **Persistence verdict:** `ExecutionRun` → Postgres (survives). `WorkflowInvocation` + `OutputDataset` → in-memory Zod maps, **no pgTable** (die on restart). `metadata.s3Uri` per output is set *lazily* into the in-mem map on first `/api/invocations/:id/outputs` hit → gone on restart → owner-403 / download-404 / findings-unreadable.
- The design reference already mandates the fix: *"A single artifact resolver remains an internal invariant across all surfaces"* (`SIMPLIFICATION_DECISIONS.md`).

## Canonical model

```
CanonicalOutput { id: `${runId}:${s3Key}`, runId, name, extension, fileType,
                  s3Uri, s3Bucket, s3Key, size, sizeBytes, sha256?,
                  downloadUrl (presigned), step, previewable }
```
**Authoritative store = `execution_runs` (Postgres).** Add a persisted per-run output manifest, written **once at terminal state** by a single `RunsOutputsService.registerOutputs(runId, CanonicalOutput[])` — the sole writer. Owner and `s3Uri` both come from the run, so **owner can never fail to resolve** and no surface re-derives it from an output id. In-memory maps demoted to a 60s cache.

---

## Level 1 — one canonical resolver over a persisted store (ship first; independent of Galaxy)

Staged as shippable PRs (extends the 20260518 spec with L1c auth + L1a persistence):

### L1a — persisted store + single writer (foundation) → task #33
- Add `output_manifest jsonb` on `execution_runs` (or a `run_outputs` child table keyed by `run_id`).
- `RunsOutputsService.registerOutputs(runId, outputs)` = the sole write path, called at terminal state.
- Backend `nextflow_executor.py`: mirror `s3_output_files` into the RunStateStore at completion (`~:4261`) so Redis (not only Postgres-via-poll) carries it — closes the "lost if no poll before restart" window.
- `runsOutputsService.list(runId)` reads the persisted manifest first (then live-S3 fallback for pre-migration runs). +tests.

### L1b — repoint all READ surfaces to the resolver → task #34
- record (R2 `routes.ts:12145`), output_files (R3 `:12219`), invocations/outputs (R4 `:8993`), download-all (R7 `:9559`), findings reader (R8 `:13936`), outputs-tab/UI → all call `runsOutputsService.list(runId)`; delete their bespoke prefix-derivation / in-mem cascades.

### L1c — unify AUTH surfaces + delete the invocationId walk → task #35
- download / preview / display (R5/R6 `:9496,9667`) and download-all resolve by `runId` (id = `runId:s3Key`) → authorize via `decideRunAccess(run)`.
- **Delete `accessTargetForOutputInvocationId` / the `output → invocationId → run` walk** in `output-access.ts` — the sole reason owner-403 exists.
- Retire the symptom patches (galaxy-id fallback, findings Fallback A, ad-hoc S3 download branch) — now redundant.
- Keep a legacy-id shim mapping `${invId}:…` → `${runId}:${s3Key}` for one release. Extend `output-access.test.ts`.

### L1d — legacy removal + cache demotion → task #36
- Remove superseded endpoints (301/aliases), demote MemStorage `invocations`/`outputs` maps to cache, manual smoke on a fresh run + a post-restart run.

**Risk: medium overall** (auth path change is the sensitive part — covered by `output-access.test.ts`, extend it; behavior-preserving on the happy path). **Effort ~2–3 days.** **Closes the entire bug class.**

---

## Level 2 — drop Galaxy execution (follow-on simplification) → task #37

Removes the second id-space (`WorkflowInvocation` PK, `OutputDataset` PK, `galaxyDatasetId`), the Galaxy-only `/api/invocations/:id/report`, and the "two run models" confusion permanently.

**Liveness verdict: GALAXY EXECUTION IS VESTIGIAL — L2 is a GO.** Every real run executes as Nextflow on AWS Batch: the default engine is `nextflow` (`routes.ts:217-248`), the Nextflow-direct branch returns before the Galaxy fall-through (`routes.ts:10618,10868`), chains are sequential Nextflow (`workflow_chain.py`), and CryoSPARC falls back to Nextflow-on-Batch. The Galaxy path survives only as: unreachable fall-through (`routes.ts:10905`), an orphaned route + UI (`/api/galaxy/workflows/invoke` → `useWorkflowExecution.ts` → `enhanced-workflow-builder.tsx`, imported by no live page), `isGalaxyInvocation` report branches that never fire (Nextflow legacy invocations set `galaxyWorkflowId:''`), test specs, and **one dormant source branch** (`ai_assistant.py:5173` `template_reuse→galaxy`, only reachable by a pure `galaxy_ga` DB match — negligible against the 2,455 Nextflow workflows).

**Remove at the source:** neuter the `template_reuse→galaxy` emission (`ai_assistant.py:5173` + the `galaxy-reuse` tag at `:5229`) so any surviving `galaxy_ga` match routes through the Nextflow composer (as the medium-confidence branch already does). Then the `'galaxy'` return in `getWorkflowExecutionEngine`, the `/api/workflows/execute` Galaxy fall-through, the orphaned invoke route + UI, and the `isGalaxyInvocation` branches are all provably dead and removable; retire `WorkflowInvocation` legacy-record writes in favor of `ExecutionRun`. Verify no historical run still needs `galaxyDatasetId` downloads before deleting those branches. **Do not couple to L1.** (Tracked as task #37.)

---

## Sequencing
L1a → (L1b ∥ L1c) → L1d. L1 is independent and closes the bug class on its own — ship it first. L2 waits on the liveness verdict.
