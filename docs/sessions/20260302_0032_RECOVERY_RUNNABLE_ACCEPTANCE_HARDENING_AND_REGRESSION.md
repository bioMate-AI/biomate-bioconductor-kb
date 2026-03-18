## 2026-03-02 00:32 - Recovery Runnable Acceptance Hardening + Regression

### Scope
- Continue real-user BioMate system testing and close remaining backend acceptance gap for prerequisite-recovery workflow selection.
- Validate that recovered workflows are accepted only when runnable for their execution engine.

### Root Gap Confirmed
- `frontend/server/galaxy-api-proxy.ts` previously accepted Nextflow recovery candidates using a permissive rule: any `nextflow_path` ending with `.nf` was treated as runnable.
- This could mark a recovery candidate as valid before confirming the script was actually executable in practice.

### Fix Implemented
- Hardened recovery runnable check inside `generateWorkflow()` in `frontend/server/galaxy-api-proxy.ts`.
- Added filesystem-backed Nextflow validation:
  - confirm candidate path exists,
  - support both absolute and relative path candidates (`cwd`, repo root sibling, `../backend`),
  - parse script text and require an executable workflow signature:
    - anonymous entry: `workflow { ... }`, or
    - named entry workflow block: `workflow <name> { ... }`.
- Updated `isExecutableNextflowPath()` to call this stricter runnable validator instead of relying on extension-only checks.

### Why This Aligns With Prior Entry-Resolution Work
- Backend (`nextflow_executor.py`) now resolves named entry workflows at runtime.
- This frontend-server hardening does not duplicate runtime entry resolution; it prevents non-runnable candidates from being selected during recovery trials.
- Combined behavior:
  - selection phase: reject non-runnable candidates earlier,
  - execution phase: resolve/append `-entry` when needed.

### Validation Evidence
- Focused full matrix after prior subworkflow fix:
  - `npx playwright test e2e/complete-workflow.e2e.ts e2e/pm-user-stories-comprehensive.e2e.ts e2e/ux-artifact-readiness-silent.e2e.ts --project chromium --retries=1`
  - Result: **5 passed**.
- Post-hardening targeted reruns:
  - `npx playwright test e2e/complete-workflow.e2e.ts --project chromium --retries=1`
  - Result: **1 passed**.
  - `npx playwright test e2e/pm-user-stories-comprehensive.e2e.ts e2e/ux-artifact-readiness-silent.e2e.ts --project chromium --retries=1`
  - Result: **4 passed**.

### Real-User Correctness Signals Observed
- Workflow generation returned runnable Nextflow artifact after prerequisite recovery.
- Run button became actionable after recovery turn.
- Unified execution reached terminal `completed` with Nextflow success.
- Frontend showed both:
  - visualization cue (`View Results` visibility), and
  - downloadable output cue (`Download` visibility).
- Silent `artifactReadiness` telemetry path remains non-intrusive and test-covered.

### Remaining Known Risk (Tracked)
- Repeated `GET /api/workflows//invocations/<id>` 404 polling appears in backend logs due to empty Galaxy workflow id in Nextflow-only runs.
- Current behavior is non-blocking (Nextflow status path still provides correct run completion), but this should be cleaned up to reduce noisy log/error surfaces.

### Next Actions
1. Suppress/skip Galaxy invocation polling when execution is Nextflow-only and workflow id is absent.
2. Re-run full regression bundle after that cleanup.
3. Keep collecting silent telemetry for artifact-readiness misses to prioritize backend output hydration improvements.
