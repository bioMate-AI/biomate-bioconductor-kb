# Grounded UI-Backend Alignment Roadmap

Timestamp: 2026-03-01 13:25

## Scope and method

This roadmap is based on the **current implemented state**, not hypothetical architecture.
Interpretation is grounded in:

1. Main chat execution path (`chat-with-artifacts` -> `chat-interface` -> `chat-message` -> `nextflow-workflow-viewer`)
2. Unified execution API path (`/api/workflows/execute`, `/api/workflows/runs`, `/api/workflows/runs/:id/status`)
3. Poller/SSE orchestration (`galaxy-state-poller`, `workflow-sse`)
4. Existing AutoFix and Nextflow tracking contracts
5. Passing E2E/regression evidence from recent runs

## Current status matrix

### A) Multi-task run lifecycle

- **Backend capability**: COMPLETE
  - multiple runs supported
  - concurrent polling/sse design supports many invocation IDs
- **BioMate server orchestration**: COMPLETE
  - run creation/listing/status APIs in place
  - run records persisted and queryable
- **UI run management surface**: COMPLETE (recently added)
  - Run Manager panel, grouped buckets, quick switch, refresh, session filtering
- **Risk level**: low

### B) Session-context alignment

- **chatSessionId propagation**: COMPLETE
  - execution request includes `chatSessionId`
  - run list filtering supports `chatSessionId`
- **project-level grouping**: PARTIAL
  - projectId is present in APIs; UX-level project run views are not primary in chat shell
- **Risk level**: low-medium

### C) AutoFix vs manual retry de-dup

- **UI guard**: COMPLETE
  - retry actions disabled when autofix active
- **Server explicit guard**: COMPLETE
  - blocks explicit retry context while autofix active
- **Server implicit guard**: COMPLETE (conservative)
  - infers likely duplicate by recent failed same-workflow-name run + active autofix
- **Residual**: workflow-name heuristic can over/under-match
- **Risk level**: medium

### D) “While running” assistance (Claude-like)

- **Proactive surface**: COMPLETE (Stage-A)
  - background assist panel appears during active run
- **Actionability**: COMPLETE (Stage-A)
  - quick actions dispatch real chat prompts through normal pipeline
- **Outcome visibility per run**: MISSING
  - no per-run action history in run manager yet
- **Risk level**: medium (discoverability and traceability gaps)

### E) Galaxy internal work-management alignment

- **Invocation-centric polling model**: ALIGNED
  - poller and SSE keyed by invocation IDs
- **Status mapping consistency**: PARTIAL
  - multiple status domains (Galaxy invocation, Nextflow status, local execution status) are mapped but not fully normalized into one canonical user-facing state machine
- **AutoFix lifecycle surfaced to UI**: COMPLETE (normalized `autofix` in status)
- **Risk level**: medium

## What is definitively finished vs not finished

### Finished (production-usable)

1. Run Manager panel and quick-switch
2. Session-scoped run listing wiring
3. Background assist quick actions (real prompt dispatch)
4. AutoFix/manual retry de-dup guard (UI + server explicit + server implicit)

### Not finished / next hardening needed

1. Fingerprint-grade duplicate detection (instead of name-only inference)
2. Canonical combined status model (Galaxy + Nextflow + AutoFix) for simpler UI logic
3. Per-run background-action history and outcomes in Run Manager
4. Deterministic API-level tests for implicit guard branch

## Grounded next 3 implementation slices

These slices are chosen to extend existing code with minimal architectural risk.

### Slice 1 — Fingerprint-based retry de-dup (high value, low-medium risk)

Goal:
- reduce false positives/negatives from name-based implicit matching.

Approach:
1. Derive stable workflow fingerprint from execution request workflow definition:
   - canonicalize workflow step graph + tool IDs + key params (exclude volatile metadata)
2. Persist fingerprint on execution run record
3. Use fingerprint + recent failed run + active autofix for implicit retry blocking

Likely files:
- `frontend/server/routes.ts`
- `frontend/server/storage.ts`
- `frontend/shared/schema.ts`

Acceptance:
- implicit guard uses fingerprint first, falls back to normalized name only if fingerprint missing.

### Slice 2 — Canonical run status adapter (high value, medium risk)

Goal:
- present one consistent status object to UI to avoid drift across multiple status sources.

Approach:
1. Server creates `runLifecycle` object in `/api/workflows/runs/:id/status`:
   - `phase`: queued/running/completing/completed/failed/cancelled
   - `engineState` (raw)
   - `autofixState` (normalized)
   - `progress` normalized
2. UI reads only `runLifecycle` for panel badges/controls.

Likely files:
- `frontend/server/routes.ts`
- `frontend/shared/schema.ts`
- `frontend/client/src/hooks/useUnifiedExecution.ts`
- `frontend/client/src/components/chat-with-artifacts.tsx`
- `frontend/client/src/components/nextflow-workflow-viewer.tsx`

Acceptance:
- no direct component reliance on mixed raw states for core button gating.

### Slice 3 — Run Manager background-action timeline (medium value, low risk)

Goal:
- make “while running” actions auditable and useful.

Approach:
1. Record selected background action in run interactions (`type=background_action`)
2. Surface recent actions under each run item in Run Manager (collapsed by default)

Likely files:
- `frontend/client/src/components/chat-with-artifacts.tsx`
- `frontend/server/routes.ts` (if server-side interaction write endpoint is used directly)
- optionally `frontend/client/src/hooks/useUnifiedExecution.ts` (`recordInteraction`)

Acceptance:
- selecting a background action shows in run history with timestamp.

## Alignment verdict

Based on current implementation:

- **“Backend finished but not wired to UI?”** — this was mostly true historically, but is now largely resolved for run discovery/switching and background parallel actions.
- **“Aligned with Galaxy internal management?”** — mostly aligned at invocation/polling level, with remaining improvement needed in canonical cross-source status normalization and stronger duplicate inference fingerprinting.

## Recommendation

Proceed with Slice 1 first (fingerprint de-dup), then Slice 2 (status adapter), then Slice 3 (action timeline).

This order minimizes risk:
1) correctness hardening,
2) state-model simplification,
3) UX traceability enhancement.

