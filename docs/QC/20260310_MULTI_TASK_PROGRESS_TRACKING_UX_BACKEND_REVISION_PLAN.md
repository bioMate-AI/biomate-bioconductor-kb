# BioMate Multi-Task Progress Tracking Revision Plan (UX + Backend)

Date: 2026-03-10  
Owner: BioMate product + engineering  
Audience: Product, engineering, QA, demo stakeholders  
Status: Proposed implementation plan for execution

---

## 1) Executive Summary

This plan upgrades BioMate’s multi-task experience from “run list + polling snapshots” to a professional task-operations UX with deterministic backend state semantics.

Primary outcomes:

1. Users can reliably track multiple active tasks across chats.
2. Every stalled/failed task provides a typed reason and concrete next action.
3. Progress updates are more real-time, less noisy, and less ambiguous.
4. Drug-development workflows receive higher quality failure diagnostics and guided recovery.

---

## 2) Problem Statement

Current strengths:

- There is a `Run Manager` panel with grouped statuses.
- Run details include context chip, triage summary, and run controls.
- Step-wise execution and per-step rerun already exist.

Current gaps:

1. **Status meaning ambiguity**
   - “running” can mask “waiting on dependency” or “search timeout recovery”.
2. **Inconsistent blocker visibility**
   - Users do not always see a structured, typed blocker reason in one consistent place.
3. **Actionability varies**
   - Failures can be descriptive but not always operationally actionable.
4. **Cross-chat operations need stronger prioritization**
   - Multiple concurrent runs need faster “what needs attention now?” filtering.
5. **Search timeout degradation affects confidence**
   - Upstream 60s search timeout causes stalled user perception.

---

## 3) Product Goals and Non-Goals

### Goals

1. Make multi-run tracking first-class for PM/scientist workflow.
2. Normalize run state transitions and expose them to UI in deterministic form.
3. Turn failures into guided recovery paths.
4. Reduce perceived latency and avoid opaque waiting states.
5. Keep full compatibility with existing run controls and step rerun UX.

### Non-goals (this phase)

1. Full orchestration engine rewrite.
2. Long-term queue scheduling/prioritization by cluster resource class.
3. Replacing existing workflow generation pipeline.

---

## 4) UX Revision Plan

## 4.1 Run Manager (global operations console)

Current: bucketed list (`running/queued/failed/completed`) with scope/sort/filter/search.  
Revision:

1. Add **Needs Attention** bucket (derived state):
   - `failed`
   - `blocked_missing_inputs`
   - `blocked_tool_unavailable`
   - `degraded_timeout_recovery`
2. Add compact run metadata chips:
   - scientific domain (`drug-dev`, `rna-seq`, `cryo-em`, etc.)
   - stage (`searching`, `building`, `running`, `postprocess`)
   - health (`healthy`, `degraded`, `blocked`)
3. Add primary CTA per run row:
   - `Resolve Inputs`
   - `Retry Search`
   - `Open Logs`
   - `View Outputs`
4. Add “last transition reason” tooltip text:
   - e.g., “tool search timeout (auto-fallback active)”
5. Keep `Current chat` / `All chats`, but persist user’s selected scope.

## 4.2 Run detail panel

Revision:

1. Add **normalized timeline**:
   - `queued -> preparing -> running -> postprocessing -> completed/failed/blocked`
2. Add **blocker card** (always visible when not healthy):
   - blocker type
   - detected timestamp
   - remediation steps
3. Add **decision-oriented action drawer**:
   - one-click helper prompts to continue execution safely
4. Separate visual messaging:
   - progress vs waiting/recovery vs hard failure

## 4.3 Background Assist panel

Current: available while workflow runs with helper actions.  
Revision:

1. Convert helper actions into task cards with status:
   - `pending`, `running`, `ready`, `failed`
2. Each completed card includes “insert into chat” or “attach to report”.
3. Include generated artifacts and timestamps for auditability.

## 4.4 Notification behavior

Revision:

1. Transition-based notifications only (no repetitive polling noise).
2. Sticky notifications for “needs attention” transitions.
3. Optional digest mode for heavy multi-run sessions.

---

## 5) Backend Revision Plan

## 5.1 Unified run state contract

Introduce/standardize a canonical response shape used by:

- `/api/workflows/runs`
- `/api/workflows/runs/:id/status`
- SSE updates for run changes

Proposed fields:

```json
{
  "runId": "string",
  "status": "queued|preparing|running|postprocessing|completed|failed|blocked|cancelled",
  "stage": "search|workflow_generation|execution|artifact_hydration|done",
  "health": "healthy|degraded|blocked",
  "progress": {
    "kind": "step_based|time_based|unknown",
    "percent": 0,
    "completedSteps": 0,
    "totalSteps": 0
  },
  "blocker": {
    "type": "missing_inputs|tool_unavailable|search_timeout|runtime_error|auth_boundary|unknown",
    "message": "string",
    "firstSeenAt": "iso-timestamp",
    "nextActions": ["string"]
  },
  "nextAction": "string",
  "lastTransition": {
    "from": "string",
    "to": "string",
    "reason": "string",
    "at": "iso-timestamp"
  }
}
```

## 5.2 Event-driven updates (SSE-first)

Add/normalize run transition SSE stream:

- Event types:
  - `run_state_changed`
  - `run_progress`
  - `run_blocked`
  - `run_recovered`
  - `run_completed`
  - `run_failed`
- Include monotonic `eventSeq` to prevent out-of-order UI update regressions.
- Fallback to polling if stream unavailable.

## 5.3 Timeout and degradation handling

Issue observed: tool/dataset search calls can hit 60s timeout and degrade experience.  
Plan:

1. Introduce interactive-path fast timeout budget:
   - tool search: ~8-12s
   - dataset search: ~8-12s
2. Use partial-result strategy:
   - return available context instead of waiting full upstream timeout.
3. Emit typed degraded state:
   - `blocker.type = search_timeout`
   - include next actions (`retry`, `narrow scope`, `provide must-use tool hints`)

## 5.4 Structured diagnostics persistence

Persist `workflowGenerationDiagnostics` for unresolved runs:

- likely reasons
- recommended actions
- follow-up questions
- process outputs snapshot

Expose this in run APIs and run detail panel for continuity across refresh/chat switches.

## 5.5 Search/cache strategy

1. Short TTL cache for query-normalized search responses.
2. Request coalescing for duplicate in-flight search terms.
3. Per-session concurrency guardrails to avoid stampede patterns.

---

## 6) Drug-Development Quality Integration

Because drug-development guidance quality is high-stakes, include contract checks:

1. For drug-development unresolved states, response metadata must include:
   - at least 2 blocker categories
   - at least 2 follow-up questions
   - explicit next-step guidance
2. Ensure stream path and non-stream path produce equivalent quality diagnostics.
3. Preserve decision-gate language for operational review.

---

## 7) Implementation Phases

## Phase 1: Contract + state normalization (Backend-first)

Scope:

- Add normalized run state envelope
- add blocker typing + last transition reason
- enable unresolved-state diagnostics in all response paths

Deliverables:

- backend response schema updates
- compatibility adapters in frontend data layer
- telemetry for state transition counts

Success criteria:

- UI can render new states without regressions
- no API consumers broken

## Phase 2: Run Manager UX upgrade

Scope:

- Needs Attention bucket
- domain/stage/health chips
- primary CTA per run item
- persisted scope and sort preferences

Success criteria:

- PM can identify highest-priority run in <=5 seconds

## Phase 3: Run detail + blocker action drawer

Scope:

- normalized timeline
- explicit blocker card
- guided recovery actions

Success criteria:

- every non-healthy run has visible reason + next action

## Phase 4: Event-driven progress + timeout hardening

Scope:

- SSE transition events + eventSeq
- search fast-fail budgets
- degraded-mode fallback semantics

Success criteria:

- reduced “silent waiting” intervals
- fewer >30s uninformative waits in UX

## Phase 5: QA hardening + demo readiness

Scope:

- expand real E2E suites
- run PM acceptance checklist
- produce demo script and evidence pack

Success criteria:

- comprehensive UX + professional-quality suites pass
- no blocker-class regressions in final run

---

## 8) QA and Validation Strategy

## 8.1 Automated E2E

Must-pass suites:

1. `frontend/e2e/drug-development-ux-comprehensive.e2e.ts`
2. `frontend/e2e/drug-development-professional-quality.e2e.ts`

Add new suites:

1. `multi-run-manager-priority.e2e.ts`
   - verifies needs-attention ordering and primary CTAs
2. `search-timeout-degraded-mode.e2e.ts`
   - verifies typed blocker + fallback actions under induced timeout
3. `run-sse-ordering.e2e.ts`
   - verifies event sequence ordering and UI stability

## 8.2 Manual PM checks

Checklist:

1. Start 3+ tasks across different chats.
2. Switch to All chats and identify top-priority issue run quickly.
3. Confirm each blocked run shows reason + next action.
4. Confirm recovery action changes state deterministically.
5. Confirm no ambiguous “running” state with no explanation.

---

## 9) Metrics and Telemetry

Track before/after:

1. Time to first actionable diagnosis for failed run.
2. Percent of failures with typed blocker classification.
3. Mean user recovery completion time from blocked state.
4. Search-timeout incidence and degraded recovery success rate.
5. Multi-run panel usage (scope toggle, filter usage, CTA clicks).

---

## 10) Risks and Mitigations

1. **Risk:** More state complexity can confuse implementation.
   - Mitigation: strict canonical schema + typed enums.
2. **Risk:** SSE event ordering issues.
   - Mitigation: monotonic `eventSeq` and idempotent reducer.
3. **Risk:** Fast timeout may reduce search recall.
   - Mitigation: staged fallback + background continuation + retry CTA.
4. **Risk:** UI clutter with added metadata.
   - Mitigation: compact chips + progressive disclosure in detail pane.

---

## 11) Rollout and Communication

Rollout:

1. Feature flag for normalized states.
2. Internal QA on flag.
3. PM validation session.
4. Staged rollout (dev -> staging -> production).

Communication package (for sharing):

1. This plan document.
2. API contract diff.
3. UX screenshots/video snippets per phase.
4. E2E pass/fail matrix.

---

## 12) Definition of Done

Done means all are true:

1. Multi-run tracking supports 3+ concurrent runs with clear prioritization.
2. Every non-healthy run has typed blocker and concrete next action.
3. Search timeout never appears as unexplained waiting.
4. Real E2E suites pass (UX + professional quality).
5. PM can run end-to-end demo without manual debugging intervention.

---

## 13) Immediate Next Steps (Execution-ready)

1. Implement canonical run-state envelope in backend.
2. Add Needs Attention bucket and row-level CTA in Run Manager.
3. Add blocker card + action drawer in run detail.
4. Introduce fast-fail search timeout and degraded-state fallback.
5. Add/execute new E2E tests for multi-run and timeout degradation.
6. Publish demo-readiness report with final evidence links.

---

## 14) Workflow Email Notifications Plan (Complete/Failed)

Goal: ensure users are reliably notified by email when workflows complete or fail, across all execution paths.

### 14.1 Current baseline (already present)

1. Email templates/mailer exist:
   - `sendWorkflowCompleteEmail(...)`
   - `sendWorkflowErrorEmail(...)`
2. Notification service exists:
   - `workflow-notification-service.ts`
   - listens to workflow completion/error events
3. Registration currently happens in one workflow invocation path.

### 14.2 Gaps to close

1. Invocation registration not guaranteed for all run start paths.
2. Active notification state currently in-memory only.
3. User notification preferences are default-only (not persisted per user).
4. Delivery observability/retry for transient SMTP failures is limited.

### 14.3 Target architecture

1. **Notification registration contract**
   - Any workflow start path must call a shared registration helper.
2. **Persistent notification queue/state**
   - Store pending notification intents in DB with status:
     - `pending`, `sent`, `failed`, `retrying`
3. **Delivery worker**
   - Background sender with retry policy (exponential backoff, capped attempts).
4. **User preferences**
   - Persist per-user toggles:
     - `emailOnComplete`
     - `emailOnError`
5. **Audit + telemetry**
   - Track delivery success/failure and latency.

### 14.4 API and data model additions

1. New table (example):
   - `workflow_notifications`
   - fields: `id`, `invocationId`, `userId`, `type`, `payload`, `status`, `attempts`, `lastError`, `createdAt`, `sentAt`
2. Preferences table/column extension:
   - `user_notification_preferences`
3. Optional internal endpoint:
   - trigger/replay notifications for failed sends (admin/dev only).

### 14.5 UX additions

1. Settings page “Notifications” section:
   - email on completion toggle
   - email on failure toggle
2. Run details:
   - show email notification state (“queued/sent/failed”).
3. Optional user-facing retry button for failed notification delivery.

### 14.6 Acceptance criteria

1. For any authenticated run start path, a notification record is created.
2. Completion/failure sends exactly one email per invocation outcome (idempotent).
3. SMTP transient failures retry automatically and are visible in telemetry.
4. Preference toggles are respected in real execution.
5. Real E2E verifies both success and failure email paths.

---

## 15) Team Collaboration Split (Parallel Workstreams)

The work is split for parallel execution across teams with clear handoffs.

### Track A: Backend runtime/state team

Scope:

- canonical run-state envelope
- typed blocker semantics
- SSE transition contract + ordering
- fast-fail search timeout and degraded mode

Deliverables:

- backend API contract changes
- migration notes and compatibility layer
- backend unit/integration coverage

### Track B: Notification platform team

Scope:

- persistent workflow notification queue
- unified invocation registration helper across all start paths
- retry/idempotency logic
- preferences persistence

Deliverables:

- notification DB schema + service
- notification delivery metrics + audit events
- email reliability test suite

### Track C: Frontend UX team

Scope:

- Run Manager upgrades (Needs Attention + CTA + chips)
- run detail blocker card + action drawer
- notification settings UI + delivery status indicator
- low-noise transition notifications

Deliverables:

- component-level implementation
- UX states for healthy/degraded/blocked
- visual QA checklist

### Track D: QA/E2E team

Scope:

- extend real E2E suites for multi-run and degraded mode
- add email notification E2E verification
- flaky test controls and artifact capture

Deliverables:

- pass/fail matrix per phase
- reproducible scripts and evidence package

### Track E: PM/Release coordination

Scope:

- prioritize milestones
- demo readiness validation
- stakeholder communication

Deliverables:

- milestone acceptance sign-off
- release notes and demo narrative

### Handoff cadence

1. Weekly contract sync (A/B/C).
2. Mid-week integration check (A+C).
3. End-week verification review (D + PM).
4. Release-go/no-go based on Definition of Done.

### Suggested milestone ownership

1. Milestone 1 (state contract): **Track A**
2. Milestone 2 (Run Manager UX): **Track C**
3. Milestone 3 (notifications reliability): **Track B**
4. Milestone 4 (full validation): **Track D**
5. Milestone 5 (release/demo): **Track E**

---

## 16) Reuse-First Implementation Map (Galaxy + galaxy_nextflow)

This section maps existing implementations that must be reused before adding new behavior.

## 16.1 Galaxy capabilities to leverage

### A) Invocation/job state model (authoritative execution truth)

Source:

- `backend/lib/galaxy/webapps/galaxy/services/invocations.py`

Reuse intent:

1. Use invocation and job summaries as canonical backend evidence for run state.
2. Align BioMate normalized state mapping to invocation semantics first, then overlay UI-friendly labels.
3. Reuse existing access-control model for invocation visibility in cross-session/project contexts.

Expected integration:

- run state mapper uses invocation/job summaries as input.
- no duplicate shadow status model that diverges from invocation truth.

### B) Notification service + user preferences

Source:

- `backend/lib/galaxy/webapps/galaxy/services/notifications.py`
- `backend/lib/galaxy/webapps/galaxy/api/notifications.py`

Reuse intent:

1. Reuse notification preference semantics (category/channel style model).
2. Reuse async delivery approach and task-backed dispatch for reliable notifications.
3. Reuse preference API patterns for user settings integration.

Expected integration:

- BioMate workflow completion/failure notifications are represented as notification events with user preferences respected.

### C) Async task status contract

Source:

- `backend/lib/galaxy/webapps/galaxy/api/tasks.py`

Reuse intent:

1. Reuse `state/result` style for long-running backend tasks (e.g., notification dispatch, export, enrichment tasks).
2. Keep a consistent response contract for UI polling fallback.

Expected integration:

- background operations expose deterministic states and terminal outcome reasons.

## 16.2 galaxy_nextflow capabilities to leverage

### A) Nextflow run lifecycle and status transitions

Source:

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

Reuse intent:

1. Reuse run lifecycle fields (`running/succeeded/failed`) and execution metadata.
2. Reuse trace/log streaming behavior as evidence for run-stage transitions.
3. Reuse runtime artifact signal pattern for output-readiness hints.

Expected integration:

- normalized BioMate run states map directly from nextflow executor state and trace-derived evidence.

### B) QC/trace monitoring callback pattern

Source:

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` (QC monitor + callback)

Reuse intent:

1. Reuse callback/event emission pattern for stage/blocker transitions.
2. Convert monitor outcomes to typed blocker categories and suggested actions.

Expected integration:

- run stream includes explicit transition reasons rather than ambiguous progress-only updates.

### C) AutoFix toolkit for actionable recovery

Source:

- `galaxy_nextflow/lib/galaxy/ai/workflow_ops/autofix/toolkit.py`

Reuse intent:

1. Reuse concrete fix primitives (inspect input, generate fix, upload fix).
2. Map fix actions into UI “Resolve” CTAs for blocked runs.

Expected integration:

- “Needs Attention” actions are operational and reproducible, not generic text suggestions.

### D) Engine & Satellites workflow decomposition

Source:

- `galaxy_nextflow/tools/nextflow_native/workflow_generator.py`
- `galaxy_nextflow/workflows/README.md`

Reuse intent:

1. Reuse architecture idea: engine execution + satellite result extraction.
2. Surface stage-level progress in UI as parallel tracks.

Expected integration:

- one run can expose multiple meaningful stage tracks without losing global run coherence.

---

## 17) Work Breakdown with Owners, Dependencies, and Done Criteria

## Track A — Runtime/State Contract Team

Scope:

1. canonical run-state envelope
2. blocker typing and transition reason model
3. invocation/nextflow mapping adapter

Dependencies:

- Galaxy invocation services
- nextflow executor status fields

Complete when:

1. all run APIs return normalized state envelope
2. state transitions are deterministic and auditable
3. mapping tests cover success/failure/blocked/degraded paths

Test criteria:

1. unit tests for mapper with representative invocation payloads
2. integration tests verifying transition order
3. no mismatch between invocation terminal state and normalized terminal state

## Track B — Notification Platform Team

Scope:

1. persistent workflow notification queue/state
2. registration helper used by all run start paths
3. retry/idempotent delivery and metrics
4. user preference persistence for completion/error email

Dependencies:

- email service configuration
- workflow completion/error events

Complete when:

1. every authenticated invocation is registered for notification
2. completion/failure leads to one terminal notification record
3. retries handle transient SMTP failures
4. preferences are persisted and respected

Test criteria:

1. unit tests for idempotency and retry policy
2. integration tests for complete and failed workflow email paths
3. failure-injection tests (SMTP unavailable, timeout)
4. telemetry confirms sent/failed/retried counters

## Track C — Frontend UX Team

Scope:

1. Run Manager needs-attention and CTA upgrades
2. run detail blocker card and timeline
3. notification settings and delivery status UI

Dependencies:

- Track A schema
- Track B notification state endpoints

Complete when:

1. user can prioritize >3 concurrent runs from one panel
2. each non-healthy run shows reason + next action
3. notification toggles and statuses are visible and clear

Test criteria:

1. component tests for state rendering and CTA behavior
2. interaction tests for scope/filter/sort persistence
3. accessibility checks for key controls and alerts

## Track D — QA/E2E Team

Scope:

1. full-system real E2E validation
2. multi-run, timeout degradation, notification delivery validation
3. artifact evidence packaging for release/demo

Dependencies:

- Tracks A/B/C merged in staging

Complete when:

1. required E2E suites pass in stable repeated runs
2. no P1/P2 regression remains for run tracking or notification behavior
3. PM acceptance checklist passes

Test criteria:

1. `frontend/e2e/drug-development-ux-comprehensive.e2e.ts`
2. `frontend/e2e/drug-development-professional-quality.e2e.ts`
3. `frontend/e2e/multi-run-manager-priority.e2e.ts` (new)
4. `frontend/e2e/search-timeout-degraded-mode.e2e.ts` (new)
5. `frontend/e2e/workflow-email-notification.e2e.ts` (new)

## Track E — PM/Release Team

Scope:

1. milestone readiness reviews
2. release decision and stakeholder communication
3. demo scenario ownership

Dependencies:

- Track D pass matrix

Complete when:

1. sign-off on Definition of Done
2. shareable release pack is complete

Test criteria:

1. PM manual checklist green
2. stakeholder walkthrough passes without manual engineering intervention

---

## 18) Global Completion Criteria (Program-Level)

This initiative is complete only if all criteria below are true:

1. **Run clarity**
   - every active run has unambiguous state, stage, health, and next action.
2. **Parallel operations**
   - users can manage 3+ concurrent runs across sessions/projects from Run Manager.
3. **Timeout transparency**
   - search timeout/degraded mode is explicitly surfaced with recovery guidance.
4. **Notification reliability**
   - completion/failure notifications are delivered with retry and user preference respect.
5. **Reuse compliance**
   - implementation reuses mapped Galaxy/galaxy_nextflow capabilities before introducing net-new behavior.
6. **Quality gates**
   - real E2E suites pass and PM acceptance criteria are satisfied.

---

## 19) Test Matrix (Release Gate)

Release requires passing all mandatory checks:

### Automated

1. Existing mandatory:
   - `frontend/e2e/drug-development-ux-comprehensive.e2e.ts`
   - `frontend/e2e/drug-development-professional-quality.e2e.ts`
2. New mandatory:
   - `frontend/e2e/multi-run-manager-priority.e2e.ts`
   - `frontend/e2e/search-timeout-degraded-mode.e2e.ts`
   - `frontend/e2e/workflow-email-notification.e2e.ts`

### Manual PM

1. Start and monitor multiple runs across different chats/projects.
2. Resolve one blocked run through CTA and verify deterministic recovery.
3. Confirm completion email received for successful run.
4. Confirm failure email received for failed run.
5. Confirm notification preference toggles are respected.

### Observability checks

1. transition telemetry volume and ordering healthy
2. degraded-mode frequency within expected bounds
3. email delivery success/retry/failure metrics available

---

## 20) One-Page Execution Summary (Share-Ready)

| Track | Owner | Core Deliverable | Done Gate | Test Gate | Target Week |
|---|---|---|---|---|---|
| A — Runtime/State | Backend runtime/state team | Canonical run-state envelope + blocker typing + transition semantics | All run APIs emit normalized state/stage/health/blocker; deterministic transition reasons available | Mapper unit tests + invocation integration tests + transition order checks | W1–W2 |
| B — Notification Platform | Backend notification team | Persistent workflow completion/failure email pipeline with preferences + retries | Every authenticated invocation registered; exactly-once terminal notification record; retries operational | Notification unit/integration tests + SMTP failure injection + telemetry counters | W2–W3 |
| C — Frontend UX | Frontend team | Run Manager upgrades + run detail blocker/action drawer + notification settings/status | Users can prioritize 3+ concurrent runs and resolve blocked runs via explicit CTA | Component/integration tests + a11y checks + PM scripted UI pass | W2–W4 |
| D — QA/E2E | QA automation team | Full release gate suites + evidence package | Mandatory suites stable across repeated runs; no open P1/P2 regressions | Existing + new E2E suites, including multi-run, degraded mode, email notifications | W3–W4 |
| E — PM/Release | PM + release manager | Stakeholder-ready release and demo package | Sign-off on Definition of Done; release communication package published | PM manual checklist + stakeholder walkthrough + go/no-go review | W4 |

### 20.1 Milestone Timeline

1. **M1 (end W2):** state contract and transition semantics complete (Track A).  
2. **M2 (mid W3):** notification reliability and preference wiring complete (Track B).  
3. **M3 (end W3):** primary UX upgrades for multi-run operations complete (Track C).  
4. **M4 (end W4):** full E2E validation and release evidence complete (Track D).  
5. **M5 (end W4):** PM release sign-off and stakeholder demo-ready package complete (Track E).

### 20.2 RACI Snapshot

| Work Item | Responsible | Accountable | Consulted | Informed |
|---|---|---|---|---|
| Run-state contract | Track A | Backend lead | Track C, Track D | PM |
| Notification pipeline | Track B | Backend lead | Track C, Track D | PM |
| Run Manager UX | Track C | Frontend lead | Track A, PM | Track D |
| E2E release gate | Track D | QA lead | Track A, Track B, Track C | PM |
| Demo readiness | Track E | PM | QA lead, Eng leads | Stakeholders |

### 20.3 Weekly Reporting Template (for team sync)

Each track reports:

1. **Done this week** (completed deliverables)  
2. **Blocked** (dependency and risk)  
3. **Next week commitment** (explicit done gate target)  
4. **Quality signal** (test pass % / regression count / telemetry status)


