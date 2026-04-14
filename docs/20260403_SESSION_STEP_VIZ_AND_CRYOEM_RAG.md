# Session Log — 2026-04-03: Cryo-EM RAG Wiring + Per-Step Output Visualization

**Branch**: integration/next-phase

---

## Work Completed

### 1. Cryo-EM RAG → galaxy-assistant.ts wiring

**File**: `frontend/server/galaxy-assistant.ts`

Added `_fetchCryoEmContext(query, sampleClass?)` private method (line 834). When `preferredDomains` includes `cryo_em`, calls `POST /api/cryo_em/context` on the Galaxy backend and injects the returned context (~1100 tokens: structured protocol JSON + parameter table + top-5 RAG chunks) into the system prompt just before `buildDomainSpecialistBlock`.

- 4-second timeout via `AbortSignal.timeout(4000)` — never blocks response
- Returns empty string on any failure (context is optional enrichment, not required)
- `isCryoEmDomain = preferredDomains.includes('cryo_em')` flag controls the fetch

The static `DOMAIN_SPECIALIST_GUIDANCE['cryo_em']` string (the MW parameter table and 5-step decision block) is now *supplemented* by live RAG results from the 150-chunk SQLite-vec index built in the previous session.

---

### 2. Per-step output visualization + parameter adjustment

**Design plan**: `docs/20260403_STEP_OUTPUT_VIZ_PLAN.md`  
**Implementation doc**: `docs/20260403_STEP_OUTPUT_VIZ_IMPLEMENTATION.md`

#### New files
- `frontend/client/src/components/step-output-preview.tsx` — inline file preview; 8 viewer modes (image, table, sequence, text, HTML, structure, density, download); blob URL lifecycle; error display
- `frontend/client/src/components/step-adjust-modal.tsx` — step parameter editor dialog; boolean→Switch, number→Input, string→Input; POSTs to rerun endpoint; loading/error states

#### Modified files
- `frontend/client/src/components/phase-card.tsx` — `outputFiles`, `onPreviewFile`, `onAdjustAndRerun` props; eye button per visualizable file; gear button for completed steps; `displayFiles` computed from `outputFiles ?? taskFiles`
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — imports both new components; `previewFile`/`adjustStep`/`rerunRunId` state; maps `nextflowStatus.processes[].task_files` to structured `outputFiles[]`; passes `outputFiles={phase.outputFiles}` and both callbacks into `PhaseCard`; uses `activeRunId = rerunRunId ?? runId` after rerun
- `frontend/server/routes.ts` — new `GET /api/workflows/runs/:id/step-file` (stream file, path validation, Content-Type inference) and `POST /api/workflows/runs/:id/rerun-from-step` (Nextflow -resume with param overrides)

#### Audit findings (2 critical bugs found and fixed)

**Bug 1**: `outputFiles={phase.outputFiles}` was missing from the `<PhaseCard>` call. The prop was computed and stored inside `phase` but never extracted and passed explicitly. File lists would never have rendered.

**Bug 2**: After `onRerunSubmitted(newRunId)`, the viewer kept polling the old `runId`. Fixed by adding `rerunRunId` state and `activeRunId = rerunRunId ?? runId` derived value. Viewer now seamlessly switches to the new run.

#### Documented limitations
1. MRC/MAP: download link only (binary format, needs desktop viewer)
2. PDB/mmCIF: text preview only (3Dmol.js requires Galaxy output URL)
3. S3 step files: `step-file` endpoint reads local disk only; S3 paths return 404 (future: proxy through aws s3 cp)
4. `rerunRunId` not persisted across page reloads
5. `step.parameters` reflects workflow-level params, not process-level runtime params (Nextflow trace limitation)

---

## TypeScript Status

Zero `error TS` at session end. Pre-existing error in `server/routes.ts` (one unrelated type issue) was fixed as a side effect.

---

## Next: Agent Architecture Discussion

See `docs/20260404_AGENT_ARCHITECTURE_DESIGN.md` for the full proposal on relaxing prompt constraints and adding a Tier-1 code execution path.
