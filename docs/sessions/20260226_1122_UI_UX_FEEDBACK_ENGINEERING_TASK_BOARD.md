# 20260226_1122 UI/UX Feedback Engineering Task Board

## Purpose
Owner-ready execution board for implementing BioMate UX feedback + telemetry with clear dependencies, estimates, and delivery order.

## Capacity Assumption
- 1 frontend engineer
- 1 backend engineer
- 1 full-stack/support engineer
- 1 product/UX reviewer (part-time)

---

## Task Board (Execution Order)

## T01 - Shared Feedback Schema and Types
- **Owner:** Full-stack
- **Estimate:** 4h
- **Depends on:** none
- **Deliverables:**
  - shared feedback payload types
  - reason tag enum
  - validation contract
- **Done when:** frontend and backend compile against same schema.

## T02 - Backend `POST /api/feedback` Ingestion
- **Owner:** Backend
- **Estimate:** 8h
- **Depends on:** T01
- **Deliverables:**
  - endpoint implementation
  - schema validation
  - error handling
- **Done when:** valid payload writes to DB; invalid payload returns actionable 4xx.

## T03 - Feedback Storage Schema + Migration
- **Owner:** Backend
- **Estimate:** 6h
- **Depends on:** T01
- **Deliverables:**
  - `ux_feedback` table
  - indexes (`created_at`, `run_id`, `session_id`, `feedback_type`)
- **Done when:** migration applied and read/write tested.

## T04 - Inline Feedback Widget (Thumbs + Reasons)
- **Owner:** Frontend
- **Estimate:** 10h
- **Depends on:** T01, T02
- **Deliverables:**
  - widget on assistant messages and workflow cards
  - downvote reason tags + optional comment
- **Done when:** feedback submits and UI confirms success/failure.

## T05 - Post-Run Micro Survey
- **Owner:** Frontend
- **Estimate:** 8h
- **Depends on:** T01, T02
- **Deliverables:**
  - terminal-state trigger
  - 3-question modal
  - dismiss/submit handling
- **Done when:** survey shown once per run and submission stored.

## T06 - Contextual "Report Confusion"
- **Owner:** Frontend
- **Estimate:** 6h
- **Depends on:** T01, T02
- **Deliverables:**
  - button near execution/output surfaces
  - auto-included context payload
- **Done when:** report includes run/session/status metadata.

## T07 - Download Outcome Prompt
- **Owner:** Frontend
- **Estimate:** 5h
- **Depends on:** T01, T02
- **Deliverables:**
  - non-blocking post-download check
  - yes/no + reason capture
- **Done when:** submission linked to run/session where available.

## T08 - Core UX Event Instrumentation
- **Owner:** Full-stack
- **Estimate:** 10h
- **Depends on:** T01
- **Deliverables:**
  - standardized event envelope
  - event emitters for key funnel points
- **Done when:** events are emitted with required IDs.

## T09 - Event Completeness Guardrails
- **Owner:** Backend
- **Estimate:** 4h
- **Depends on:** T08
- **Deliverables:**
  - server-side enrichment for missing IDs
  - warnings for low-quality events
- **Done when:** completeness threshold report available.

## T10 - Feedback Summary APIs
- **Owner:** Backend
- **Estimate:** 8h
- **Depends on:** T03
- **Deliverables:**
  - `GET /api/feedback/summary`
  - `GET /api/feedback/issues`
  - basic filtering
- **Done when:** dashboard clients can consume aggregates without heavy client compute.

## T11 - UX Health Dashboard (v1)
- **Owner:** Full-stack
- **Estimate:** 12h
- **Depends on:** T10, T08
- **Deliverables:**
  - funnel panel
  - output actionability panel
  - top reason tags panel
- **Done when:** team can triage weekly with real data.

## T12 - End-to-End Validation Tests
- **Owner:** Frontend
- **Estimate:** 8h
- **Depends on:** T04, T05, T06, T07
- **Deliverables:**
  - tests for feedback UI rendering
  - tests for submission payload correctness
- **Done when:** CI passes for all feedback flows.

## T13 - Privacy and Data Retention Controls
- **Owner:** Backend
- **Estimate:** 6h
- **Depends on:** T03
- **Deliverables:**
  - retention policy config
  - optional anonymization pipeline for comments
- **Done when:** policy documented and enforceable.

## T14 - Rollout Flags + Gradual Release
- **Owner:** Full-stack
- **Estimate:** 5h
- **Depends on:** T04, T05, T06, T07, T10
- **Deliverables:**
  - feature flags for feedback modules
  - staged rollout config (10% -> 50% -> 100%)
- **Done when:** safe rollback and progressive release are possible.

## T15 - Operations Ritual and Triage Template
- **Owner:** Product/UX + Engineering Lead
- **Estimate:** 3h
- **Depends on:** T11
- **Deliverables:**
  - weekly triage template
  - severity and assignment protocol
- **Done when:** recurring triage cadence is adopted.

---

## Critical Path
T01 -> (T02 + T03) -> (T04 + T05 + T06 + T07) -> T12 -> T14  
Parallel: T08 -> T09; T03 -> T10 -> T11 -> T15

---

## Effort Summary
- Frontend-heavy tasks: 37h
- Backend-heavy tasks: 32h
- Full-stack/shared tasks: 31h
- Product/UX ops tasks: 3h
- **Total:** ~103h engineering + ops

Approx timeline:
- With 2 engineers: ~2.5-3 weeks
- With 3 engineers: ~1.5-2 weeks

---

## Risk and Blockers Checklist
- Shared schema drift between FE/BE
- Missing run/session correlation in certain UI states
- Feedback fatigue from over-prompting
- Dashboard lag from unindexed queries
- Lack of clear owners for weekly triage

Mitigation:
- Lock T01 first and gate all subsequent tasks on it.
- Add ID enrichment fallback in T09.
- Prompt throttling and context-triggered collection only.
- Ensure indexes in T03 before dashboard rollout.

---

## Release Acceptance Criteria
- Feedback submission success >= 98%
- Event completeness >= 95% with correlation IDs
- Output actionability metric measurable end-to-end
- No critical UX blockers in triage queue
- Rollout flags validated with rollback test

