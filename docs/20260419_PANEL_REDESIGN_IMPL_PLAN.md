# BioMate Workflow Panel Redesign — Implementation Plan

**Date:** 2026-04-19  
**Branch:** integration/next-phase  
**Reference design:** `reference/claude_design/biomate/HANDOFF.md`

---

## 1. Design vs Implementation Gap Audit

### Summary

| Status | Count |
|---|---|
| Fully implemented | 28 |
| Partial | 5 |
| Missing (scoped to future) | 1 |

### Partial items (priority order)

| # | Feature | Gap |
|---|---|---|
| P1 | AutoLoopPanel inline under failed phase | Panel was at workflow level; must appear under the specific phase that halted |
| P2 | Per-phase auto-loop toggle | Single whole-workflow on/off; need per-phase switch in each PhaseGroupSection |
| P3 | Step/Phase skip → SkipConfirmModal | Skip fires immediately; no confirmation modal with downstream dependency warning |
| P4 | AutoLoopCard Accept per-phase | Dismiss works; no Accept→enable-per-phase toggle |
| P5 | Phase data model: summary/qc[] fields | Backend returns them but frontend ViewerPhase type doesn't expose them |

### Deferred to future work

| Feature | Reason |
|---|---|
| SkipConfirmModal with downstream deps | Risk of downstream breakage is real; needs design review before enabling |

---

## 2. Implementation Done This Session

### P1 — AutoLoopPanel inline under its failed phase ✅

**Before:** `AutoLoopPanel` rendered at the top of the workflow Card body (viewer lines 1681–1688), floating above all phase groups regardless of which phase triggered the QC halt.

**After:** Removed top-level panel. Each `PhaseGroupSection` receives:
- `autoLoopPanelState` — the full `AutoLoopPanelState` object, only set when the panel's `gateResults.phase` key matches this group
- `onDismissAutoloop` — clears the panel state at viewer level

Phase key matching (`autoloopPhaseMatches`):
- `phase_A` → group key `A` ✓
- `phase_1_docking` → group key `1` ✓ (startsWith match)
- Single-group workflow (`key === 'all'`) always matches ✓

The panel renders inside a `border-t` section at the bottom of the phase group, after step cards and param editor.

**Files changed:**
- `frontend/client/src/components/nextflow-workflow-viewer.tsx`
  - Added `autoloopPhaseMatches()` helper (~line 447)
  - Added `autoLoopPanelState`, `autoloopEnabled`, `onToggleAutoloop`, `onDismissAutoloop` props to `PhaseGroupSection` interface
  - Removed top-level `AutoLoopPanel` block (was ~line 1681)
  - Added inline panel render at bottom of `PhaseGroupSection`
  - Updated call site to pass phase-matched state

### P2 — Per-phase auto-loop toggle ✅

**Before:** No per-phase on/off switch. Global `AutoLoopPanel` was always shown when any gate results arrived.

**After:**
- Added `autoloopMap: Record<string, boolean>` state to viewer (default all `true`)
- Each `PhaseGroupSection` renders a compact `Switch` + `"Auto-loop QC"` label at its footer
- `data-testid="autoloop-toggle-{group.key}"` for E2E
- Toggle stored in `autoloopMap[group.key]`; default is `true` (on) — missing key = enabled
- When toggled off, the `AutoLoopPanel` for that phase is suppressed even if gate results arrive

---

## 3. Remaining Work

### 3A — SkipConfirmModal (deferred — design review needed)

**Scope:** When user clicks Skip on a step or phase, show a modal listing downstream phases that depend on the skipped item, with "Skip anyway" / "Cancel" buttons.

**Why deferred:** Downstream dependency breakage is non-trivial in Nextflow (outputs of skipped steps become empty → downstream processes fail to find inputs). The correct behavior (auto-stub outputs, abort downstream, or warn-only) requires a design decision.

**Where to implement when ready:**
- `frontend/client/src/components/skip-confirm-modal.tsx` — new component
- `PhaseGroupSection` / `PhaseCard` — intercept `onSkip` call, open modal first
- `handleSkipPhase` in viewer — only called after modal confirmation

### 3B — AutoLoopCard Accept action

Currently `onAccept` in `AutoLoopPanel` only shows a toast. The intended behavior is to apply the suggested parameter changes from `remediations[*].param_changes` directly to the workflow params and trigger a re-run.

**Where to implement:**
- `AutoLoopPanel`: add `onAccept?: (paramChanges: Record<string, unknown>) => void` prop
- Viewer: wire `onAccept` → merge `param_changes` into `params` state → call `onExecute`

### 3C — Phase data model completeness

`ViewerPhase` type in viewer is missing `summary`, `qc_gates`, and `autoloop` boolean fields that the design's `Phase` type defines. These are returned by the backend in `workflow.phases` but stripped when building `updatedPhases`.

---

## 4. Billing Audit Scope

### LLM Costs

Emission point: `frontend/server/routes.ts` ~line 4129  
Trigger: every `/api/ai_assistant/stream` call that completes  
Payload: `user_id`, `session_id`, `model`, `input_tokens`, `output_tokens`  
Destination: `{GALAXY_URL}/internal/billing/llm_cost` via `BILLING_INTERNAL_KEY`  
Pilot bypass: users in `PILOT_ACCOUNT_EMAILS` skip emission  

**Gap:** Token count uses `tokenCounter.countText()` (character-based estimator), not Anthropic's actual token counts from the API response. This can under-count by ~15% for code-heavy outputs.

### AWS Batch Compute Costs

Emission point: `backend/lib/galaxy/jobs/runners/nextflow_s3_manager.py`  
Trigger: job completion event from AWS Batch EventBridge → Lambda `biomate-batch-billing`  
Payload: `job_id`, `user_id`, `instance_type`, `vcpus`, `memory_mb`, `gpu_count`, `duration_seconds`  
Destination: `{GALAXY_URL}/internal/billing/job_completed`  
Lago metric: `vcpu_hours` (billable_metric code)

**Verification queries:**
```bash
# Check Lago usage for a user
curl -H "Authorization: Bearer $LAGO_API_KEY" \
  "$LAGO_URL/api/v1/customers/{userId}/current_usage?external_subscription_id={userId}"

# Check billing backend health
curl -H "X-Internal-Key: $BILLING_INTERNAL_KEY" \
  http://localhost:8081/internal/billing/admin/health
```

### AWS Batch Only — Enforcement

All Nextflow workflow executions must go through AWS Batch. Local execution is disabled.

**Where enforced:**
- `nextflow_executor.py` — `_submit_to_aws_batch()` is the only execution path; local `nextflow run` is not called
- Batch CE: `biomate-nextflow-ce-v2` with LT v9
- Queue: `biomate-nextflow-queue` (CPU) / `galaxy-cloud-queue-gpu` (GPU)
- `NEXTFLOW_EXECUTION_MODE=batch` env var must be set

---

## 5. Drug Dev Pilot Test Plan

**Test file:** `frontend/e2e/drug-discovery-pilot-e2e.e2e.ts`

| Session | Workflow | Key assertion |
|---|---|---|
| S1 | ADMET property prediction | ADMET gate results appear; auto-loop toggle visible |
| S2 | IVIVE clearance | Workflow completes; billing LLM cost emitted |
| S3 | Pocket finder | Run starts on AWS Batch; no local execution |
| S4 | Pharmacophore | Phase-grouped steps shown; auto-loop panel under correct phase |
| S5 | Compound ranking | Findings card populated after completion |
| S6 | CRO submission export | Download button works; QC audit log accessible |

**Billing assertions to add:**
- After each run: call `GET /api/billing/usage` → `breakdown.llm.calls` incremented
- After Batch job completes: `breakdown.compute.vcpu_hours` > 0
- Pilot users (`PILOT_ACCOUNT_EMAILS`): no billing events emitted

---

## 6. Relevant Files

| File | Purpose |
|---|---|
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | Main viewer — phase grouping, autoloop state, run controls |
| `frontend/client/src/components/phase-card.tsx` | Per-step card — params, run, skip, outputs |
| `frontend/client/src/components/auto-loop-panel.tsx` | AutoLoopPanel — gate table, remediations, citations |
| `frontend/client/src/components/step-adjust-modal.tsx` | Adjust & rerun modal |
| `frontend/client/src/components/findings-card.tsx` | Post-run findings display |
| `frontend/client/src/components/license-gate.tsx` | Pre-run credential check |
| `frontend/client/src/components/workflow-disambiguation-card.tsx` | Disambiguation card in chat |
| `frontend/server/routes.ts` | LLM billing emission (~line 4129) |
| `backend/lib/galaxy/jobs/runners/nextflow_s3_manager.py` | Batch job billing tag |
| `backend/tests/test_billing_e2e.py` | Billing E2E test suite |
| `reference/claude_design/biomate/HANDOFF.md` | Design handoff spec |
