# Leverage-First Plan: Multi-Chat, Multi-Workflow UX on Top of Galaxy/Galaxy-Nextflow (2026-03-03 14:08)

## Why this plan exists
- We should not rebuild proven community capabilities already present in Galaxy/Galaxy-Nextflow.
- BioMate's job is to provide a chat-first orchestration and UX layer while using Galaxy as execution truth.
- This plan is based on:
  - code audit of current frontend/server implementation,
  - product-management review,
  - UX-optimization review.

---

## Executive conclusion
- **Do not build from scratch.**
- **Leverage strategy**:
  1. Reuse Galaxy/Galaxy-Nextflow for execution state, provenance, logs, and outputs.
  2. Use BioMate to normalize and present that truth in a chat-first experience.
  3. Close current UX gaps in run scoping, multi-chat discoverability, and run-to-output traceability.

---

## What already exists and should be leveraged

## A) Existing backend run model (already in BioMate, should be extended, not replaced)
- Unified execution run APIs already exist:
  - `GET /api/workflows/runs`
  - `GET /api/workflows/runs/:id`
  - `GET /api/workflows/runs/:id/status`
  - pause/resume/cancel/compare endpoints.
- `chatSessionId` is already stored on execution runs and queryable.
- Existing run status endpoint already enriches data with:
  - `nextflowStatus`,
  - `autofix` lifecycle,
  - `artifactReadiness` contract.

**Leverage action**: extend this model to power richer run manager summaries and multi-chat run navigation; do not create a second run-state system.

## B) Existing run manager UX (already implemented, needs hardening)
- Current UI has:
  - run buckets (`running/queued/failed/completed`),
  - quick switch per run,
  - periodic refresh and manual refresh.
- Current list fetch uses `chatSessionId` filter, meaning run manager currently emphasizes current-chat scope.

**Leverage action**: keep current panel architecture, add all-chats scope toggle, search/filter/sort, and stronger run provenance anchors.

## C) Existing async assistant-in-parallel actions (already functional)
- Buttons while workflow runs are predefined prompts, but they are operational:
  - click -> create `externalPromptRequest` -> auto-send via `ChatInterface`.
- This is not fake UI; it is a functional shortcut pattern.

**Leverage action**: convert hardcoded options into registry-driven actions; keep current prompt-dispatch mechanism.

## D) Existing log and outputs bridging (already improved)
- Nextflow evidence is already surfaced:
  - log tail,
  - runtime status and IDs,
  - runtime artifact extraction.
- Output hydration now supports:
  - Galaxy datasets,
  - runtime artifact materialization fallback.

**Leverage action**: harden readiness and provenance display consistency across runs/chats; avoid building a separate logging/output backend.

---

## What Galaxy/Galaxy-Nextflow already provides (must remain source of truth)
- Invocation/job lifecycle truth.
- Dataset history/provenance and download/display mechanisms.
- Retry/operational semantics.
- Nextflow runtime introspection integrated in Galaxy-nextflow ecosystem.

**Rule**: BioMate UI state must reconcile to Galaxy truth; never diverge into a competing scheduler/state authority.

---

## Current multi-chat + multi-workflow status (what is covered now)

## Already covered
- Multiple chats are supported.
- Each run stores `chatSessionId`.
- Run list API supports filtering by `chatSessionId`.
- Run manager can switch to a selected run and load its state.

## Not fully covered yet (high-value gaps)
- No first-class "all chats" operational view in run manager.
- Limited run manager scalability (bucket truncation, no robust search/filter/sort).
- Run-to-message/output provenance can feel ambiguous in dense chat histories.
- Cross-chat handoff is functional but not explicit enough for user confidence.

---

## Product and UX risks if unchanged
- **Trust risk**: users cannot quickly prove "which run produced these outputs."
- **Operational risk**: multi-run monitoring degrades with scale; hidden failed/stalled runs.
- **Cost risk**: avoidable duplicate reruns due to poor status clarity.
- **Support risk**: triage burden rises because evidence is split and context switches are error-prone.

---

## Anti-patterns to avoid
- Rebuilding a second execution scheduler in BioMate.
- Creating a separate provenance truth store independent of Galaxy history.
- Chat-only run ownership where runs disappear outside origin thread.
- Over-automation of retries/actions without explicit auditability and user control.
- Dashboard-heavy rework before reliability and traceability are solid.

---

## Leverage-first roadmap (detailed)

## Phase P0 (must-do first): trust and scope correctness
Timeline: 1-2 weeks

### P0.1 Run identity and provenance anchoring
- Add strict run context chips in workflow/output surfaces:
  - `Run ID`, `Galaxy Invocation ID`, `Nextflow Run ID`.
- Ensure output/log panels are anchored to focused run identity.
- Acceptance:
  - every displayed output card maps to one focused run and invocation,
  - no ambiguous run context in UI panels.

### P0.2 Multi-chat scope control in Run Manager
- Add scope toggle:
  - `Current chat` (existing behavior),
  - `All chats` (new).
- Keep existing API and pass/omit `chatSessionId`.
- Acceptance:
  - user can find active runs across chats in <= 3 interactions.

### P0.3 Run list discoverability uplift (using existing data)
- Add search and filter:
  - workflow name,
  - status,
  - updated time,
  - output readiness.
- Add sort:
  - newest,
  - longest running,
  - failed first.
- Acceptance:
  - run retrieval success rate in UX test > 90% for 20+ run dataset.

---

## Phase P1: operational parity uplift without backend reinvention
Timeline: 1-2 weeks after P0

### P1.1 Run summary view-model endpoint (aggregation only)
- Build lightweight server adapter using existing run + status data.
- No new scheduler/state machine.
- Fields:
  - canonical IDs,
  - status,
  - progress,
  - last log line,
  - output readiness,
  - updatedAt.
- Acceptance:
  - list query p95 under agreed threshold,
  - consistent mapping with run status endpoint.

### P1.2 Run focus mode in chat canvas
- Clicking run manager item sets `focusedRunId` and highlights linked workflow artifact.
- Auto-scroll to run-origin artifact when possible.
- Acceptance:
  - switch-to-context time reduced by >= 30% in test script.

### P1.3 Error triage hierarchy
- Standardize order:
  1. status and reason,
  2. actionable next step,
  3. logs preview,
  4. outputs state.
- Reuse existing `executionGuidance`, `autofix`, `artifactReadiness`.
- Acceptance:
  - reduced repeated retry loops without state change.

---

## Phase P2: UX optimization and telemetry-driven refinement
Timeline: 1 week after P1

### P2.1 Replace hardcoded async options with action registry
- Keep existing prompt dispatch path, but move choices/config to registry.
- Add capability metadata and guardrails per action.
- Acceptance:
  - actions configurable without component code edits.

### P2.2 Confusion index telemetry
- Use existing telemetry events to detect confusion patterns:
  - rapid run switching without meaningful interaction,
  - repeated retries without progress,
  - repeated error displays,
  - output dead-end patterns.
- Acceptance:
  - weekly confusion dashboard and top offender flows.

---

## Requirements checklist (for implementation tickets)
- Canonical run mapping fields always visible in run-focused UI.
- Run manager supports current-chat/all-chat scopes.
- Run manager supports filter/search/sort and pagination/load-more.
- Focused run context is explicit in chat and output surfaces.
- Output cards always indicate source run/invocation.
- Run switching preserves and restores scroll/context deterministically.
- Retry/cancel/pause actions remain idempotent and auditable.
- Error surfaces include actionable "next step", not just failure text.
- Telemetry captures run-switch churn and confusion indicators.
- Feature flags gate rollout by phase.

---

## Rollout and safety gates
- Feature flags:
  - `VITE_RUN_MANAGER_SCOPE_TOGGLE`,
  - `VITE_RUN_MANAGER_ADVANCED_FILTERS`,
  - `VITE_RUN_FOCUS_MODE`,
  - `VITE_ASYNC_ACTION_REGISTRY`.
- Gate criteria:
  - no run-state divergence from Galaxy truth in validation sample,
  - no regression in existing strict complete workflow E2E,
  - run retrieval and switch UX targets met.

---

## Test strategy (incremental)

## E2E additions
- Multi-chat run visibility:
  - create runs in chat A and chat B,
  - verify scope toggle behavior and switching.
- Run focus anchoring:
  - select run from manager,
  - verify corresponding artifact/output context aligns.
- Run manager scaling:
  - 20+ mock/real runs, verify search/filter/sort outcomes.
- Failure triage:
  - failed run shows cause + actionable next step + logs + outputs state.

## Non-E2E checks
- API contract tests for run summary adapter.
- Telemetry contract checks for confusion heuristics.

---

## Explicit answer to "is multiple chats with different workflows taken care of already?"
- **Partially yes**: foundation exists (`chatSessionId`, run filtering, run switching).
- **Not complete for production-grade UX**: all-chats operational visibility, robust discovery, and run-context anchoring need strengthening.

This plan intentionally reuses existing, proven systems and focuses new work on UX trust, discoverability, and cross-chat operational clarity.
