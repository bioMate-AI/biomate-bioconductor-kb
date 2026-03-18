# Multi-Chat Run Manager Execution Handoff (2026-03-03 15:32)

## Purpose
- This is a team-assignment-ready implementation plan.
- Goal: improve BioMate multi-chat, multi-run UX by leveraging existing Galaxy/Galaxy-Nextflow truth and current BioMate implementation.
- Constraint: no scratch rebuild of scheduler/provenance systems.

## Source context
- Strategy doc: `20260303_1408_LEVERAGE_FIRST_MULTI_CHAT_RUN_MANAGER_PLAN.md`
- Existing UX backlog context: `20260301_1001_UX_WALKTHROUGH_REMAINING_WORK_AND_PARALLEL_EXECUTION.md`
- Current execution surfaces:
  - `frontend/client/src/components/chat-with-artifacts.tsx`
  - `frontend/client/src/components/chat-message.tsx`
  - `frontend/client/src/components/nextflow-workflow-viewer.tsx`
  - `frontend/client/src/components/chat-output-attachments.tsx`
  - `frontend/client/src/components/chat-interface.tsx`
  - `frontend/client/src/hooks/useUnifiedExecution.ts`
  - `frontend/server/routes.ts`
  - `frontend/server/storage.ts`

---

## Shared understanding (for all team members)

## What already exists (must reuse)
- Run APIs already exist:
  - `GET /api/workflows/runs`
  - `GET /api/workflows/runs/:id`
  - `GET /api/workflows/runs/:id/status`
  - pause/resume/cancel/compare endpoints.
- Execution runs already carry `chatSessionId`.
- Run manager UI exists with buckets and quick switching.
- Nextflow status, autofix lifecycle, and artifact-readiness are already enriched in run status.
- Output hydration includes Galaxy datasets plus runtime-artifact fallback materialization.

## What is partially covered
- Multiple chats + workflows are supported structurally, but UX is still mostly current-chat scoped.
- Cross-chat operational visibility and high-confidence run-to-output traceability are not yet production-grade.

## Non-goals
- Do not build a second scheduler/state machine.
- Do not introduce separate provenance truth from Galaxy history/invocation.
- Do not redesign the whole app IA before fixing run trust/discoverability.

---

## Architecture contracts (must stay true)

## Run truth contract
- Canonical status truth: Galaxy/Galaxy-Nextflow + current BioMate run status adapter.
- BioMate UI only normalizes/presents; no competing status authority.

## Identity mapping contract
- Every run-focused UI must support explicit mapping:
  - `ExecutionRun.id`
  - `execution.galaxyInvocationId`
  - `execution.nextflowRunId` (when available)

## Scope contract
- Run manager must support:
  - `Current chat` scope
  - `All chats` scope
- Current behavior (`chatSessionId` filter) remains default for backward compatibility.

---

## Workstreams and assignment-ready tickets

## WS1 - Backend Adapter and Contracts
Owner profile: Backend engineer
Priority: P0

### Ticket WS1-T1: Run overview adapter endpoint
- Objective: expose list-friendly summary model using existing run data.
- Add endpoint:
  - `GET /api/workflows/runs/overview`
- Query params:
  - `scope=current_chat|all_chats`
  - `chatSessionId` (required for `current_chat`)
  - `status`, `search`, `sort`, `limit`, `offset`
- Return fields per run:
  - `runId`, `workflowName`, `status`, `updatedAt`, `createdAt`
  - `chatSessionId`
  - `progressPercent`
  - `artifactReadiness`
  - `ids: { galaxyInvocationId, nextflowRunId }`
  - `lastLogLine` (best-effort)
- Files:
  - `frontend/server/routes.ts`
  - `frontend/server/storage.ts` (add helper query and optional filters)
- Acceptance:
  - endpoint returns deterministic summaries
  - supports both current-chat and all-chat scopes
  - does not alter existing `/api/workflows/runs` behavior

### Ticket WS1-T2: Run summary consistency test
- Add tests for adapter correctness against existing run status endpoint.
- Files:
  - `frontend/server/workflow-execution.test.ts` (or new test file)
- Acceptance:
  - state mapping parity validated for running/queued/failed/completed
  - no null-ID regressions

---

## WS2 - Run Manager UX v2 (Leverage Existing Panel)
Owner profile: Frontend engineer (state + UI)
Priority: P0

### Ticket WS2-T1: Scope toggle and persistent selection
- Add `Current chat / All chats` toggle in run manager header.
- Persist user selection in local state (or local storage key).
- Wire fetch behavior:
  - current chat -> include `chatSessionId`
  - all chats -> omit `chatSessionId`
- Files:
  - `frontend/client/src/components/chat-with-artifacts.tsx`
- Test IDs:
  - `run-manager-scope-toggle`
  - `run-manager-scope-current-chat`
  - `run-manager-scope-all-chats`
- Acceptance:
  - toggling immediately reloads list
  - no crash when `currentChatSession` is null

### Ticket WS2-T2: Search/filter/sort
- Add controls:
  - search by workflow name/run id
  - status filter
  - sort (updated desc, running first, failed first)
- Use server-side query params if available; fallback to client-side for first pass.
- Files:
  - `frontend/client/src/components/chat-with-artifacts.tsx`
- Test IDs:
  - `run-manager-search-input`
  - `run-manager-filter-status`
  - `run-manager-sort-select`
- Acceptance:
  - retrieval within 3 interactions for 20+ runs

### Ticket WS2-T3: Run card metadata hardening
- Show explicit IDs and freshness:
  - short run id
  - invocation id (short)
  - last update age
  - output readiness badge
- Files:
  - `frontend/client/src/components/chat-with-artifacts.tsx`
- Acceptance:
  - each card includes enough context to avoid wrong-run clicks

---

## WS3 - Run Focus and Traceability in Chat
Owner profile: Frontend engineer (chat rendering)
Priority: P0

### Ticket WS3-T1: Focused run context chip
- Add context chip near workflow/output area:
  - `Run <id> | Inv <id> | NF <id>`
- Add on every run-focused viewer surface.
- Files:
  - `frontend/client/src/components/nextflow-workflow-viewer.tsx`
  - optionally `frontend/client/src/components/chat-message.tsx`
- Test IDs:
  - `run-context-chip`
- Acceptance:
  - chip always visible for workflow artifacts with run context

### Ticket WS3-T2: Run switch anchoring
- On run manager switch:
  - set `focusedRunId`
  - auto-scroll to closest corresponding workflow artifact in chat
  - highlight active artifact card briefly
- Files:
  - `frontend/client/src/components/chat-with-artifacts.tsx`
  - `frontend/client/src/components/chat-interface.tsx` (if needed for anchor API)
- Acceptance:
  - run switch lands user on the right artifact region

### Ticket WS3-T3: Message/run mismatch guard
- Audit invocation resolution priority to reduce stale context leakage.
- Ensure output attachments map to focused run context where possible.
- Files:
  - `frontend/client/src/components/chat-message.tsx`
  - `frontend/client/src/components/chat-output-attachments.tsx`
- Acceptance:
  - no visible mismatch between selected run and shown outputs in test scenario

---

## WS4 - UX Quality and Confusion Telemetry
Owner profile: UX engineer + analytics
Priority: P1

### Ticket WS4-T1: Confusion index signals
- Add lightweight derived metrics from existing telemetry:
  - run-switch oscillation
  - retry-without-progress
  - repeated error surfaces
  - output dead-end loops
- Files:
  - `frontend/client/src/lib/ux-telemetry.ts` and related consumers
  - optional backend aggregation route
- Acceptance:
  - confusion signals available in logs/monitoring for QA

### Ticket WS4-T2: Triage hierarchy consistency
- Standardize execution panel ordering:
  - status -> guidance -> logs -> outputs.
- Ensure `Report confusion` remains accessible.
- Files:
  - `frontend/client/src/components/chat-with-artifacts.tsx`
  - `frontend/client/src/components/nextflow-workflow-viewer.tsx`
- Acceptance:
  - consistent UI structure across states

---

## WS5 - PM + QA Validation
Owner profile: PM + QA lead
Priority: P0/P1 gates

### Ticket WS5-T1: Acceptance script and UAT checklist
- Define UAT scenarios:
  - two chats, multiple runs each, mixed statuses
  - switch across chats, then switch runs
  - verify run context and outputs are correct
- Deliverable:
  - test script doc + expected screenshots/evidence points

### Ticket WS5-T2: E2E suite additions
- New tests:
  - `frontend/e2e/run-manager-multi-chat-scope.e2e.ts`
  - `frontend/e2e/run-manager-switch-anchoring.e2e.ts`
  - `frontend/e2e/run-manager-search-filter-sort.e2e.ts`
  - `frontend/e2e/run-context-traceability.e2e.ts`
- Keep existing strict complete workflow E2E as non-regression gate.

---

## Dependency and sequencing map
- WS1-T1 is prerequisite for WS2 advanced filtering/sorting when server-side used.
- WS2-T1 and WS3-T1 can run in parallel.
- WS3-T2 depends on WS2 run selection behavior.
- WS4 can begin after WS2/WS3 baseline UX is stable.
- WS5 test authoring can start early; final execution after WS2+WS3 merge.

Recommended order:
1. WS1-T1
2. WS2-T1 + WS3-T1 (parallel)
3. WS2-T2 + WS2-T3 + WS3-T2 (parallel)
4. WS3-T3
5. WS4-T1 + WS4-T2
6. WS5-T2 run and sign-off

---

## Assignment template (copy/paste for team board)
- Ticket:
- Owner:
- Reviewer:
- Scope:
- Files:
- API changes:
- Test IDs:
- Acceptance criteria:
- Risk:
- Rollback:

---

## Risks and mitigations per workstream
- WS1 risk: API bloat/duplication.
  - Mitigation: adapter-only endpoint; reuse existing storage models.
- WS2 risk: state complexity in run manager UI.
  - Mitigation: incremental controls, retain current behavior as fallback.
- WS3 risk: wrong anchor resolution in long chats.
  - Mitigation: deterministic run/message keying + e2e anchoring tests.
- WS4 risk: telemetry noise.
  - Mitigation: start with logging thresholds, tune post-pilot.
- WS5 risk: flaky e2e due async hydration timing.
  - Mitigation: keep robust polling and explicit readiness checks.

---

## Rollout plan
- Flag set:
  - `VITE_RUN_MANAGER_SCOPE_TOGGLE`
  - `VITE_RUN_MANAGER_ADVANCED_FILTERS`
  - `VITE_RUN_FOCUS_MODE`
- Stages:
  1. local dev validation
  2. internal canary
  3. full enable after 2 green CI cycles + UAT sign-off

---

## Definition of done (global)
- All P0 tickets merged behind flags.
- Existing strict `complete-workflow` E2E remains green.
- New multi-chat run manager E2Es green.
- PM/UX sign-off on UAT checklist.
- No observed run-context mismatch in QA replay scenarios.

