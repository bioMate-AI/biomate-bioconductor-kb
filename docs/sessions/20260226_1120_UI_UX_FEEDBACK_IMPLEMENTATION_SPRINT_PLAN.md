# 20260226_1120 UI/UX Feedback Implementation Sprint Plan (BioMate)

## Goal
Implement production-grade UX feedback and telemetry so user experience is measurable, debuggable, and continuously improvable.

## Scope
- Frontend feedback widgets
- Backend feedback ingestion APIs
- Event instrumentation
- Storage schema
- Dashboards and triage workflow
- Rollout and quality gates

---

## Sprint Structure (2 Sprints)

## Sprint A (Critical Foundation, 1 week)
- Ship feedback capture and telemetry backbone.
- Make all key UX interactions observable with run/session correlation IDs.

## Sprint B (Optimization and Operations, 1 week)
- Add dashboards, alerting, and triage loops.
- Improve UX quality loops with prioritization and experiment support.

---

## Workstream 1: Frontend Feedback UI

## Ticket FE-01: Inline thumbs feedback on assistant/workflow cards
- Component: `FeedbackInlineWidget`
- Placement:
  - assistant message footer
  - workflow card footer
- Behavior:
  - thumbs up: one click submit
  - thumbs down: reason tags required + optional comment
- Payload fields:
  - `sessionId`, `messageId`, `runId`, `workflowId`, `rating`, `reasonTags`, `comment`

Acceptance:
- Widget appears on targeted surfaces.
- Feedback persists and success/failure toast is shown.

## Ticket FE-02: Post-run micro survey modal
- Trigger:
  - run terminal states (`completed`, `failed`, `cancelled`)
- Questions:
  - status clarity (1-5)
  - output usefulness (1-5)
  - output actionability (1-5)
  - optional comment

Acceptance:
- Modal appears once per run.
- "Dismiss" and "submit" both tracked.

## Ticket FE-03: Contextual "Report confusion"
- Placement:
  - execution panel
  - output panel
- One-click capture with optional comment.
- Auto attach context:
  - `runId`, `workflowId`, `executionStatus`, `errorMessage`, `timestamp`, `uiRoute`

Acceptance:
- Context payload is auto-filled and visible in preview.

## Ticket FE-04: Download outcome check
- Trigger:
  - after `Download` / `Download All`
- Ask:
  - "Did you receive what you expected?"
  - if no: reason tags + comment

Acceptance:
- Prompt is non-blocking and dismissible.

---

## Workstream 2: Backend Feedback APIs

## Ticket BE-01: Feedback ingestion endpoint
- Route: `POST /api/feedback`
- Validate payload schema per feedback type.
- Rate limit per session/user.
- Store normalized records in DB.

Acceptance:
- 200 on valid payload.
- 4xx on validation failures with actionable messages.

## Ticket BE-02: Feedback query endpoints
- `GET /api/feedback/summary` (aggregated metrics)
- `GET /api/feedback/issues` (high-friction slices)
- Filters:
  - date range
  - feedback type
  - workflow family
  - run status

Acceptance:
- Supports dashboard use cases without client-side heavy aggregation.

## Ticket BE-03: Correlation enrichment middleware
- Enrich feedback records with:
  - resolved user/session metadata
  - inferred workflow/run relationships where missing
  - client version/build

Acceptance:
- Records are queryable by `runId`, `sessionId`, and time.

---

## Workstream 3: Telemetry/Event Instrumentation

## Ticket OBS-01: Core UX event schema
- Standardize event shape:
  - `eventName`
  - `ts`
  - `sessionId`
  - `runId` (nullable)
  - `workflowId` (nullable)
  - `properties` (json)

Acceptance:
- Shared type definitions in frontend+backend.

## Ticket OBS-02: Instrument key funnel events
- Required events:
  - `chat.prompt_submitted`
  - `workflow.generated`
  - `workflow.run_clicked`
  - `workflow.status_changed`
  - `workflow.error_shown`
  - `output.panel_opened`
  - `output.visualization_opened`
  - `output.download_clicked`
  - `feedback.submitted`

Acceptance:
- >95% events contain `sessionId`.
- >90% run-bound events contain `runId`.

---

## Workstream 4: Storage and Analytics

## Ticket DATA-01: Feedback DB tables
- `ux_feedback`
- `ux_feedback_reason_tags` (or json array per DB style)
- indexes on:
  - `created_at`
  - `run_id`
  - `session_id`
  - `feedback_type`

Acceptance:
- Query latency acceptable for dashboard windows.

## Ticket DATA-02: Derived metrics jobs
- Nightly aggregates:
  - completion rates
  - error recovery success
  - output actionability pass
  - top confusion tags

Acceptance:
- Summary endpoint reads pre-aggregated tables/views.

---

## Workstream 5: Dashboard and Triage

## Ticket OPS-01: UX health dashboard
- Panels:
  - prompt -> run -> output funnel
  - visualization/download success rates
  - top confusion reasons
  - failed run feedback hotspots

Acceptance:
- Dashboard refreshes daily and supports drill-down.

## Ticket OPS-02: Weekly triage ritual
- Process:
  - review critical/high feedback clusters
  - assign owner and target release
  - close loop with before/after metrics

Acceptance:
- Triage template and owner rotation documented.

---

## Definition of Done Per Sprint

## Sprint A DoD
- Feedback UI shipped in core surfaces.
- Feedback API and storage live.
- Core telemetry events live with correlation IDs.
- Basic feedback summary endpoint operational.

## Sprint B DoD
- UX dashboard and filters available.
- Weekly triage running.
- Release gate uses UX metrics.
- At least one UX issue closed with measurable improvement.

---

## Release Gates (Must Pass)
- Critical UX issues open: 0
- Output actionability (visualize + download): >= 95%
- Post-error recovery success: >= 70% (initial target)
- Feedback submission failure rate: < 2%
- Event schema completeness: >= 95%

---

## Risk Register and Mitigation
- **Risk:** Feedback fatigue
  - Mitigation: throttle prompts, contextual triggers only.
- **Risk:** Noisy low-quality feedback
  - Mitigation: reason tags + structured context.
- **Risk:** Missing correlation IDs
  - Mitigation: middleware fallback + schema validation.
- **Risk:** Privacy concerns
  - Mitigation: explicit consent text, avoid sensitive content storage by default.

---

## Suggested Rollout
1. Internal dogfood (2-3 days)
2. 10% traffic rollout with monitoring
3. 50% rollout after error budget check
4. 100% rollout with weekly review cadence

---

## Immediate Next Build Order
1. FE-01, BE-01, OBS-01 (foundation)
2. FE-02, OBS-02, DATA-01
3. FE-03, FE-04, BE-02
4. DATA-02, OPS-01, OPS-02

