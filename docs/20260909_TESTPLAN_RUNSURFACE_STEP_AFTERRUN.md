# Test Plan — Run Surface / Workflow Panel / Step Deep-View / After-Run Report

**Date:** 2026-09-09
**Branch:** `integration/dev-test`
**Scope:** `nextflow-workflow-viewer.tsx`, `steps/step-detail.tsx`, `v2/AfterRunReport.tsx`, and the SSE + REST wiring in `frontend/server/routes.ts`.
**Method:** Every `data-testid`, endpoint, SSE event, and visible copy string below was extracted directly from the real source (line references in-text). Nothing is invented. Items the code does NOT expose (commented-out / not-wired) are called out explicitly under "Flagged as undeterminable / not testable from code".

All E2E tests must run against the live server per CLAUDE.md (no `page.route()` mocks). Use fixture `lifeifei163361@163.com` and the dev bypass token.

---

## Coverage checklist

| # | Surface | Use case | State(s) | SSE / endpoint core | UC id |
|---|---------|----------|----------|---------------------|-------|
| 1 | Workflow panel | Idle pre-run — tabs + settings strip + param strip | idle | `/api/nextflow/steps`, `/api/qc/profiles` | RS-01 |
| 2 | Workflow panel | Required-param block gate on Run button | idle | (client-only) | RS-02 |
| 3 | Workflow panel | Execution-blocked banner: Fix now / Confirm anyway / auto-countdown | idle→running | `onExecute` prop | RS-03 |
| 4 | Workflow panel | **Live SSE idle→running→completed** phase transition | idle→running→completed | `step_state`, `workflow_state` | RS-04 |
| 5 | Workflow panel | **Live SSE …→failed** phase transition + Restart | running→failed | `step_state`, `workflow_state` | RS-05 |
| 6 | Workflow panel | Running action bar (Pause/Stop) + Resume | running/paused | `onPause`/`onCancel`/`onResume` | RS-06 |
| 7 | Workflow panel | Completed footer "Run again" + post-run links | completed | `/download-all`, `/methods-report`, `ai/analyze` | RS-07 |
| 8 | Workflow panel | Failed footer Restart / Resume-from-last / Start over | failed | `nextflowStatus.failure`, `/rerun` | RS-08 |
| 9 | Workflow panel | QC gate blocked (two-number measured vs threshold) apply/keep/cancel | running | `qc_gate_triggered` SSE | RS-09 |
| 10 | Workflow panel | QC gate 10s auto-proceed countdown | running | `qc_gate_triggered` SSE | RS-10 |
| 11 | Workflow panel | QC advisory (near-threshold) step chip | running | `qc_warning` SSE | RS-11 |
| 12 | Workflow panel | Per-phase QC threshold editor (edit/reset) | any | `/api/qc/profiles` | RS-12 |
| 13 | Workflow panel | Completed QC results panel (measured vs threshold) | completed | `nextflowStatus.qc_report` | RS-13 |
| 14 | Workflow panel | Parameter override — GlobalParamsPanel all types | idle | (client-only) | RS-14 |
| 15 | Workflow panel | Per-phase inline params (edit/collapse) | any | (client-only) | RS-15 |
| 16 | Workflow panel | Step output preview (image/table/FASTA/VCF/text) | completed | `/step-file` | RS-16 |
| 17 | Workflow panel | Auto-loop panel — gate table halt/advisory/pass + was→now diff | running | `autoloop_gate_results`, `autoloop_update`, `autoloop_phase_complete`, `autoloop_escalation` | RS-17 |
| 18 | Workflow panel | Auto-loop manual remediation inputs + Apply & Re-run | running | `autoloop_update` SSE | RS-18 |
| 19 | Workflow panel | Skip-dependency map (skippable / blocked / warn) | idle | `/api/nextflow/skip-analysis` | RS-19 |
| 20 | Workflow panel | Lazy step fetch / loading / empty states | idle | `/api/nextflow/steps` | RS-20 |
| 21 | Workflow panel | Chat-progress narration relay | any | `chat_progress` SSE | RS-21 |
| 22 | Workflow panel | Chain / proactive suggestions relay | completed | `chain_suggestion`, `proactive_suggestion` SSE | RS-22 |
| 23 | Step detail | Provenance row (inputs → tool → N outputs · duration) | completed/failed | (props) | SD-01 |
| 24 | Step detail | Resolved params + origin badges (default/inherited/override/unknown) | — | `resolveStepParams` | SD-02 |
| 25 | Step detail | Per-row revert | — | (client-only) | SD-03 |
| 26 | Step detail | Rendered ⇄ raw toggle + RawBytesViewer | — | `/step-file` | SD-04 |
| 27 | Step detail | Output tabs + evidence-class render + download | — | `/step-file` | SD-05 |
| 28 | Step detail | Re-run from here + honest empty states | — | `onAdjustAndRerun` | SD-06 |
| 29 | After-run | Tab bar composition + hide-when-empty | completed | multiple | AR-01 |
| 30 | After-run | Outputs tab (table, preview, bulk zip, save-to-project) | completed | `/output_files`, `download_all_zip` job, `/reproducibility`, `/save-to-project` | AR-02 |
| 31 | After-run | Findings tab (summary, key results, figures, download) | completed | `/api/jobs` findings_analysis | AR-03 |
| 32 | After-run | Findings on failed run (no spinner, static message) | failed | `/api/jobs` findings_analysis | AR-04 |
| 33 | After-run | Methods tab (real vs empty) | completed | `/api/jobs` methods_report | AR-05 |
| 34 | After-run | Parameters tab + Run-again-with-edits | completed | CustomEvent | AR-06 |
| 35 | After-run | Software tab (present vs empty) | completed | `/software` | AR-07 |
| 36 | After-run | Citations tab (present vs empty) | completed | `/citations` | AR-08 |
| 37 | After-run | QC audit tab — 4-stat summary + audit log + chain-of-custody + e-sig hide | completed | `/qc-events` | AR-09 |
| 38 | After-run | QC audit tab — all-passed empty state | completed | `/qc-events` (empty) | AR-10 |
| 39 | After-run | Trajectory tab (honest empty) | completed | `/trajectory` | AR-11 |
| 40 | After-run | Download comprehensive report (dedup, toast) | completed | client blob | AR-12 |
| 41 | After-run | Failed-run section (badge, error, autofix history, log tail) | failed | `/autofix3/sessions` | AR-13 |

**Total use cases: 41.**

---

## §1 Workflow panel — `frontend/client/src/components/nextflow-workflow-viewer.tsx`

**Purpose:** The right-hand run surface. Renders a status-aware header badge, three top tabs (`Workflow settings` / `Phases` / `After run`), phase cards with live per-step status, QC gates, auto-loop remediation, a skip map, and a sticky footer whose primary CTA changes label by run state. Tab auto-defaults by `status` (idle/pending_review→settings, running/paused→phases, completed/failed→after-run) until the user manually switches (`tabAutoDefault`, lines 1064–1072).

Root testid: `workflow-artifact-panel`. Overall status badge: `workflow-overall-status-badge` with `data-status` ∈ `idle|running|completed|failed` (lines 2520–2536). Tab strip: `panel-tabs`; tabs `panel-tab-settings`, `panel-tab-phases`, `panel-tab-after-run` (lines 2579–2643).

---

### RS-01 · Idle pre-run panel renders name, tabs, and settings strip
- **Preconditions/state:** `status='idle'`, `workflowDefinition` supplied with `name`, `domain`, `required_params`/`optional_params`, `nextflow_path`. Not yet run.
- **Input:** Mounted panel with a real workflow (e.g. nf-core/rnaseq) suggested via chat.
- **Action flow:**
  1. Open a chat, send a workflow request, wait for the card to open the panel.
  2. Read the header name (`.panel-name`, line 2496) and kicker (`DOMAIN · WORKFLOW`, line 2481).
  3. Assert the overall badge is hidden-but-present with `data-status="idle"` (line 2530–2536; idle badge is `display:none`).
  4. Assert the auto-default tab is `settings` (`panel-tab-settings` aria-selected, `panel-settings` body visible).
  5. Expand `button-toggle-workflow-settings` (line 2894) if collapsed.
- **Expected output:** `.panel-name` = workflow name (never "undefined"/"Untitled" for a real workflow, line 2496). Settings strip shows label `Parameters` + `(N params)` hint (line 2903). Required-params chip `chip err` "Required" appears when unfilled (line 2905). `panel-tabs` present with the three tabs.
- **Information flow:** `workflowDefinition.name/domain` prop → header render. Steps: `/api/nextflow/steps?nextflow_path=…` (line 1125) → `lazySteps` → `phases` memo (line 1213) → `groupedPhases` → phase count badge. `/api/qc/profiles` (line 2025) → `qcDefaults`/`availableQcProfiles`.
- **Pass criteria:** Name non-empty, `data-status="idle"`, `panel-tab-settings` selected, no phase card in a non-pending state.
- **Edge/error cases:** `workflowDefinition.name` absent → "Untitled" (line 2496) — should NOT happen for real workflows (flag if seen). No params → empty-state "This workflow has no configurable parameters." (line 2886).

### RS-02 · Run button hard-blocks on unfilled required params
- **Preconditions/state:** `status='idle'`, at least one `required_params` entry with empty value, `prereqChecklist.overrideAllowed` falsy.
- **Input:** Workflow whose required param (e.g. `input`/samplesheet) is empty.
- **Action flow:**
  1. Open panel idle; do not fill the required param.
  2. Read primary CTA `button-run-workflow-panel` (line 2598).
  3. Attempt to click.
- **Expected output:** CTA disabled (line 3600–3606: `globalRequiredUnfilledCount > 0`), `title` = "Fill in N required parameter(s) above before running" (line 3608), `data-required-unfilled="N"` (line 3612). Settings strip auto-opens (`hasUnfilledRequired` effect, line 1923).
- **Information flow:** `renderedParameters` (buildViewerParameters, line 247) → `globalRequiredUnfilledCount` memo (line 1778, excludes phase-pinned params) → disabled prop.
- **Pass criteria:** Button disabled + correct `data-required-unfilled` count; enabling requires filling the field.
- **Edge/error cases:** `prereqChecklist.overrideAllowed=true` → `hasUnfilledRequired=false` (line 1845), button enabled. Phase-pinned required params are excluded from this global count (they gate at phase level).

### RS-03 · Execution-blocked banner — Fix now / Confirm anyway / auto-confirm countdown
- **Preconditions/state:** `executionBlockedReason` prop set (low-confidence run), `status='idle'`, not prereq-blocked/autofix/license-blocked.
- **Input:** A low-confidence workflow suggestion that sets `executionBlockedReason`.
- **Action flow:**
  1. Mount panel with `executionBlockedReason`.
  2. Observe the footer alert (line 3561).
  3. Read `low-confidence-countdown` (line 3567) — "Auto-confirming in Ns unless you act."
  4. Click `Fix now` (line 3573) → cancels countdown, opens settings strip; OR click `button-confirm-low-confidence-run` (line 3584).
  5. Alternatively wait 10s (`LOW_CONF_TIMEOUT_S`, line 1190) for auto-confirm.
- **Expected output:** Alert "Execution blocked — {reason}" (line 3565). Countdown ticks down. "Fix now" opens `globalParamsOpen`, stops the timer (line 3575). "Confirm anyway" fires `onExecute` with `__executionOverrides.allowLowConfidence=true` (line 1870). Auto-timeout fires the same with `autoProceeded=true` and toasts "Auto-proceeded" (line 1876) + `onWorkflowProgress` kind `workflow.auto_proceeded`.
- **Information flow:** `executionBlockedReason` prop → countdown effect (line 1893) → `fireLowConfidenceConfirm('timeout')` → `onExecute`. Telemetry `workflow.low_confidence_override_clicked` / `…_auto_proceeded` (line 1866).
- **Pass criteria:** Countdown visible, Fix-now cancels it, Confirm fires execute with the override payload, auto-timeout fires after 10s.
- **Edge/error cases:** `status='running'|'completed'` or prereq/autofix/license blocked → countdown suppressed (line 1899), Confirm-anyway disabled (line 3585).

### RS-04 · **Live SSE idle→running→completed phase transition (CRITICAL)**
- **Preconditions/state:** Real run dispatched (AWS Batch). `invocationId` set so the panel opens an `EventSource('/api/workflows/:invocationId/events')` (line 2066). Phases present.
- **Input:** A short real workflow (or a fixture run) that starts, runs at least one step, and completes.
- **Action flow:**
  1. Mount panel idle; assert overall badge `data-status` starts non-running (idle hidden or pending phases `data-status="pending"`).
  2. Click `button-run-workflow-panel`; assert action bar transitions and header badge `data-status` moves to `running` (parent-driven `status` prop).
  3. Via Playwright `waitForFunction`, observe a phase-group card `phase-group-<key>` flip `data-status` from `pending`→`running` (line 574), and a step row `phase-card-<stepId>` `data-status` change as `step_state` SSE events arrive (line 2227–2251).
  4. Wait for terminal: overall badge `data-status="completed"`, footer CTA becomes `panel-run-again-cta` "Run again" (line 3598/3623).
- **Expected output:** Observed transition sequence `pending → running → completed` on at least one phase card and the overall badge. Step chips show `RUNNING` (line 731) then `DONE` (line 732). Completion banner `workflow-completion-banner` appears (line 2819).
- **Information flow:** SSE `step_state` `{step_id, step_state, job_id}` → `setStepExecutionById[stepId].phaseStatus = mapBackendToPhaseStatus` (line 2234) → `updatedPhases` (line 1494) → `PhaseGroupSection` `data-status` (step row line 711, phase group line 574). SSE `workflow_state` terminal → clears pollers (line 2258). Overall header badge is driven by the parent `status` prop (line 2522), set from the parent's polled run status. Per-process status can also come from `nextflowStatus.processes` (line 1455–1478).
- **Pass criteria:** Test MUST observe at least one real idle→running→terminal transition live (not just the final state) — per CLAUDE.md this is mandatory.
- **Edge/error cases:** SSE drops (`es.onerror`, line 2306) → connection closes silently; the parent's status polling still drives the overall badge. If steps never emit `step_state`, the progress-heuristic fallback (line 1472) marks one phase running by `progress%`.

### RS-05 · **Live SSE running→failed transition + Restart footer**
- **Preconditions/state:** A run that fails a step (e.g. bad input). `invocationId` set.
- **Input:** Workflow with a deliberately failing step.
- **Action flow:**
  1. Dispatch; observe a phase card enter `running`.
  2. Observe a step row flip to `data-status` reflecting `failed`/`error`/`cancelled` (mapped, line 335); phase card `data-status="failed"` (line 565).
  3. On terminal failure, overall badge `data-status="failed"`; footer CTA becomes "Restart" (line 3621).
- **Expected output:** Step chip `FAILED` (line 733). Phase header chip `FAILED` (line 590). Error-recovery card `execution-triage-panel` (line 3353) with "Workflow Failed" and (once fetched) "What went wrong / Suggested fix". Footer CTA label "Restart" unless resume is offered (see RS-08).
- **Information flow:** `step_state` with `error`/`failed` → `mapBackendToPhaseStatus` "failed" (line 336) → phase `data-status`. Parent `status='failed'` → header badge + `execution-triage-panel`. Failure auto-explanation: `POST /api/workflows/explain_error` (line 1948) → `errorExplanation`.
- **Pass criteria:** At least one phase card observed transitioning into failed live; overall badge failed; footer shows Restart (or resume label per RS-08).
- **Edge/error cases:** `explain_error` 30s timeout → fallback message "Error analysis timed out…" (line 1964). `logsOpen` auto-opens on failure (line 1918).

### RS-06 · Running action bar (Pause / Stop) and paused Resume
- **Preconditions/state:** `status='running'` then `'paused'`.
- **Input:** An in-flight run.
- **Action flow:**
  1. While running, assert `panel-action-bar` with `data-status="running"` (line 3514) shows `panel-action-pause` + `panel-action-stop` (lines 3519/3527).
  2. Click Pause → parent moves to `paused`; assert bar shows `panel-action-resume` + `panel-action-stop` (lines 3539/3547).
  3. Header cancel `button-cancel-workflow-panel` (line 2538) also present while running/paused.
- **Expected output:** Correct buttons per state; buttons disabled when their handler prop is absent (`disabled={!onPause}` etc.).
- **Information flow:** `onPause`/`onCancel`/`onResume` props → parent. Action bar renders only for running/paused (line 3486).
- **Pass criteria:** Bar composition matches state; handlers fire.
- **Edge/error cases:** Terminal states render NO action bar (line 3486) — the footer handles them.

### RS-07 · Completed footer "Run again" + post-run links row
- **Preconditions/state:** `status='completed'`, `invocationId` + `runId` set.
- **Input:** A completed run.
- **Action flow:**
  1. Footer primary CTA `panel-run-again-cta` "Run again" (line 3598/3623).
  2. Post-run links row (line 3181): `button-view-results-link` (line 3187), `button-download-all-workflow-panel` (line 3201), `button-analyze-results` (line 3211), `button-download-methods-report` (line 3224). QC audit link `button-download-qc-audit` (line 3239) appears only when `availableQcProfiles.length>0 || qcGateData!==null` (line 3229).
  3. Click AI analysis → `POST /api/workflows/runs/:runId/ai/analyze` (line 1826); panel `ai-analysis-panel` shows loading→done (lines 3394–3472).
- **Expected output:** "Run again" CTA. Download-all opens `/api/invocations/:id/download-all` (line 3197) + `DownloadOutcomePrompt`. Report opens `/api/invocations/:id/methods-report` (line 3222). AI analysis panel renders summary / key findings / quality / next steps / citations / limitations.
- **Information flow:** `ai/analyze` → `analysisResult` (line 1836). Completion also auto-derives `showResults` (line 1795) → `ChatOutputAttachments` + `FindingsCard`.
- **Pass criteria:** CTA label correct, each link's endpoint fires, AI analysis reaches `done` with real prose.
- **Edge/error cases:** Buttons disabled when `!invocationId`. AI analyze error → `ai-analysis-panel` shows `analysisError` (line 3409).

### RS-08 · Failed footer — Restart / Resume-from-last / Start over / Reset-to-defaults
- **Preconditions/state:** `status='failed'`, `runId` set, `nextflowStatus.failure.suggested_action` ∈ `resume|resume_more_resources|fix_and_resume` for the resume path.
- **Input:** A failed run with a resumable failure payload vs. one without.
- **Action flow:**
  1. Read footer CTA. When `canResumeFailed` (line 1651): label = "Fix & resume" (if `fix_and_resume`) or "Resume from last step" (line 3620); a `button-start-over-failed` link also appears (line 3632).
  2. When NOT resumable: CTA label "Restart" (line 3621), fires `handleExecute`.
  3. If `showingSubmittedParams` (carryover) → `button-reset-params-to-defaults` (line 3641).
- **Expected output:** Resume path calls `/api/workflows/runs/:id/rerun` with current params (line 1657); Restart calls `onExecute`. Start-over discards cache and re-runs whole pipeline (line 3633).
- **Information flow:** `nextflowStatus.failure.suggested_action` → `canResumeFailed` (line 1651) → CTA branch. `useRunAgainParamCarryover` (line 1041) → `showingSubmittedParams`.
- **Pass criteria:** CTA label matches the failure's suggested_action; resume vs restart hit the right endpoint.
- **Edge/error cases:** No `runId` on resume → falls back to `onExecute(params)` (line 1654).

### RS-09 · QC gate blocked — two-number measured vs threshold, apply/keep/cancel
- **Preconditions/state:** `status='running'`, backend fires `qc_gate_triggered` SSE, auto-loop OFF for the phase (`autoloopMapRef` false, line 2104 — note auto-loop is locked, so this is the default path).
- **Input:** A workflow whose QC gate fails (e.g. ADMET hERG over threshold).
- **Action flow:**
  1. On `qc_gate_triggered`, panel shows `qc-gate-inline` (line 2760).
  2. Read each failure row: metric name, measured value `qc-gate-measured` (red, line 2779), operator, threshold `qc-gate-threshold` (green, line 2783).
  3. Read suggestions list (line 2791).
  4. Click `qc-gate-apply` (line 2805) → applies suggestions + `-resume` rerun; OR `qc-gate-keep` (line 2809) → proceed; OR `qc-gate-cancel-run` (line 2810) → cancel.
- **Expected output:** Two-number display measured (red) vs threshold (green). Apply calls `/api/workflows/runs/:id/rerun` with updated params (line 1629) and dismisses the gate. Keep dismisses without change (line 1705). Cancel calls `onCancel` (line 1711).
- **Information flow:** SSE `qc_gate_triggered` `{process_name, qc_metrics, failures[], suggestions[]}` → `qcGateData` (line 2094) → inline panel. Failures may be strings or `{metric,value,threshold,operator,message}` (line 135).
- **Pass criteria:** Measured/threshold rendered in correct colors with correct testids; each button performs its action.
- **Edge/error cases:** No suggestions → Apply button hidden (line 2804), only Keep/Cancel. String-form failures render as plain text (line 2772).

### RS-10 · QC gate 10s auto-proceed countdown
- **Preconditions/state:** QC gate inline shown (RS-09).
- **Input:** Same gate; no user action.
- **Action flow:**
  1. On gate appear, `qc-gate-countdown` shows "Pipeline continues in M:SS unless you act" (line 2799).
  2. Wait 10s (`QC_GATE_TIMEOUT_S`, line 1189).
- **Expected output:** Gate auto-dismisses on timeout; toast "QC gate timed out … kept current parameters and continued." (line 1674) + `onWorkflowProgress` kind `workflow.auto_proceeded` (line 1680).
- **Information flow:** `showQcInline` effect (line 1690) → `dismissQcGate('timeout')`.
- **Pass criteria:** Countdown counts down and auto-dismisses with the timeout toast.
- **Edge/error cases:** Any user click (apply/keep/cancel) clears the timer first (line 1669).

### RS-11 · QC advisory (near-threshold) step chip
- **Preconditions/state:** `status='running'`, backend fires `qc_warning` SSE for a process.
- **Input:** A run that emits near-threshold warnings.
- **Action flow:**
  1. On `qc_warning`, the step card shows `phase-step-advisory-<stepId>` (line 723) "⚠ {metric} +N".
  2. Hover to read the title tooltip listing each metric/value/threshold.
- **Expected output:** Amber advisory chip on the step, keyed by `processName`.
- **Information flow:** SSE `qc_warning` `{process_name, warnings[]}` → `qcAdvisoryByStep` (line 2158) → `qcAdvisoryByStep[processName]` → step chip (line 717).
- **Pass criteria:** Chip appears on the correct step with metric label.
- **Edge/error cases:** Empty warnings or missing `process_name` → no chip (line 2157).

### RS-12 · Per-phase QC threshold editor (edit / reset to default)
- **Preconditions/state:** A phase with `displayedQcThresholds.length>0` (derived from `/api/qc/profiles`).
- **Input:** Any workflow with QC defaults for its domain.
- **Action flow:**
  1. Expand a phase; find the `QC Gates` block (line 819).
  2. Click `qc-edit-toggle-<groupKey>` (line 827) → rows become editable number inputs.
  3. Edit a threshold value → row marked modified (accent styling, line 850).
  4. Click the reset "×" (line 855) or clear the field → reverts to default.
- **Expected output:** Each row: metric label, operator `≥`/`≤` (line 835), value/unit. Editing writes `qcOverrides[key]`; reset deletes it (line 3052).
- **Information flow:** `/api/qc/profiles` → `qcDefaults` → `displayedQcThresholds` memo (line 1556, merges default+profile+user overrides, applies domain filter). `onQcChange` (line 3052) → `qcOverrides`. Overrides flow into `handleExecute` as `__qcConfig.qcOverrides` (line 1599).
- **Pass criteria:** Toggle switches edit mode; modified rows highlighted; reset restores default; override persists into the run payload.
- **Edge/error cases:** Non-numeric input on blur → treated as reset (`onQcChange(key,null)`, line 847). Domain-mismatched metrics filtered out (line 1562).

### RS-13 · Completed QC results panel (measured vs threshold)
- **Preconditions/state:** `status='completed'`, `nextflowStatus.qc_report._all_metrics` non-empty.
- **Input:** A completed run whose backend reported QC metrics.
- **Action flow:**
  1. On completion, read `qc-report-panel` (line 2831).
  2. Each row: metric name, measured (green if pass / red if fail, line 2842), "✓/✗ thresh N".
- **Expected output:** "QC Results" panel with per-metric pass/fail coloring.
- **Information flow:** `nextflowStatus.qc_report._all_metrics` → render (line 2826).
- **Pass criteria:** Panel renders with correct pass/fail colors; hidden when no metrics.
- **Edge/error cases:** `_all_metrics` empty → panel not rendered (line 2829).

### RS-14 · Parameter override — GlobalParamsPanel renders all param types
- **Preconditions/state:** `status='idle'`, `Workflow settings` tab, `globalParamsOpen=true`.
- **Input:** A workflow with boolean, select (options), file, and number params.
- **Action flow:**
  1. Open settings strip (`button-toggle-workflow-settings`).
  2. Assert `ParameterGroup` "Required parameters" (line 2918) and "Optional parameters" (line 2929) render (or a single "Workflow parameters" group, line 2940).
  3. Verify each param type renders its control (boolean→toggle, select→dropdown, file→textarea/browse, number→input) via ParameterGroup / EditableParamRow.
  4. Edit a value → `handleParamChange` (line 1581) marks it user-overridden (line 1584).
- **Expected output:** Each type renders the correct control. `format-mismatch-warning` alert (line 2913) shows when any param carries `format_mismatch_warning`. Dataset params open `GalaxyDatasetBrowser` via `onBrowseDataset` (line 2924).
- **Information flow:** `renderedParameters` (line 1739) minus phase-pinned = `globalParams` (line 2871) → split required/optional (autoFilled counts as required-shown, line 2880) → ParameterGroup. `inferParamType` (line 176) trusts backend `type`.
- **Pass criteria:** All four control types present; edits persist and set `userOverriddenParams`.
- **Edge/error cases:** No params → "This workflow has no configurable parameters." (line 2886). Note: the per-type render lives in `ParameterGroup`/`EditableParamRow`, not this file — verify those components render toggles/dropdowns/textareas.

### RS-15 · Per-phase inline params (edit / collapse)
- **Preconditions/state:** A phase whose `phaseParams` intersect `renderedParameters` (line 559).
- **Input:** A grouped-phase workflow (e.g. cryo-EM) with phase-scoped params.
- **Action flow:**
  1. Expand a phase; read the `Parameters (N configured / N required)` header (line 619).
  2. Click `phase-params-toggle-<groupKey>` (line 630) → full editable list.
  3. Edit boolean (`.switch`, line 658), select (line 664), or text/number (line 677).
- **Expected output:** Collapsed summary row lists first 4 params or required-missing in warn color (line 638). Expanded rows editable; required-unfilled outlined in `--warn` (line 684).
- **Information flow:** `phaseRenderedParams` (line 559) → per-phase editor → `onParamChange` (line 661).
- **Pass criteria:** Toggle expands/collapses; edits flow to `params`.
- **Edge/error cases:** Note (per prior memory): nf-core/differentialabundance has no phase_group, so `phase-params-toggle` may not render (single "Steps" group). Flag as soft-skip for phaseless workflows.

### RS-16 · Step output preview (image / table / FASTA / VCF / text)
- **Preconditions/state:** A completed/failed step with `outputFiles`, `activeRunId` set.
- **Input:** A step producing a PNG, a CSV/TSV, a FASTA, a VCF, and a plain-text file.
- **Action flow:**
  1. Expand phase; on a step row click `phase-card-preview-btn-<fileName>` (line 796).
  2. `StepOutputPreview` opens (line 3296) resolving by extension.
  3. Or download via `phase-card-download-btn-<fileName>` (line 800) → `/api/workflows/runs/:id/step-file?path=…&download=1`.
- **Expected output:** Image → `<img>`; table → HTML table; FASTA/VCF/text → code block (resolution handled inside `StepOutputPreview`). The preview offers "open full step view" only when the owning step is known (line 3304).
- **Information flow:** `onPreviewFile(file, step)` (line 3048) → `previewFile`+`previewStep` → `StepOutputPreview`, fetches `/api/workflows/runs/:id/step-file?path=…` (line 801/12361).
- **Pass criteria:** Each file type renders its correct evidence-class view; download link resolves.
- **Edge/error cases:** Only first 4 output files shown inline; "+N more" chip (line 807). Preview requires `activeRunId` (line 3295).

### RS-17 · Auto-loop panel — gate table halt/advisory/pass + was→now diff
- **Preconditions/state:** `status='running'`, `autoloopEnabled` for the phase, backend fires `autoloop_gate_results` (+ `autoloop_update`) SSE. **NOTE:** `autoloopLocked=true` is hard-wired (line 3074) and the toggle to enable is commented out (lines 864–885) — see flagged section.
- **Input:** ADMET/docking/CYP/PK/cryo-EM phase that fails a gate.
- **Action flow:**
  1. On `autoloop_gate_results`, if `autoloopPhaseMatches` (line 892), `AutoLoopPanel` renders (line 895).
  2. Read `autoloop-panel` (line 465) header "Auto-Loop QC — {domain}" + phase label + level dot.
  3. Read `autoloop-gate-table` (line 487): each `GateRow` shows gate label, value (halt=red/pass=green/advisory=amber, line 380), threshold, and `actionBadge` PASS/ADVISORY/HALT (line 184).
  4. On `autoloop_update`, `autoloop-remediation-card` (line 550) shows RemediationCard rows: for confident/heuristic, the was→now diff (red strikethrough `currentParams[k]` → green `param_changes[k]`, lines 270–274).
  5. On `autoloop_phase_complete`/`autoloop_escalation`, banner `autoloop-phase-complete-banner` "Phase passed" (line 508) or escalation "Phase escalated — N gates failed" (line 518).
- **Expected output:** Gate table with correct per-action colors + badges; remediation was→now diff; pass/escalation banner.
- **Information flow:** SSE `autoloop_gate_results` → `autoLoopPanel.gateResults` (line 2171). `autoloop_update` → `remediations`+`regulatoryActions` (line 2184). `autoloop_phase_complete` → `complete` (line 2202). `autoloop_escalation` → escalated `complete` (line 2212). Advisory-only (no halt) → "N advisory warning(s) — phase will continue" (line 530).
- **Pass criteria:** Table action colors + badges correct; was→now diff visible with strikethrough→green; correct terminal banner.
- **Edge/error cases:** `regulatory_actions` present → `autoloop-regulatory-actions` (line 538) REGULATORY cards (no param tuning). Because auto-loop is locked, this whole surface requires a test hook or backend flag flip to exercise — flag it.

### RS-18 · Auto-loop manual remediation inputs + Apply & Re-run
- **Preconditions/state:** As RS-17, with a remediation whose `confidence='manual'` and `onAccept` wired (line 899).
- **Input:** A gate whose fix the system cannot infer.
- **Action flow:**
  1. RemediationCard shows editable inputs `autoloop-manual-input-<gate>-<key>` (line 296) with prompt "Enter value(s) manually…" (line 285).
  2. Enter values; click `autoloop-accept-btn` "Apply N changes & Re-run" (line 577).
- **Expected output:** `buildMergedParams` (line 444) merges auto + manual values; `onAccept(merged)` fires → `setParams` + re-execute (line 3081). Apply button hidden when no applicable changes (`canApply`, line 571).
- **Information flow:** `manualValues` state (line 429) → `buildMergedParams` → `onAcceptAutoloop` (line 3081) → `handleExecute`.
- **Pass criteria:** Manual inputs accept values; Apply merges and re-runs.
- **Edge/error cases:** Empty manual value → excluded from merge (line 451). Numeric coercion applied (line 453).

### RS-19 · Skip-dependency map (skippable / blocked / warn)
- **Preconditions/state:** `status='idle'|'pending_review'`, grouped phases (`key!=='all'`) present, `/api/nextflow/skip-analysis` returns phase info.
- **Input:** A multi-phase workflow with declared skip params + DAG dependencies.
- **Action flow:**
  1. Pre-run, `skip-dependency` (line 71) renders one `skip-phase-<id>` row per phase (line 91) with `data-skippable`/`data-skipped`.
  2. Toggle `skip-toggle-<id>` (line 108) — only enabled when `canSkip` (skippable & no blockers, line 56).
  3. Observe `skip-blocked-<id>` "Can't skip — X and Y depend on it" (line 134) for blocked phases; `skip-warn-<id>` advisory (line 146) when skipping leaves downstream empty.
- **Expected output:** Non-skippable phases show "not declared skippable" badge (line 122) + disabled checkbox. Blocked phases show amber block notice. Skipped-with-downstream-empty shows warn notice.
- **Information flow:** `/api/nextflow/skip-analysis?nextflow_path=…` (line 1141) → `skipAnalysis` → indexed by id → `SkipDependency` (line 3133). Falls back to honest "does not declare a skip parameter" when analysis absent (line 3124).
- **Pass criteria:** Skippable rows toggle; blocked rows cannot; correct notices.
- **Edge/error cases:** Skip is read-only — the resolved set is NOT wired into execution (no `onToggle` passed, line 3133). Only shown pre-run (line 3112). Flag: toggling does not affect the actual run.

### RS-20 · Lazy step fetch — loading / no-steps / idle empty states
- **Preconditions/state:** `workflowDefinition.steps` empty but `nextflow_path` present.
- **Input:** An older-session workflow with `steps={}`.
- **Action flow:**
  1. Mount; while fetching, "Loading workflow steps…" spinner (line 3013).
  2. After fetch with 0 steps → "Phases will appear here once the workflow starts." (line 3023) or failed variant (line 3021).
  3. No `nextflow_path` + idle → "No phases defined yet." (line 3029).
- **Expected output:** Correct one of three empty/loading states.
- **Information flow:** `/api/nextflow/steps` (line 1125) → `lazySteps` → `groupedPhases`. `lazyStepsFetching` gates the spinner.
- **Pass criteria:** Right state for each `(lazyStepsFetching, lazySteps, nextflow_path, status)` combination.
- **Edge/error cases:** Fetch failure sets `lazySteps={}` (line 1128) → no-steps state, not an error.

### RS-21 · Chat-progress narration relay
- **Preconditions/state:** `invocationId` set, `onWorkflowProgress` supplied, backend emits `chat_progress` SSE.
- **Input:** Any run with lifecycle narration (submitted/phase_started/completed/failed).
- **Action flow:**
  1. Dispatch run; backend emits `chat_progress` events.
  2. Assert `onWorkflowProgress` receives `{kind, friendly_message, ts, technical}` and the host appends an italic chat line.
- **Expected output:** Each lifecycle transition surfaces a friendly chat line.
- **Information flow:** SSE `chat_progress` (line 2072) → `onWorkflowProgress` callback.
- **Pass criteria:** At least submitted + completed narration lines relayed.
- **Edge/error cases:** Malformed payload logged + skipped (line 2085).

### RS-22 · Chain / proactive suggestions relay (post-completion)
- **Preconditions/state:** Completed run, backend emits `chain_suggestion` / `proactive_suggestion`.
- **Input:** A workflow with registered downstream chains.
- **Action flow:**
  1. On completion, `chain_suggestion` (line 2266) → chat line "Suggested next steps after your X run:" with per-suggestion bullets.
  2. `proactive_suggestion` (line 2286) → chat line + `quick_replies`.
- **Expected output:** Suggestion chat lines relayed with `technical.suggestions`/`quick_replies`.
- **Information flow:** SSE → `onWorkflowProgress` (lines 2275/2291).
- **Pass criteria:** Suggestion lines appear post-completion.
- **Edge/error cases:** Empty suggestion list → no relay (line 2274).

---

## §2 Step deep-view — `frontend/client/src/components/steps/step-detail.tsx`

**Purpose:** The full "step as one object" surface (spec 08). Opened via `button-full-step-view-<stepId>` (viewer line 739) into a Dialog (`full-step-view-dialog`, line 3336). Answers: what fed this → what came out (provenance), the params it actually ran with (origin-tagged, revertable), each output by evidence class with a rendered⇄raw switch, and a download of the unmodified artifact. Root testid `step-detail` (line 288). Only real mapped step data is passed (via `buildStepDetailStep`, viewer line 215) — omitted fields render honest empty states.

### SD-01 · Provenance row
- **Preconditions/state:** StepDetail mounted for a completed step.
- **Input:** A step with (or without) inputs, tool, version, duration.
- **Action flow:**
  1. Open full step view.
  2. Read `step-provenance` (line 314): "ran with [inputs] → [tool + version] → [N outputs] · duration".
- **Expected output:** Inputs as chips or "upstream step output" when empty (line 322). Tool = name or "tool not reported" (line 325); version or "(version n/a)" (line 328). "N output(s)" (line 332). Duration or "duration n/a" (line 335).
- **Information flow:** `step.inputs/tool/toolVersion/duration/outputs` props. Note `buildStepDetailStep` (viewer line 215) intentionally omits tool/version/duration/inputs (not tracked per step) → honest empty states are the EXPECTED render here.
- **Pass criteria:** Provenance row shows real values or the honest empty text; never fabricated.
- **Edge/error cases:** All optional fields absent → "upstream step output", "tool not reported", "(version n/a)", "duration n/a".

### SD-02 · Resolved params + origin badges (default / inherited / override / unknown)
- **Preconditions/state:** Step with `parameters`; `workflowDefinition` with `required_params`/`optional_params` (for defaults) and optionally `inherited_parameters`.
- **Input:** A step whose params include a default value, an overridden value, and (if backend tags it) an inherited value.
- **Action flow:**
  1. Read `param-row-<name>` (line 438) for each param.
  2. Read origin badge `param-origin-<origin>` (line 174) with `data-origin`.
  3. Read `not-default-count` "N not default" (line 423).
- **Expected output:** `default` (grey), `inherited` (amber), `override` (blue), `unknown` (dashed, when no default known — line 171). Count = override+inherited (line 284).
- **Information flow:** `resolveStepParams(step.parameters, workflowDefinition)` (line 104): value==default→default, value!=default→override, tagged inherited→inherited, no default→undefined/"unknown". `sameValue` loose-matches "5"==5 (line 140).
- **Pass criteria:** Each param's badge matches its true origin; unknown shown honestly (not guessed).
- **Edge/error cases:** No params → "No parameters were recorded for this step." (line 429).

### SD-03 · Per-row revert
- **Preconditions/state:** A param whose live value differs from `p.value` and has a `defaultValue`.
- **Input:** Edit a param row's live value (or one already differing).
- **Action flow:**
  1. When `changed` (line 434), `param-revert-<name>` link appears (line 449).
  2. Click revert → live value resets to `p.value` (line 451).
- **Expected output:** Revert link shows only when changed and a default exists; clicking restores.
- **Information flow:** `vals` state (line 263) vs `p.value`.
- **Pass criteria:** Revert appears/disappears correctly and restores the value.
- **Edge/error cases:** No `defaultValue` → no revert link even if changed (line 447).

### SD-04 · Rendered ⇄ raw toggle + RawBytesViewer
- **Preconditions/state:** A step with ≥1 output selected.
- **Input:** A text output and a binary output.
- **Action flow:**
  1. Read `rendered-raw-toggle` (line 364) with `toggle-rendered` (line 372) / `toggle-raw` (line 379).
  2. Default = rendered (`step-output-body`→`rendered-view`, line 397). Toggle raw → `raw-view` (line 392) → `RawBytesViewer` fetches `/step-file` and shows first 8000 bytes (line 230).
  3. Read the footnote (line 408): raw = "Raw first: the summary above is derived from these bytes…".
- **Expected output:** Toggle switches views; raw shows monospace bytes with "First bytes, exactly as written…" (line 233).
- **Information flow:** `raw` state → view switch. RawBytesViewer fetches `/api/workflows/runs/:runId/step-file?path=…&name=…` (line 192), `stripAnsi` applied (line 202).
- **Pass criteria:** Toggle works; raw view fetches and renders real bytes.
- **Edge/error cases:** Binary/unreadable → "Raw bytes could not be read as text (HTTP …). Download {name}" (line 218). Empty file → "— empty file —" (line 237). Loading → spinner "Loading raw bytes…" (line 210).

### SD-05 · Output tabs + evidence-class render + download
- **Preconditions/state:** Step with multiple outputs.
- **Input:** A step with e.g. an image + a table.
- **Action flow:**
  1. Read `step-output-tab-<name>` per output (line 351); first is auto-selected (line 260).
  2. Click a tab → `StepOutputPreview` remounts (key=id, line 399) and resolves the evidence-typed view.
  3. Footer download `Download {name}` → `/step-file?path=…&download=1` (line 476).
- **Expected output:** One tab per output; selected tab's rendered view via the shared evidence viewer; footer download link for the selected output.
- **Information flow:** `outputs` memo (line 251) → tabs; `selected` (line 283) → StepOutputPreview + footer.
- **Pass criteria:** Tabs render/select; rendered view delegates to StepOutputPreview; download link correct.
- **Edge/error cases:** No outputs → "This step produced no output files, or none were recorded." (line 346); no toggle/footer rendered.

### SD-06 · Re-run from here + close
- **Preconditions/state:** `onAdjustAndRerun` supplied (optional; the viewer does NOT pass it — line 3341 omits it).
- **Input:** Open the step detail.
- **Action flow:**
  1. If `onAdjustAndRerun` present → "Re-run from here" button (line 302).
  2. Close via X `Close full step view` (line 306) or Dialog dismiss.
- **Expected output:** Re-run button only when the callback is wired; close returns to the panel.
- **Information flow:** `onAdjustAndRerun` / `onClose` props (viewer sets `onClose` at line 3346, no re-run callback).
- **Pass criteria:** Close works; Re-run button absent in the current viewer wiring (flag).
- **Edge/error cases:** Because the viewer opens StepDetail without `onAdjustAndRerun` (line 3341), the "Re-run from here" button will NOT appear in production — verify it is absent, not present.

---

## §3 After-run report — `frontend/client/src/v2/AfterRunReport.tsx`

**Purpose:** The inline after-run panel embedded in the `after-run` tab (viewer line 2648). A download-report header + a hide-when-empty tab bar + a failed-run section (above the bar) for failed/cancelled runs. Root class `after-run-report` (line 221). Tab bar `role="tablist"` with `data-visible-tabs` (line 262); each tab `after-tab-<id>` (line 269). `isFailed` = status ∈ failed/cancelled/error (line 148).

### AR-01 · Tab bar composition + hide-when-empty discipline
- **Preconditions/state:** A completed run with `invocationId`+`runId`.
- **Input:** Runs with vs without methods/citations/software present.
- **Action flow:**
  1. Read `data-visible-tabs` on the tablist (line 262).
  2. Assert always-present: `after-tab-outputs`, `after-tab-findings`, `after-tab-qc`, `after-tab-params`, `after-tab-trajectory` (lines 176–188).
  3. Assert conditional: `after-tab-methods` only when `methods.hasRealContent` (line 182); `after-tab-citations` only when `citations.length>0` (line 183); `after-tab-software` only when `Object.keys(software).length>0` (line 185).
  4. Default active tab = `outputs` (line 149).
- **Expected output:** Tab order: Outputs, Findings, QC report, [Methods], [Citations], Parameters, [Software], Trajectory.
- **Information flow:** `visibleTabs` memo (line 175) driven by the fetch hooks' results.
- **Pass criteria:** Always-tabs present; optional tabs appear only with real content (no "Coming soon" placeholders).
- **Edge/error cases:** All optional endpoints 404 → only the five always-tabs show.

### AR-02 · Outputs tab — table, preview, bulk zip, reproducibility, save-to-project
- **Preconditions/state:** Completed run with output files (via `outputs` prop or `/output_files` fallback).
- **Input:** A run producing files (image, csv, text, binary).
- **Action flow:**
  1. Open Outputs tab; read `output-files-table` (line 1120) with columns Step/File/Type/actions.
  2. Preview a previewable file (`canPreview`, line 1029) → overlay renders `<img>` (image, line 1180), `<iframe>` (html/pdf, line 1183), or `TextFilePreview` (text exts, line 1186).
  3. `interactive-tools-row` (line 832) with `afterrun-launch-<tool>` (line 859) for jupyter/rstudio/cellxgene when applicable.
  4. Bulk: `download_all_zip` JobButton (line 1037), Reproducibility bundle `/reproducibility` (line 1046), Save to Project picker (lines 1064–1113).
- **Expected output:** File table per row (icon by ext, line 1018); view/dl per row. Bulk-zip polls the job then downloads. Save-to-project → `/save-to-project` (line 981), success shows "✓ Saved to {name}".
- **Information flow:** `outputs` prop (viewer builds from `nextflowStatus.s3_output_files`, line 2668) OR fallback `GET /api/workflows/runs/:id/output_files` (line 911). Preview/download via `/step-file` (line 1015). Project list via `/api/projects` (line 967).
- **Pass criteria:** Table renders real files; each preview type works; bulk + save flows fire their endpoints.
- **Edge/error cases:** 0 outputs → "No output files registered yet." or (failed) "No outputs — run did not complete successfully." (line 1007). Non-previewable ext → "Inline preview not available for .{ext}…" (line 1189).

### AR-03 · Findings tab — summary, key results, figures, download
- **Preconditions/state:** Completed run; findings job resolves to ready with summary.
- **Input:** A run whose findings analysis produces a summary + key results (+ optional figures).
- **Action flow:**
  1. Open Findings; `FindingsCard` (line 282) renders; while loading shows "Analyzing outputs…" (findings-card line 176).
  2. When ready → `findings-card` (findings-card line 207) with "Findings Summary", numbers linkable (`finding-number-link`).
  3. Optional `findings-figures-panel` (line 1596) with `finding-fig-bars`/`finding-fig-composition`/`finding-fig-qc` (lines 1512/1543/1570).
  4. Read `findings-manifest-note` contract note (line 291).
- **Expected output:** Summary paragraph with real values; key results; optional headline figures; the manifest contract note always renders (figures present or not).
- **Information flow:** `useFetchFindings` (line 558) enqueues `POST /api/jobs {kind:'findings_analysis'}` → polls `/api/jobs/:id` → `/api/jobs/:id/artifact`. FindingsCard fetches its own `/findings`.
- **Pass criteria:** Spinner resolves to a real summary; figures render when present; contract note present.
- **Edge/error cases:** `status='pending'` (still generating) → "Analysis in progress…" (findings-card line 194). No summary → card not rendered (findings-card line 200).

### AR-04 · Findings on a FAILED run — static message, no spinner
- **Preconditions/state:** `executionStatus='failed'`, findings status `pending`.
- **Input:** A failed run.
- **Action flow:**
  1. Open Findings tab on a failed run.
  2. Read FindingsCard.
- **Expected output:** "Analysis not available — workflow did not complete successfully." (findings-card line 187) — a STATIC message, NOT "Analysis in progress…" and NOT a spinner (per CLAUDE.md).
- **Information flow:** `runFailed = executionStatus in {failed,error}` (findings-card line 102) branches the pending state.
- **Pass criteria:** Static failed message; no polling spinner. This is an explicit CLAUDE.md must-not regression.
- **Edge/error cases:** If a spinner or "Analysis in progress…" appears on a failed run → BUG.

### AR-05 · Methods tab — real content vs empty
- **Preconditions/state:** Completed run; methods job resolves.
- **Input:** A run with a real methods report vs a stub.
- **Action flow:**
  1. Tab appears only when `hasRealContent` (line 182). Open it.
  2. Read `MethodsTab` (line 1203) `<pre>` body.
- **Expected output:** Real methods text in a monospace block; when stub, tab is hidden entirely.
- **Information flow:** `useFetchMethods` (line 617) enqueues `POST /api/jobs {kind:'methods_report'}` → polls → artifact text. `isStub` when empty/"No QC events recorded"/<200 chars (line 665) → `hasRealContent=false`.
- **Pass criteria:** Tab shown iff real content; body shows the text.
- **Edge/error cases:** If forced open with no content → "Methods report not available for this workflow." (line 1204).

### AR-06 · Parameters tab + Run-again-with-edits
- **Preconditions/state:** Completed run; `parameters` supplied (viewer passes `params`, line 2653).
- **Input:** A run with recorded parameters.
- **Action flow:**
  1. Open Params; read the k/v table (line 1256).
  2. Click `afterrun-run-again-params` (line 1244) → dispatches CustomEvent `biomate:run-again-with-edits` (line 1225); `afterrun-cta-toast-params` toast (line 1249).
- **Expected output:** Param table rows; run-again CTA dispatches the event (parent wire-up pending per code) + shows a toast.
- **Information flow:** `parameters` prop → entries table. CTA → `window.dispatchEvent(CustomEvent(...))`.
- **Pass criteria:** Table renders every param; CTA dispatches the event and toasts.
- **Edge/error cases:** No params → "No parameter values recorded." (line 1254); CTA not shown.

### AR-07 · Software tab — present vs empty
- **Preconditions/state:** `/software` returns ≥1 version.
- **Input:** A run whose backend emitted `versions.yml`.
- **Action flow:**
  1. Tab appears only when `software` non-empty (line 185). Open it.
  2. Read `SoftwareTab` (line 1626) tool/version table.
- **Expected output:** "Sourced from versions.yml…" + per-tool version rows.
- **Information flow:** `useFetchSoftware` → `GET /api/invocations/:id/software` (line 745; proxied at routes.ts line 4967).
- **Pass criteria:** Tab shown iff versions present; rows correct.
- **Edge/error cases:** Empty/404 → tab hidden; forced open → "No software versions recorded." (line 1628).

### AR-08 · Citations tab — present vs empty
- **Preconditions/state:** `/citations` returns ≥1 entry.
- **Input:** A workflow with registered citations (e.g. cryo-EM).
- **Action flow:**
  1. Tab appears only when citations present (line 183). Open it.
  2. Read `CitationsTab` (line 1648) list with optional DOI/URL.
- **Expected output:** Citation list items; DOI shown as "doi:…".
- **Information flow:** `useFetchCitations(workflowName)` → `GET /api/workflows/:name/citations` (line 764; proxied routes.ts line 4986).
- **Pass criteria:** Tab shown iff citations; entries link correctly.
- **Edge/error cases:** Empty/404 → tab hidden; forced open → "No citations registered." (line 1649).

### AR-09 · QC audit tab — 4-stat summary + audit log + chain-of-custody + e-sig hide
- **Preconditions/state:** `/qc-events` returns ≥1 event.
- **Input:** A run that fired QC gates.
- **Action flow:**
  1. Open QC report tab (`after-tab-qc`, always present, line 181). Root `qc-audit-tab` (line 1351).
  2. Read `qc-summary` (line 1353) grid: `qc-stat-evaluated`, `qc-stat-passed` (green), `qc-stat-autoloop` (amber), `qc-stat-manual` (line 1362–1365).
  3. Read `qc-audit-log` (line 1397): columns Timestamp/Gate/Threshold/Observed/Result/Action (lines 1407–1412). Each `qc-row-<i>`; result `qc-row-<i>-result` shows "✓ PASS" or "↻ FAIL → loop" (line 1432).
  4. Read `qc-chain-of-custody` (line 1442) SHA-256 tamper-evident text.
  5. `qc-e-signature` (line 1464) shown ONLY when `eSignature.reviewer||reviewedAt` present (hide-when-empty).
- **Expected output:** 4 stat cards; audit log with correct pass/fail treatment; chain-of-custody block; e-sig block hidden when no reviewer record.
- **Information flow:** `useFetchQcEvents` → `GET /api/invocations/:id/qc-events` (line 727; proxied routes.ts line 4943). Counts derived by `isPassedStatus`/`isAutoCorrectedStatus` (lines 1301/1307).
- **Pass criteria:** Stats sum to events.length; log rows correct; e-sig hidden without a record.
- **Edge/error cases:** `eSignature` prop is never passed by the parent (AfterRunReport does not forward one) → e-sig block ALWAYS hidden in production. Flag.

### AR-10 · QC audit tab — all-passed empty state
- **Preconditions/state:** `/qc-events` returns 0 events.
- **Input:** A clean run with no gate failures.
- **Action flow:**
  1. Open QC report tab.
  2. Read the empty state.
- **Expected output:** `qc-all-passed` "All quality gates passed" (line 1341) + "No QC thresholds were exceeded during this run…" (green check icon). NO audit table.
- **Information flow:** `events.length===0` branch (line 1324).
- **Pass criteria:** Green all-passed state, no table.
- **Edge/error cases:** This is the default for most successful runs — do not treat as "no data".

### AR-11 · Trajectory tab — honest empty state
- **Preconditions/state:** Completed run; no agent-trajectory endpoint yet.
- **Input:** Any run.
- **Action flow:**
  1. Open Trajectory (always present, line 188).
  2. Read `TrajectoryView` (line 314).
- **Expected output:** "No entries" honest empty state until the backend event log ships.
- **Information flow:** `useFetchTrajectory` → `GET /api/workflows/runs/:id/trajectory` (line 700) — probes a forward-looking route; returns [] on failure (honest empty).
- **Pass criteria:** Empty state renders; no fabricated rows.
- **Edge/error cases:** Endpoint 404 (expected today) → [] → "No entries".

### AR-12 · Download comprehensive report (dedup + toast)
- **Preconditions/state:** Completed run.
- **Input:** Any completed run.
- **Action flow:**
  1. Click `afterrun-download-report` (line 241).
  2. Observe label "Preparing…" then a `.md` blob download `biomate-run-<runId>.md` (line 210); toast "Report downloaded — check your browser" (line 215).
  3. Double-click → deduped (line 193).
- **Expected output:** Client-side markdown built by `buildFullReportMarkdown` (line 1674) stitching Dataset/Findings/Outputs/Methods/Parameters/Software/Citations/QC/Reproducibility; download triggered; dedup prevents double.
- **Information flow:** In-memory blob from the already-fetched hook data (findings/methods/qc/software/citations).
- **Pass criteria:** File downloads with the right name; toast shows; second immediate click is a no-op.
- **Edge/error cases:** Findings still pending at click → report inlines "Findings analysis is still pending…" (line 1738).

### AR-13 · Failed-run section (badge, error, autofix history, log tail)
- **Preconditions/state:** `executionStatus='failed'|'cancelled'`.
- **Input:** A failed run (optionally with autofix attempts + log tail).
- **Action flow:**
  1. `afterrun-failed-section` (line 405) renders ABOVE the tab bar.
  2. Read badge "Run failed"/"Run cancelled" (line 417) + `afterrun-run-again-failed` (line 423) → dispatches `biomate:run-again-with-edits` + `afterrun-cta-toast-failed` (line 407).
  3. If autofix tried → `afterrun-autofix-summary` (line 433) with state + attempts; toggle `afterrun-autofix-toggle` (line 466) lazy-fetches `/autofix3/sessions` (line 372).
  4. Read `afterrun-error-message` humanized (line 495); failed steps list; log tail (last 20, line 511).
- **Expected output:** Failed badge + run-again CTA; autofix narrative distinguishing "exhausted after N attempts" (line 450) vs never-ran; humanized error (no raw stack/timestamps, `humanizeNfError` line 64); log tail.
- **Information flow:** props from the viewer (`errorMessage`, `failedSteps`, `logTail`, `autofix`). Attempt history via `GET /api/galaxy/workflows/_/invocations/:id/autofix3/sessions` (line 372).
- **Pass criteria:** Section above tabs; badge/error/log-tail correct; autofix toggle fetches real attempts.
- **Edge/error cases:** No autofix → autofix box hidden (line 432). No error message → error block hidden. Cancelled → grey badge (line 417).

---

## SSE event reference (from `/api/workflows/:invocationId/events`, viewer lines 2066–2314)

| SSE event | Payload keys used | Renders |
|-----------|-------------------|---------|
| `chat_progress` | kind, friendly_message, ts, technical | Chat narration relay (RS-21) |
| `qc_gate_triggered` | process_name, qc_metrics, failures[], suggestions[], phase_key | QC gate inline (RS-09/10) |
| `qc_warning` | process_name, warnings[] | Step advisory chip (RS-11) |
| `autoloop_gate_results` | phase, domain, overall_level, passed, gates[] | Auto-loop gate table (RS-17) |
| `autoloop_update` | phase, domain, remediations[], regulatory_actions[] | Remediation cards (RS-17/18) |
| `autoloop_phase_complete` | phase, domain, outcome, level, failed_gates[] | Phase-complete banner (RS-17) |
| `autoloop_escalation` | phase, domain, failed_gates[] | Escalation banner (RS-17) |
| `step_state` | step_id, step_state, job_id | Live step `data-status` (RS-04/05) |
| `workflow_state` | workflow_state | Clears pollers on terminal (RS-04) |
| `chain_suggestion` | trigger_workflow, suggestions[] | Chain suggestion relay (RS-22) |
| `proactive_suggestion` | message, quick_replies[] | Proactive relay (RS-22) |

Server wiring: `app.get("/api/workflows/:invocationId/events")` → `sseManager.handleConnectionByInvocationId` (routes.ts line 4361).

---

## Endpoint reference (verified in `frontend/server/routes.ts`)

| UI call | Route (Node) | routes.ts line |
|---------|--------------|----------------|
| Steps (lazy) | `GET /api/nextflow/steps` | 8773 |
| Skip analysis | `GET /api/nextflow/skip-analysis` | 8790 |
| SSE events | `GET /api/workflows/:invocationId/events` | 4361 |
| Rerun / QC-resume | `POST /api/workflows/runs/:runId/rerun` | 3903 |
| Rerun-from-step | `POST /api/workflows/runs/:id/rerun-from-step` | 12496 |
| Step file / preview / raw | `GET /api/workflows/runs/:id/step-file` | 12361 |
| Output files fallback | `GET /api/workflows/runs/:id/output_files` | 11870 |
| Reproducibility bundle | `GET /api/workflows/runs/:id/reproducibility` | 12614 |
| Save to project | `POST /api/workflows/runs/:id/save-to-project` | 12651 |
| AI analyze | `POST /api/workflows/runs/:id/ai/analyze` | 12970 |
| Findings | `GET /api/workflows/runs/:id/findings` (via `/api/jobs`) | 13416 |
| Explain error | `POST /api/workflows/explain_error` | 11562 |
| QC events | `GET /api/invocations/:invocationId/qc-events` | 4943 |
| Software | `GET /api/invocations/:invocationId/software` | 4967 |
| Citations | `GET /api/workflows/:name/citations` | 4986 |
| Methods report | `GET /api/invocations/:invocationId/methods-report` | 5020 |
| Download all | `GET /api/invocations/:id/download-all` | 9383 |
| Trajectory | `GET /api/workflows/runs/:id/trajectory` | (probed; no backend route found — expected 404) |
| QC profiles | `GET /api/qc/profiles` | (fetched viewer line 2025) |

---

## Flagged as undeterminable / not testable from code as-is

1. **Auto-loop is hard-locked** (`autoloopLocked={true}`, viewer line 3074; `autoloopEnabled={autoloopMap[key]===true}`, line 3073). The enable toggle is commented out (lines 864–885). So `AutoLoopPanel` renders only if `autoloopMap[key]` is set true by some other path AND the gate SSE fires. **RS-17/RS-18 require a test hook or backend flag flip** to exercise live; otherwise the panel never mounts in production. The auto-apply branch in `qc_gate_triggered` (line 2105) is also gated on `autoloopMapRef` being true.
2. **Skip toggle is read-only** — `SkipDependency` is rendered without an `onToggle` (viewer line 3133), so toggling a skip checkbox does NOT affect execution. Test the display states only; do not assert a skipped phase actually skips.
3. **Step "Re-run from here" not wired** — the viewer opens `StepDetail` without `onAdjustAndRerun` (line 3341), so the "Re-run from here" button (step-detail line 302) will NOT appear. Verify absence.
4. **Skip-phase / skip-step / "View phase outputs" / watcher bar / progress bar / cost badge / self-correct toggle / LLM-cost cell are all commented out** (viewer lines 757–765, 915–923, 925–941, 864–885, 2544–2559, 415–443, 3273–3289). Per CLAUDE.md UX standard, tests should assert these do NOT render.
5. **`eSignature` never forwarded** — `AfterRunReport` does not pass an `eSignature` prop to `QcAuditTab`, so the e-signature block (line 1462) is always hidden. AR-09 verifies the hide, not the populated block.
6. **Trajectory endpoint does not exist yet** — `/api/workflows/runs/:id/trajectory` is a forward-looking probe (AfterRunReport line 700); expect 404 → honest "No entries". AR-11 asserts the empty state only.
7. **`/api/qc/profiles` route** was fetched by the viewer (line 2025) but not located in the grepped routes.ts window — confirm it exists on the Node server (or is proxied to Galaxy) before asserting RS-12 threshold data loads.
8. **Overall header badge is parent-driven** — `data-status` on `workflow-overall-status-badge` comes from the parent `status` prop, not directly from SSE. RS-04/05 must drive real run status through the parent (a real dispatched run), not just inject SSE events, to see the badge flip.
9. **Phase per-process status has two sources** — `nextflowStatus.processes` (line 1455) OR the `step_state` SSE path (line 2227). A live test may see either; assert the observed `data-status` transition regardless of source.
10. **`phase-params-toggle` absent for phaseless workflows** — workflows with no `phase_group` collapse into a single "Steps" group; RS-15's per-phase toggle should soft-skip there (consistent with prior BC-PARAM E2E status).
