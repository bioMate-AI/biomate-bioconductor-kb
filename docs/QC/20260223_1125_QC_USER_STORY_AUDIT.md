# QC Gate & Test Harness — User Story Implementation Audit
**Date**: 2026-02-23 11:25
**Audited by**: Code analysis of frontend + backend (25 user stories)
**Result**: 2 fully implemented · 12 partial · 11 not implemented

---

## How to Read This Document

Each user story is rated:
- **IMPLEMENTED** — feature exists and matches the story
- **PARTIAL** — infrastructure exists but UX details or behaviour are incomplete
- **NOT IMPLEMENTED** — no code exists for this story

Key files audited:
- `frontend/client/src/components/workflow-artifact.tsx` — main workflow UI, SSE listener, QC gate modal trigger
- `frontend/client/src/components/qc-gate-modal.tsx` — the modal the researcher sees on a QC failure
- `frontend/client/src/components/pilot-run-panel.tsx` — pilot run control panel
- `frontend/client/src/components/phase-card.tsx` — phase status card component
- `backend/lib/galaxy/jobs/qc_trace_monitor.py` — SSE event emission, metric parsing, failure messages
- `backend/lib/galaxy/jobs/parameter_suggester.py` — domain-specific suggestion generation

---

## Epic 1 — Understanding the Pilot Run

### US-1.1 First-time pilot banner
**PARTIAL**

| | |
|---|---|
| **What exists** | Banner renders in `workflow-artifact.tsx` (lines 721–762); shows `pilotMessage` prop and iterates `pilotReasons[]` with icons; "Skip pilot" button present; pilot fraction shown as percentage and count |
| **What's missing** | `pilotMessage` defaults to `"We suggest running a pilot test before full execution"` — generic, not domain-specific. Units are always `"samples"` not `"micrographs"` / `"reads"` / `"cells"`. No estimated time saving shown. No description of what happens if you skip. |
| **Gap** | Copy and domain context |

---

### US-1.2 Phase 0 / Phase 1 visual distinction
**NOT IMPLEMENTED**

| | |
|---|---|
| **What exists** | `phase-card.tsx` component exists with `pending / running / completed / failed` status. Step list renders in `workflow-artifact.tsx` with numbered badges. |
| **What's missing** | No grouping of steps into Phase 0 (pilot) vs Phase 1 (full run) in the step list. No lock icon on Phase 1 steps. No tooltip `"Full run starts after pilot QC passes"`. Phase-card component is rendered in `pilot-run-panel.tsx` but not surfaced as a visual hierarchy in the main workflow card. |
| **Gap** | Step list needs phase grouping; lock state for Phase 1 |

---

### US-1.3 Auto-advance pilot → full run
**NOT IMPLEMENTED**

| | |
|---|---|
| **What exists** | `pilot-run-panel.tsx` shows a "Run Full Analysis" button after pilot completion. |
| **What's missing** | User must manually click. There is no SSE event listener for `qc_all_passed` that would auto-trigger the full run. No toast `"Pilot passed — starting full run"`. The backend emits per-process `qc_gate_triggered` events but no aggregate `pilot_qc_passed` event. |
| **Gap** | New SSE event `pilot_qc_passed` on backend; auto-call `onRun()` in frontend when received |

---

## Epic 2 — The QC Gate Modal

### US-2.1 Human-readable modal content + button consequences
**PARTIAL**

| | |
|---|---|
| **What exists** | Title `"Quality Control Gate Triggered"` (static). Failures shown with measured value and threshold (`Badge` + threshold text). Three buttons: Cancel, Proceed Anyway, Retry. |
| **What's missing** | Process name shown raw: `<strong>{processName}</strong>` — `"STAR_ALIGN"` stays as `"STAR_ALIGN"`, not `"Read Alignment (STAR)"`. No lookup table for humanisation. Buttons show action labels only — no consequence line (e.g. `"Retry: re-runs alignment ~8 min"`). |
| **Gap** | Process name humanisation lookup table; consequence subtitle on each button |

---

### US-2.2 Suggestion card: confidence-aware defaults
**PARTIAL**

| | |
|---|---|
| **What exists** | Confidence badge colour changes at 0.8: `variant={confidence > 0.8 ? "default" : "secondary"}`. All suggestions pre-checked unconditionally: `new Set(suggestions.map(s => s.parameter))`. |
| **What's missing** | Suggestions with confidence < 0.7 are still pre-checked — should be unchecked with a yellow advisory note. Parameter names shown raw (`dose_weighting`, not `"Dose Weighting"`). No `"Learn more"` link. |
| **Gap** | Auto-uncheck + yellow label for low-confidence suggestions; parameter name humanisation |

---

### US-2.3 Multiple failures in one modal, not multiple modals
**IMPLEMENTED**

`workflow-artifact.tsx` sets `qcGateData` from one SSE event and opens the modal once. `qc-gate-modal.tsx` renders all `failedMetrics` in a list inside one dialog. Multiple failures from FASTP (reads + Q30 + adapter) all appear together.

**What's missing:** No "overall assessment" or root-cause summary line at the top of the failures list — each failure is displayed independently.

---

### US-2.4 Partial suggestion selection with live summary
**PARTIAL**

| | |
|---|---|
| **What exists** | Checkbox toggle implemented (`toggleSuggestion`). Retry button updates live: `"Retry with {selectedSuggestions.size} Adjustment{s}"`. |
| **What's missing** | No pre-submit summary line above the footer showing exactly which parameters will change (e.g. `"Will apply: dose_weighting false→true, patch_size 3→5"`). |
| **Gap** | One `<p>` summary line computed from `selectedSuggestions` set |

---

### US-2.5 "Proceed Anyway" confirmation + audit badge
**NOT IMPLEMENTED**

| | |
|---|---|
| **What exists** | Button exists. `handleProceedAnyway()` closes modal and clears state. |
| **What's missing** | No confirmation dialog before proceeding. No "this will be recorded" copy. No override badge or annotation on the step card after proceeding. No backend logging of the override decision. |
| **Gap** | Confirmation dialog; step-level override badge; backend audit event |

---

### US-2.6 Cancel returns to editable state with failure note
**NOT IMPLEMENTED**

| | |
|---|---|
| **What exists** | Cancel calls `onStop()` and closes modal. |
| **What's missing** | Workflow step card does not show a collapsed "Last run: QC failed — drift 78 Å" annotation after cancellation. No state preserved for the QC failure on the step. Steps do not transition to a visually editable state distinct from "never run". |
| **Gap** | `lastQCFailure` state per step; collapsed annotation on step card |

---

## Epic 3 — Domain-Specific QC Guidance

### US-3.1 Cryo-EM motion correction: domain language
**PARTIAL**

| | |
|---|---|
| **What exists** | Failure message uses Å: `f"Excessive drift: {total_drift:.1f}Å (threshold: 50Å)"`. Suggestion reason mentions dose weighting: `"Excessive drift (78.0Å). Dose weighting can improve motion correction."` |
| **What's missing** | "Beam-induced motion" terminology not used in the failure description itself. No context explaining why dose weighting helps (the physics). No `"Learn more"` link to MotionCor2 docs. |
| **Gap** | Richer failure description text; contextual explanation |

---

### US-3.2 CTF defocus: BELOW vs ABOVE range
**NOT IMPLEMENTED**

| | |
|---|---|
| **What exists** | `_parse_ctf_metrics` validates defocus in range `(1000, 100000)` and returns `None` if outside, which means no QC gate fires. The failure message for bad fit quality mentions widening search range generically. |
| **What's missing** | When defocus is outside the valid range, the parser returns `None` — the QC gate silently skips rather than surfacing a failure message. There is no BELOW / ABOVE direction logic. User never learns their defocus is near-focus or wildly out of range. |
| **Gap** | Return a failure dict when defocus is out of range (instead of `None`); add directional language |

---

### US-3.3 RNA-seq critical alignment (< 20%)
**NOT IMPLEMENTED**

| | |
|---|---|
| **What exists** | Single threshold check at 60%: `if alignment_rate < 60: → failure`. Generic message for any value below 60%. |
| **What's missing** | No severity tiers. `alignment_rate = 8%` gets the same message as `alignment_rate = 55%`. No "check input data first" recommendation. No different primary button. |
| **Gap** | Two-tier check (< 20% = critical, < 60% = warning); separate message and button text for each tier |

---

### US-3.4 CellRanger comma-escaped numbers
**IMPLEMENTED**

`_clean()` helper in `qc_trace_monitor.py` strips commas before `int()` conversion. `"1,247"` → `1247` correctly. Threshold check uses the integer value.

---

### US-3.5 Metagenomics DB suggestion with trade-off
**PARTIAL**

| | |
|---|---|
| **What exists** | Suggests `standard_8gb` as `suggested_value`. Reason: `"Low classification rate (28.0%). A larger database may cover more taxa."` |
| **What's missing** | No mention of RAM requirements or download size. No check whether the suggested database exists on the current compute node. Reason text doesn't distinguish "minikraken vs standard" by coverage percentage. |
| **Gap** | Trade-off copy; compute environment DB availability check |

---

## Epic 4 — The Skip / Override Path

### US-4.1 Skip pilot: no dialog, system learns
**PARTIAL**

| | |
|---|---|
| **What exists** | Skip link calls `setPilotBannerDismissed(true)` — dismisses for this browser session only. No confirmation dialog. |
| **What's missing** | Session-only: refreshing the page shows the banner again. No backend record of the skip. No 7-day suppression logic. |
| **Gap** | `POST /api/user/pilot-skip` to store skip preference; read back on load |

---

### US-4.2 "Pause at QC failures" toggle
**PARTIAL**

| | |
|---|---|
| **What exists** | AutoFix exists for post-run failures (lines 280–309 of `workflow-artifact.tsx`). Execution control panel has sandbox/production mode toggle. |
| **What's missing** | No "pause at QC failures" toggle. No auto-apply mode. No consolidated end-of-run QC summary when running in auto-apply mode. |
| **Gap** | New toggle in execution options; `autoApplyQC: boolean` in execution config; consolidated report on completion |

---

### US-4.3 Custom QC thresholds
**NOT IMPLEMENTED**

No custom threshold UI anywhere in the frontend. Thresholds are hard-coded in `qc_trace_monitor.py`. No settings panel, no per-workflow override, no API endpoint for threshold customisation.

**Gap:** New settings section in the workflow card; `POST /api/workflows/:id/qc-thresholds`; backend to read per-invocation threshold overrides.

---

## Epic 5 — Core Facility / Automation

### US-5.1 Multi-job QC triage dashboard
**NOT IMPLEMENTED**

No dashboard view showing QC status across concurrent jobs. Navigation has a "Dashboard" route but it shows workflow history, not a live QC triage view. No "Apply all suggestions" or "Bulk apply" controls.

**Gap:** New dashboard tab or panel; jobs sorted by QC status; per-job suggestion apply; bulk apply across all waiting jobs.

---

### US-5.2 Automated mode with confidence threshold + email escalation
**NOT IMPLEMENTED**

No `auto_apply_confidence_threshold` setting in backend or frontend. No email escalation on critical failures. All QC gates always pause and wait for user input.

**Gap:** New automation settings; backend logic to auto-apply suggestions above threshold; escalation notification (email or Slack) for critical failures.

---

## Epic 6 — Transparency and Trust

### US-6.1 Suggestion provenance (rules / ML / literature)
**NOT IMPLEMENTED**

`ParameterSuggestion` dataclass has no `source` field. `parameter_suggester.py` returns suggestions with `parameter`, `currentValue`, `suggestedValue`, `reason`, `confidence` — provenance not tracked. QC modal has no provenance display.

**Gap:** Add `source: Literal["rules", "ml", "literature"]` to suggestion dataclass; surface in modal tooltip.

---

### US-6.2 Post-completion QC report + Methods copy
**PARTIAL**

| | |
|---|---|
| **What exists** | `WorkflowReportViewer` component exists; citations panel has "Copy for Methods section" (only covers citations). |
| **What's missing** | QC gate events not included in any report. No structured log of: gate fired → decision made → parameter changed → result after retry. "Copy for Methods" text doesn't mention QC decisions. |
| **Gap:** | Backend must store QC events per invocation; new QC summary section in report viewer; extend methods copy template |

---

### US-6.3 Warnings vs. failures: visual distinction
**PARTIAL**

| | |
|---|---|
| **What exists** | Validation warnings use yellow `border-yellow-500/50` styling; validation errors use `variant="destructive"` (red). QC failures in the modal use red `XCircle` icons. |
| **What's missing** | The warning/failure distinction applies to pre-run validation, not to QC gate events. QC events are always treated as gates (modal pops up) — there is no "near-threshold warning" that lets the run continue. Metrics approaching a threshold don't appear on the step card as yellow advisories. |
| **Gap:** | Near-threshold warning tier in `_check_qc_thresholds` (e.g. within 10% of threshold); surface as yellow step annotation without gating the run |

---

## Epic 7 — Error and Recovery States

### US-7.1 No-suggestions fallback with troubleshooting steps
**PARTIAL**

| | |
|---|---|
| **What exists** | `qc-gate-modal.tsx` lines 239–244: `"No automatic parameter suggestions available. You may need to manually adjust parameters."` |
| **What's missing** | Generic message — no domain-specific troubleshooting steps. For a cryo-EM CTF failure with no suggestions, user has no next action. "Retry" button is hidden when no suggestions exist (correct), but user is left with only Cancel/Proceed. |
| **Gap:** | Per-domain fallback troubleshooting text keyed on process name; e.g. for CTF: "Check microscope voltage, Cs, and pixel size calibration" |

---

### US-7.2 SSE reconnection banner
**PARTIAL**

| | |
|---|---|
| **What exists** | `eventSource.addEventListener('error', ...)` logs a warning and closes the connection. |
| **What's missing** | No user-visible banner. No reconnection loop (connection is closed and not retried). No "last known state" preservation. No replay of QC events that fired while disconnected. User sees frozen progress with no explanation. |
| **Gap:** | Reconnect loop with exponential backoff; `"Live updates paused — reconnecting…"` banner; event replay via `GET /api/workflows/:id/qc-events?since=timestamp` |

---

### US-7.3 Retry counter, diff panel, escalation
**NOT IMPLEMENTED**

| | |
|---|---|
| **What exists** | QC modal title is always `"Quality Control Gate Triggered"`. No retry count tracked anywhere. |
| **What's missing** | No retry count in modal title (`"Retry #2"`). No before/after diff panel showing what changed since the last retry. No escalation message after N retries. `qcGateData` state in `workflow-artifact.tsx` is replaced each time a gate fires — history is discarded. |
| **Gap:** | `qcRetryCount: Map<processName, number>` in component state; before/after diff computed from previous `qcGateData`; escalation alert after 3 retries for the same step |

---

## Implementation Priority

### Tier 1 — High impact, low effort (patch existing components)

| Story | Change | Effort |
|---|---|---|
| US-2.1 | Add process name lookup table: `STAR_ALIGN → "Read Alignment (STAR)"` | 1–2 h |
| US-2.1 | Add consequence subtitle under each modal button | 30 min |
| US-2.2 | Auto-uncheck + yellow note for confidence < 0.7 | 1 h |
| US-2.4 | Add summary line above modal footer | 30 min |
| US-3.2 | Return failure dict (not `None`) when CTF defocus is out of range; add BELOW/ABOVE language | 2 h |
| US-3.3 | Two-tier alignment failure (< 20% critical vs < 60% warning) | 2 h |
| US-7.1 | Per-domain fallback troubleshooting text in no-suggestions case | 2 h |
| US-6.3 | Near-threshold warning tier (yellow, non-gating) | 3 h |

### Tier 2 — Medium effort (new state, existing architecture)

| Story | Change | Effort |
|---|---|---|
| US-2.5 | Confirmation dialog for "Proceed Anyway" + step badge | 3 h |
| US-2.6 | Persist QC failure as collapsed annotation on step card | 3 h |
| US-1.3 | Add `pilot_qc_passed` SSE event in backend; auto-advance in frontend | 4 h |
| US-7.3 | Retry counter + diff panel in QC modal | 4 h |
| US-7.2 | SSE reconnection loop + user banner | 4 h |
| US-1.1 | Domain-specific units in banner copy (micrographs / reads / cells) | 2 h |

### Tier 3 — Larger features (new backend + frontend systems)

| Story | Change | Effort |
|---|---|---|
| US-4.3 | Custom threshold UI + per-invocation threshold API | 1–2 days |
| US-6.1 | `source` field in suggestion dataclass + provenance UI | 1 day |
| US-6.2 | QC event store per invocation + report section + methods copy | 2 days |
| US-4.1 | Backend skip preference store + 7-day suppression | 1 day |
| US-4.2 | Auto-apply toggle + consolidated QC end-of-run report | 2 days |
| US-1.2 | Phase 0/1 visual grouping + lock state in step list | 2 days |
| US-5.1 | Multi-job QC triage dashboard | 3–4 days |
| US-5.2 | Automation mode + confidence threshold + email escalation | 3–4 days |

---

## Summary Table

| Story | Title | Status |
|---|---|---|
| US-1.1 | Pilot banner copy | PARTIAL |
| US-1.2 | Phase 0/1 visual distinction | NOT IMPLEMENTED |
| US-1.3 | Auto-advance when pilot passes | NOT IMPLEMENTED |
| US-2.1 | Human-readable modal + button consequences | PARTIAL |
| US-2.2 | Confidence-aware suggestion defaults | PARTIAL |
| US-2.3 | Multiple failures in one modal | IMPLEMENTED |
| US-2.4 | Partial selection with summary | PARTIAL |
| US-2.5 | Proceed Anyway confirmation + audit badge | NOT IMPLEMENTED |
| US-2.6 | Cancel → editable state + failure note | NOT IMPLEMENTED |
| US-3.1 | Motion correction domain language | PARTIAL |
| US-3.2 | CTF defocus direction (below/above range) | NOT IMPLEMENTED |
| US-3.3 | Alignment < 20% critical severity | NOT IMPLEMENTED |
| US-3.4 | CellRanger comma-escaped numbers | IMPLEMENTED |
| US-3.5 | Metagenomics DB trade-off language | PARTIAL |
| US-4.1 | Skip pilot persistence (7-day) | PARTIAL |
| US-4.2 | Pause-at-QC toggle + auto-apply mode | PARTIAL |
| US-4.3 | Custom QC thresholds UI | NOT IMPLEMENTED |
| US-5.1 | Multi-job QC triage dashboard | NOT IMPLEMENTED |
| US-5.2 | Automation mode + email escalation | NOT IMPLEMENTED |
| US-6.1 | Suggestion provenance display | NOT IMPLEMENTED |
| US-6.2 | Post-completion QC report + methods copy | PARTIAL |
| US-6.3 | Warning vs failure visual distinction | PARTIAL |
| US-7.1 | No-suggestions troubleshooting fallback | PARTIAL |
| US-7.2 | SSE reconnection banner + replay | PARTIAL |
| US-7.3 | Retry counter + diff panel + escalation | NOT IMPLEMENTED |

**Totals: 2 IMPLEMENTED · 12 PARTIAL · 11 NOT IMPLEMENTED**
