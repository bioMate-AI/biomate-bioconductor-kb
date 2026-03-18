# UX Walkthrough Remaining Work: Detailed Definition + Exact Resolution Plan (2026-03-01 10:01)

## Scope and Standard
- This document maps open UX walkthrough items to implementation-grade work plans.
- Source UX docs reviewed:
  - `UX_REVIEW_REPORT.md`
  - `UX_REVIEW_EXECUTIVE_SUMMARY.md`
  - `UX_REVIEW_README.md`
- Detail standard used per item:
  1. Product definition (what the item means),
  2. Current evidence in code/behavior,
  3. Root cause,
  4. Exact code changes (file-level),
  5. Acceptance tests (exact expected behavior),
  6. Telemetry and success metrics,
  7. Risk and rollback.

---

## Parallel Feedback Work (already executed while auditing UX)
- Strict release gate run (parallel stream) completed:
  - `FEEDBACK_MATRIX_MODE=release STRICT_NO_SKIP_CRITICAL=true BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix`
  - Result: **SUCCESS**
  - Critical suites: `feedback-real-ui-strict.e2e.ts`, `pm-user-stories-comprehensive.e2e.ts`
- Framework hardening completed:
  - `frontend/scripts/run-feedback-e2e-matrix.sh` supports `FEEDBACK_MATRIX_MODE` and `STRICT_NO_SKIP_CRITICAL`
  - `.github/workflows/feedback-e2e-matrix.yml` now runs release mode with strict no-SKIP policy

---

## Item 1 — First-Time Onboarding Tour

### Definition
- A first-run guided flow that explains:
  1) what BioMate does,
  2) how to submit a request,
  3) how run/feedback/results work,
  4) how to re-open help later.

### Current Evidence
- No dedicated tour component found in `frontend/client/src`.
- No first-run persisted onboarding state key currently used.

### Root Cause
- Product evolved feature-first; onboarding layer was never added.

### Exact Resolution
- Add `frontend/client/src/components/onboarding-tour.tsx`.
- Add storage helper in `frontend/client/src/lib/onboarding.ts`:
  - `hasSeenOnboarding()`, `markOnboardingSeen()`, `resetOnboarding()`.
- Wire in `frontend/client/src/App.tsx`:
  - show on first load only,
  - add “Take tour again” action in header/settings.

### Acceptance Tests
- First visit shows onboarding.
- Skip hides onboarding and persists dismissal.
- Reload does not re-show unless “Take tour again” is clicked.

### Metrics
- `onboarding.shown`, `onboarding.completed`, `onboarding.skipped`.

### Risk / Rollback
- Low risk (UI-only).
- Rollback: hide feature behind `VITE_ENABLE_ONBOARDING=false`.

---

## Item 2 — Execution Prerequisites Checklist

### Definition
- A user-visible checklist adjacent to run controls that explicitly states what is missing before execution.
- Should distinguish:
  - required input data,
  - required parameters,
  - tool/runtime readiness,
  - confidence-policy gates.

### Current Evidence
- Confidence run blocking exists (`Run Workflow` disabled under blocked conditions).
- Missing an explicit checklist view (“What do I need?”) with itemized reasons.

### Root Cause
- Gate logic exists but explanation layer is summarized into single reason text.

### Exact Resolution
- Extend `frontend/client/src/components/nextflow-workflow-viewer.tsx`:
  - add checklist panel with structured statuses.
- Pass normalized prerequisites from `frontend/client/src/components/chat-message.tsx`:
  - consume `message.metadata.prerequisitesValidation`,
  - merge with confidence signals.
- Add `frontend/client/src/lib/prereq-normalizer.ts` for deterministic checklist construction.

### Acceptance Tests
- If inputs missing: checklist shows explicit missing item; run disabled.
- If all required items met: checklist green; run enabled.
- If low-confidence block: checklist shows policy warning + explicit override action.

### Metrics
- `workflow.prereq_checklist_shown`
- `workflow.prereq_missing_item_clicked`
- `workflow.prereq_resolved_before_run`

### Risk / Rollback
- Medium risk (touches execution UX path).
- Rollback: keep old single-message blocking while hiding checklist.

---

## Item 3 — Session Save Transparency

### Definition
- User always sees save-state semantics:
  - “Auto-saved”
  - “Saving…”
  - “Last saved X sec/min ago”
  - optional unsaved-change warning before unload.

### Current Evidence
- Session data updates occur in `chatHistoryService` paths.
- No persistent visible save state in top-level UX.

### Root Cause
- Persistence exists but status signaling is implicit.

### Exact Resolution
- Add `useSaveStatus` hook in `frontend/client/src/hooks/use-save-status.ts`.
- Integrate in `frontend/client/src/components/chat-with-artifacts.tsx` header bar.
- Emit last-save timestamp on message/workflow/session update paths.
- Optional unload guard when save in-flight.

### Acceptance Tests
- Sending message updates status to saving -> auto-saved.
- Running workflow updates save timestamp.
- Last-saved text updates over time.

### Metrics
- `session.save_status_rendered`
- `session.save_latency_ms`

### Risk / Rollback
- Low-medium risk (state synchronization).
- Rollback: disable indicator while keeping persistence unchanged.

---

## Item 4 — Offline / Disconnection UX

### Definition
- Explicit disconnected state and recovery guidance in UI.
- Users should not confuse backend/API outage with product freeze.

### Current Evidence
- “Live” badge appears on connected path.
- No explicit offline banner + recovery copy in primary chat surface.

### Root Cause
- Positive-state indicator exists; negative-state and transition UX incomplete.

### Exact Resolution
- Add `frontend/client/src/lib/network-status.ts` with online/offline listeners.
- Show banner in `frontend/client/src/components/chat-with-artifacts.tsx` when offline.
- Add actionable copy in `chat-interface` error path:
  - retry hint,
  - preserve drafted text,
  - clear reconnect message when online returns.

### Acceptance Tests
- Simulated network failure shows offline banner.
- Banner clears on reconnect.
- User sees explicit retry guidance.

### Metrics
- `network.offline_banner_shown`
- `network.reconnect_recovered`

### Risk / Rollback
- Low risk.
- Rollback: suppress banner while keeping existing error handling.

---

## Item 5 — Suggestion Button Intent Clarity

### Definition
- Suggestion chips must clearly be understood as shortcuts (not hidden modes).

### Current Evidence
- Suggestion chips are rendered but no explicit explanatory tooltip/label.

### Root Cause
- Feature existed before UX copy polish.

### Exact Resolution
- Update `frontend/client/src/components/chat-message.tsx` suggestion block:
  - add small label (“Suggested actions”),
  - add tooltip (“Quick action — same as typing this prompt”).

### Acceptance Tests
- Label visible above suggestion chips.
- Tooltip appears on hover/focus for each chip.

### Metrics
- `suggestion.tooltip_seen`
- `suggestion.clicked`

### Risk / Rollback
- Very low risk.
- Rollback: remove tooltip only.

---

## Item 6 — Navigation Context Clarity

### Definition
- User should see where they are (chat, session context) and what adjacent areas exist.

### Current Evidence
- Sidebar and quick actions exist.
- Explicit location indicator/breadcrumb semantics are limited.

### Root Cause
- Navigation IA expanded incrementally without explicit contextual cue layer.

### Exact Resolution
- Add compact context line in header:
  - “Chat / <session-title>”.
- Highlight active section consistently in sidebar.
- Avoid heavy navigation redesign in this phase.

### Acceptance Tests
- Current section visible and consistent across route/session changes.

### Metrics
- `nav.context_rendered`

### Risk / Rollback
- Low risk.

---

## Item 7 — Upload UX Consistency

### Definition
- Upload limits/format policy must be consistent across all upload entry points.

### Current Evidence
- `file-upload.tsx` advertises and enforces large-file policy (5GB local + URL import path).
- `chat-input.tsx` popover still states “Max 500MB per file”.
- This mismatch causes user confusion and support risk.

### Root Cause
- Duplicate hardcoded policy text in multiple components.

### Exact Resolution
- Add shared constants:
  - `frontend/client/src/lib/upload-policy.ts`.
- Replace duplicated text/limits in:
  - `frontend/client/src/components/file-upload.tsx`
  - `frontend/client/src/components/chat-input.tsx`
- Ensure chat quick-upload either:
  - enforces same limit as policy, or
  - explicitly states it is a “quick upload limit” and links to full uploader for large files.

### Acceptance Tests
- Policy text is consistent in both upload surfaces.
- Oversized file behavior/error text matches documented limit.

### Metrics
- `upload.limit_error_shown`
- `upload.path_selected` (`quick` vs `full`)

### Risk / Rollback
- Medium risk (user-visible policy change).

---

## Item 8 — API Responsiveness Expectation / Timeout UX

### Definition
- Users should understand expected wait windows and get explicit timeout recovery options.

### Current Evidence
- Pending cue exists.
- Timeout/failure copy exists, but policy-level user expectation messaging is not standardized.

### Root Cause
- Iterative fixes added cues; no unified latency expectation + escalation framework.

### Exact Resolution
- Standardize async guidance text in shared utility:
  - `frontend/client/src/lib/async-guidance.ts`.
- Use in:
  - `chat-interface` pending and error states,
  - execution error panel in `chat-with-artifacts`.
- Add explicit “Try again” and “Report issue” affordances in timeout states.

### Acceptance Tests
- Delayed response shows expectation cue.
- Timeout shows actionable recovery copy and escalation option.

### Metrics
- `async.timeout_ui_shown`
- `async.retry_clicked`
- `async.report_issue_clicked`

### Risk / Rollback
- Low risk.

---

## Delivery Plan (Implementation Order)

### Batch P1 (highest impact, next)
1. Prerequisites checklist,
2. Session save transparency,
3. Offline/disconnection UX.

### Batch P2
4. Onboarding tour,
5. Suggestion clarity,
6. Upload consistency.

### Batch P3
7. Navigation context polish,
8. Async expectation standardization.

---

## Verification Gate for Completion
- Required local command:
  - `FEEDBACK_MATRIX_MODE=release STRICT_NO_SKIP_CRITICAL=true BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix`
- Required reporting:
  - timestamped implementation report,
  - timestamped acceptance report with matrix artifacts path.

---

## Engineering Contracts (Per Item)

## Item 1 Contract — Onboarding Tour

### Component/API Contract
- New component: `OnboardingTour`
  - Props:
    - `open: boolean`
    - `onOpenChange(open: boolean): void`
    - `onComplete(): void`
    - `onSkip(): void`
  - Test IDs:
    - `onboarding-tour-dialog`
    - `onboarding-tour-step-1` ... `onboarding-tour-step-n`
    - `button-onboarding-next`
    - `button-onboarding-skip`
    - `button-onboarding-finish`
- Storage helper: `lib/onboarding.ts`
  - `hasSeenOnboarding(): boolean`
  - `markOnboardingSeen(meta?: { completed: boolean }): void`
  - `resetOnboarding(): void`
  - storage key: `biomate.onboarding.v1`

### State Model
- `not_seen` -> `shown` -> (`skipped` | `completed`)
- Re-entry path: settings/header action forces `shown`.

### Exact Assertions
- First app load with no key: dialog visible.
- Skip writes `{completed:false}` and closes.
- Finish writes `{completed:true}` and closes.
- Reload: dialog hidden if key exists.

---

## Item 2 Contract — Prerequisites Checklist

### Data Normalization Contract
- New normalizer output type:
```ts
type PrereqStatus = "ok" | "missing" | "warning" | "blocked";
interface PrereqItem {
  id: string;                // e.g. input_data, required_params, tool_runtime, confidence_gate
  label: string;
  status: PrereqStatus;
  reason?: string;
  actionHint?: string;       // e.g. "Upload FASTQ files", "Set threads > 0"
}
interface PrereqChecklist {
  items: PrereqItem[];
  canRun: boolean;           // computed from hard blockers
  overrideAllowed: boolean;  // true only for policy-approved low-confidence override
}
```

### Component Contract
- `NextflowWorkflowViewer` new prop:
  - `prereqChecklist?: PrereqChecklist`
- Test IDs:
  - `workflow-prereq-checklist`
  - `workflow-prereq-item-<id>`
  - `workflow-prereq-missing-count`
  - `button-show-prereq-details`

### State Rules
- `canRun=false` when any `status in ["missing","blocked"]` unless override policy applies.
- If `overrideAllowed=true`, show `button-confirm-low-confidence-run` and keep normal run disabled.

### Exact Assertions
- Missing input case: checklist has `input_data=missing`, run disabled.
- Valid case: all critical items `ok`, run enabled.
- Policy block: `confidence_gate=blocked`, override button visible, telemetry fired on override.

---

## Item 3 Contract — Session Save Transparency

### Hook Contract
- `useSaveStatus(sessionId?: string)`
  - Returns:
    - `status: "idle" | "saving" | "saved" | "error"`
    - `lastSavedAt?: Date`
    - `markSaving(): void`
    - `markSaved(): void`
    - `markError(err: string): void`

### UI Contract
- Header status test IDs:
  - `session-save-status-chip`
  - `session-last-saved-text`
  - `session-save-error`

### Timing Rules
- Transition to `saving` within 100ms after message/workflow/session mutation starts.
- Transition to `saved` on successful persistence.
- `lastSavedAt` updates every successful save.

### Exact Assertions
- Send message -> chip goes `saving` then `saved`.
- Execute workflow -> timestamp updates.
- Simulated save failure -> `error` state visible.

---

## Item 4 Contract — Offline / Disconnection UX

### Network Store Contract
- `lib/network-status.ts`
  - `subscribe(listener)`
  - `getStatus(): "online" | "offline"`
  - emits on `window.online/window.offline`

### UI Contract
- Banner test IDs:
  - `offline-banner`
  - `offline-retry-guidance`
  - `offline-queue-note` (optional if queuing is introduced)

### Behavior Rules
- Offline banner appears immediately on transition to offline.
- `Send` and run actions either:
  - disabled with reason, or
  - allowed but with explicit queued/retry semantics.
- Banner cleared within one render cycle after reconnect.

### Exact Assertions
- Force network error -> banner visible with recovery text.
- Reconnect -> banner hidden.

---

## Item 5 Contract — Suggestion Clarity

### UI Contract
- Add label above chips: `Suggested actions`.
- Tooltip content: `Quick action — same as typing this prompt.`
- Test IDs:
  - `suggested-actions-label`
  - `suggestion-chip-<index>`

### Exact Assertions
- Label visible on assistant messages with suggestions.
- Tooltip appears on hover/focus.
- Clicking chip still triggers existing send behavior.

---

## Item 6 Contract — Navigation Context

### UI Contract
- Header breadcrumb/context text:
  - format: `Chat / <sessionName|sessionId>`
- Test ID:
  - `nav-context-label`

### Exact Assertions
- New chat/session updates context text.
- Switching recent chat updates context.

---

## Item 7 Contract — Upload Consistency

### Shared Policy Contract
- `lib/upload-policy.ts`
  - `UPLOAD_ACCEPTED_TYPES`
  - `UPLOAD_MAX_LOCAL_BYTES`
  - `UPLOAD_MAX_LOCAL_LABEL` (UI string)
  - `UPLOAD_HELP_TEXT_SHORT`
  - `UPLOAD_HELP_TEXT_FULL`

### Rules
- Chat quick-upload and full uploader must reference same constants.
- If quick-upload limit differs by design, text must explicitly say `Quick-upload limit`.

### Exact Assertions
- Chat popover and full uploader show consistent max-size policy wording.
- Oversize rejection message matches policy constant.

---

## Item 8 Contract — Async Expectation / Timeout UX

### Messaging Contract
- `lib/async-guidance.ts`
  - `getPendingCopy(context)`
  - `getTimeoutCopy(context)`
  - `getRecoveryActions(context)`

### UI Contract
- Pending test ID: `chat-response-pending` (already used)
- Timeout/recovery test IDs:
  - `chat-timeout-guidance`
  - `button-chat-retry`
  - `button-chat-report-issue`

### Exact Assertions
- Long wait path shows pending expectations text.
- Timeout path shows retry/report actions.

---

## End-to-End Test Matrix Additions (Planned)

| Test ID | Purpose | File |
|---|---|---|
| `UX-ONBOARD-001` | first-run onboarding appears once | `frontend/e2e/ux-onboarding.e2e.ts` |
| `UX-PREREQ-001` | missing prereq blocks run + checklist itemized | `frontend/e2e/ux-prereq-checklist.e2e.ts` |
| `UX-SAVE-001` | save indicator transitions saving->saved | `frontend/e2e/ux-save-status.e2e.ts` |
| `UX-OFFLINE-001` | offline banner and recovery copy | `frontend/e2e/ux-offline-recovery.e2e.ts` |
| `UX-SUGGEST-001` | suggestion label + tooltip semantics | `frontend/e2e/ux-suggestion-clarity.e2e.ts` |
| `UX-UPLOAD-001` | upload policy consistency across entry points | `frontend/e2e/ux-upload-policy-consistency.e2e.ts` |

---

## Operational Rollout Plan

### Stage 0 — Feature flags default off (dev only)
- Introduce flags:
  - `VITE_ENABLE_ONBOARDING`
  - `VITE_ENABLE_PREREQ_CHECKLIST`
  - `VITE_ENABLE_SAVE_STATUS`
  - `VITE_ENABLE_OFFLINE_BANNER`

### Stage 1 — Canary enable (internal)
- Enable for local/internal users.
- Monitor telemetry for regressions and user drop-offs.

### Stage 2 — Full enable
- Remove flags for stable items after 1–2 successful matrix cycles.

---

## Traceability Checklist (Definition of Done)
- [ ] Spec implemented in code for item.
- [ ] Unit tests added/updated.
- [ ] Dedicated E2E(s) passing.
- [ ] Included in release matrix policy when critical.
- [ ] Telemetry events verified in logs.
- [ ] Timestamped report added with artifact paths.

---

## Fundamental-Function Priority Model (Scored)

### Scoring dimensions (1-5 each)
- **Core Operability Impact**: does failure break primary workflow execution?
- **Data Integrity / Trust Impact**: can user lose work or make invalid assumptions?
- **Failure Containment Value**: does this reduce cascading failures/support burden?
- **Implementation Leverage**: does this unblock multiple downstream items?

### Priority table
| Item | Operability | Integrity | Containment | Leverage | Total | Tier |
|---|---:|---:|---:|---:|---:|---|
| Execution prerequisites checklist | 5 | 5 | 5 | 5 | 20 | L0 |
| Offline/disconnection UX | 5 | 4 | 5 | 4 | 18 | L0 |
| Async expectation/timeout UX | 5 | 3 | 4 | 4 | 16 | L0 |
| Session save transparency | 3 | 5 | 4 | 3 | 15 | L1 |
| Upload UX consistency | 4 | 4 | 3 | 3 | 14 | L1 |
| First-time onboarding | 2 | 3 | 2 | 3 | 10 | L2 |
| Navigation context clarity | 2 | 2 | 2 | 2 | 8 | L2 |
| Suggestion intent clarity | 1 | 2 | 1 | 1 | 5 | L2 |

### Why this ordering is fundamental
- L0 items directly determine whether users can reliably submit, execute, and recover.
- L1 items determine whether users trust persistence and input correctness.
- L2 items optimize discoverability/usability after system function is stable.

---

## Exact Work Packages (Ticket-Level)

## WP-L0-1: Prerequisites Checklist (Execution Safety)

### Subtasks
1. Add `prereq-normalizer.ts` with deterministic mapping from `prerequisitesValidation` + gate signals.
2. Add checklist UI block in `nextflow-workflow-viewer.tsx` with explicit item rows and statuses.
3. Pass checklist payload from `chat-message.tsx`.
4. Add telemetry on checklist render and missing-item interaction.

### Exact acceptance criteria
- `workflow-prereq-checklist` appears for workflow cards.
- Missing inputs create at least one `workflow-prereq-item-input_data` with `missing`.
- `Run Workflow` disabled when checklist has hard blockers.
- Override path only shown when policy allows and not for missing hard prerequisites.

### Exact tests
- `UX-PREREQ-001`: missing input scenario.
- `UX-PREREQ-002`: fully satisfied scenario.
- `UX-PREREQ-003`: low-confidence override scenario.

---

## WP-L0-2: Offline/Disconnection UX (Reliability)

### Subtasks
1. Build `network-status.ts` store with online/offline events.
2. Render `offline-banner` in `chat-with-artifacts.tsx`.
3. Integrate retry guidance into `chat-interface.tsx` error path.
4. Preserve draft input state on failures.

### Exact acceptance criteria
- Browser offline event -> `offline-banner` visible within one render cycle.
- Reconnect event -> banner removed.
- Failed send path includes clear retry instruction and preserves draft.

### Exact tests
- `UX-OFFLINE-001`: offline banner appears.
- `UX-OFFLINE-002`: reconnect clears banner.
- `UX-OFFLINE-003`: draft preservation on send failure.

---

## WP-L0-3: Async/Timeout UX Standardization

### Subtasks
1. Add `async-guidance.ts` for unified pending/timeout copy.
2. Use pending guidance in `chat-interface` pending strip.
3. Use timeout guidance and actions in error-render blocks.
4. Add report/retry action instrumentation.

### Exact acceptance criteria
- Pending state shows expected wait guidance text.
- Timeout state shows actionable controls (`retry`, `report issue`).
- Guidance copy is consistent in chat and execution contexts.

### Exact tests
- `UX-ASYNC-001`: pending cue copy shown.
- `UX-ASYNC-002`: timeout copy + actions shown.

---

## WP-L1-1: Session Save Transparency

### Subtasks
1. Add `use-save-status.ts` hook.
2. Add `session-save-status-chip` in header.
3. Update save events from message/workflow update paths.
4. Add optional unload warning while save in-flight.

### Exact acceptance criteria
- save state transitions: saving -> saved.
- `session-last-saved-text` updates after each mutation.

---

## WP-L1-2: Upload Policy Consistency

### Subtasks
1. Add shared `upload-policy.ts`.
2. Replace hardcoded policy strings in `chat-input.tsx` and `file-upload.tsx`.
3. Align oversize error messages to shared constants.

### Exact acceptance criteria
- Same max-size policy wording across both upload entry points.
- Oversized file error copy matches shared constants.

---

## Operational Execution Order (Strict)
1. WP-L0-1
2. WP-L0-2
3. WP-L0-3
4. WP-L1-1
5. WP-L1-2
6. L2 polish items

No L2 implementation starts before L0 and L1 are passing in release gate.

---

## Verification Commands Per Wave

### Wave L0
- `FEEDBACK_MATRIX_MODE=release STRICT_NO_SKIP_CRITICAL=true BIOMATE_URL=http://localhost:5310 npm run e2e:feedback:matrix`
- plus targeted:
  - `npx playwright test e2e/ux-prereq-checklist.e2e.ts`
  - `npx playwright test e2e/ux-offline-recovery.e2e.ts`
  - `npx playwright test e2e/ux-async-guidance.e2e.ts`

### Wave L1
- release gate command above
- plus targeted:
  - `npx playwright test e2e/ux-save-status.e2e.ts`
  - `npx playwright test e2e/ux-upload-policy-consistency.e2e.ts`
