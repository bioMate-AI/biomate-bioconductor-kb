# UX Test Plan — Cluster B: Run & Execution (Upgrade + V2)

*2026-09-11. The UX companion to the functional plan
`docs/20260909_TESTPLAN_RUNSURFACE_STEP_AFTERRUN.md`. Where that plan asked
"does the function work?", this one asks "**is the user's journey through it
smooth, honest, and visually correct?**" — scored on the 7-dimension rubric in
`docs/20260911_UXTESTPLAN_MASTER_INDEX.md`, for **both** the shipped **Upgrade**
UI and the **V2** design spec, following the master test-case shape exactly.*

**Cluster B modules (V2 spec §§ 07, 08, 12, 13, 14):**

| Module | Component | V2 spec § |
|---|---|---|
| B1 — Workflow panel (all states, param strip, QC gate incl. hERG, phase cards, real-time SSE, run-cards-by-domain) | `frontend/client/src/components/nextflow-workflow-viewer.tsx` | 07, 13 |
| B2 — Full step view + panes / output previews | `frontend/client/src/components/steps/step-detail.tsx`, `frontend/client/src/components/step-output-preview.tsx`, `frontend/client/src/components/models/inference-result.tsx` | 08, 14 |
| B3 — After-run report (Outputs/Findings/QC/Methods/Citations/Parameters/Software/Trajectory, editable methods, download) | `frontend/client/src/v2/AfterRunReport.tsx` | 07.8, 12 |

**Rubric (every function scored on all 7):** 1 Journey · 2 States & transitions
· 3 Visual fidelity vs reference · 4 Honesty · 5 Interaction & feedback ·
6 Responsiveness & a11y · 7 Cross-version Δ. **UX-pass** requires a satisfying
line on each, with the observable acceptance criteria (testids) named.

**Rules (inherited):** no mocked APIs on live steps — real backend on
`dev-public.biomate.ai`, fixture `lifeifei163361@163.com`, bypass
`x-e2e-test-token: biomate-e2e-bypass-token-dev-only`. **A skip is a fail.**
Screenshot every state and audit against the reference; do not assert-render.
Cite the v2 § each function maps to.

> **Code-drift note (read before executing).** This plan was written against the
> components as they stand on 2026-09-11, which have moved **ahead** of the
> `docs/20260909_V2GAP_RUNSURFACE_STEP_PANES.md` audit in three material ways —
> each is now a *positive* UX test, not a known gap:
> 1. **`deriveRunKind()` is implemented** (`nextflow-workflow-viewer.tsx:260`)
>    and drives the kicker `data-run-kind` (`:2530`). V2GAP §13.4 listed this
>    UNDONE. → Test the run-KIND labels (B1-RC-01).
> 2. **Per-step Rerun / adjust-params / full-step-view are wired** and terminal-
>    gated (`:768-798`); StepDetail opens from the panel (`:3376`). V2GAP §08
>    listed the step surface display-only. → Test the affordances + gating
>    (B1-PC-04, B2-SD-06).
> 3. **The pLDDT chart is wired to the 3D viewer** — `InlineStructureViewer`
>    passes `onSelectResidue={centreOnResidue}` (`step-output-preview.tsx:1104`).
>    V2GAP §08 §8.5 listed this "built but unwired". → Test chart↔3D selection
>    live (B2-SP-06).
> Conversely, several V2 elements remain **genuinely absent** (split-stage, fold,
> number→source claim card, 5-origin provenance badges, evidence-level QC row,
> DocEditor Report tab, panes choreography). Those are marked **Known gap** on
> the relevant case and, per master rule, tested as *"assert the absence is
> honest / not a broken half-state"*, never asserted present.

---

## Module B1 — Workflow panel (`nextflow-workflow-viewer.tsx`) · v2 §07, §13

Root `workflow-artifact-panel` (`:2465`). Kicker `panel-kicker` w/ `data-run-kind`
(`:2530`); name `.panel-name` (`:2531`). Overall badge
`workflow-overall-status-badge` w/ `data-status ∈ idle|running|completed|failed`
(`:2558/2567`). Tab strip `panel-tabs` (`:2662`); tabs `panel-tab-settings`,
`panel-tab-phases`, `panel-tab-after-run` (`:2619`). Footer CTA testid switches:
`button-run-workflow-panel` (idle/running/failed) ↔ `panel-run-again-cta`
(completed) (`:3633`). Tab auto-defaults by status: idle/pending_review→settings,
running/paused→phases, completed/failed→after-run (`:1099-1103`) until the user
switches.

### B1-ST-01 · Pre-run (idle) presentation — CLAUDE.md "Pre-run" standard
- **Journey:** send a workflow request in chat → card opens the panel → user reads what will run → reaches the run CTA. Should be a single scroll, no dead-end.
- **Precondition / data setup:** real chat request that routes to a live workflow (e.g. `nf-core/rnaseq`). No mocks. `status='idle'`.
- **Steps:** 1) Send request, wait for panel. 2) Read kicker + `.panel-name`. 3) Read overall badge `data-status`. 4) Confirm auto-tab = settings (`panel-tab-settings` `aria-selected=true`, `panel-settings` body visible). 5) Open the settings strip (`button-toggle-workflow-settings` `:2929`) and read the param strip.
- **Expected UX:** states=`data-status="idle"` (idle badge is `display:none` by design — present but hidden); visual=name is the real workflow name, **never "undefined"/"Untitled"** (`:2531`), kicker reads `DOMAIN · <KIND>` (see B1-RC-01); honesty=required-param chip `chip err "Required"` shows when unfilled, no fabricated values; interaction=settings strip expands on click; a11y=tab has `aria-selected`, name is a heading-level element.
- **Acceptance (UX-pass ⇔):** `.panel-name` non-empty & not "Untitled"; `panel-tab-settings` selected; param strip lists required params with a filled-or-flagged state; footer shows a run CTA (`button-run-workflow-panel`).
- **Upgrade:** as above (tabbed). **V2:** §7.1 wants the subline to read `project · version · input-provenance` (the audit anchor) — deployed subline is phase-count/description only. **Δ:** V2 formalises an audit subline; Upgrade shows a descriptive subline. **Known gap:** provenance subline (V2GAP §07 PARTIAL, P2) — assert the current subline is honest (real phase count), do not fabricate a version line.

### B1-ST-02 · Required-param hard block + "Fix now"/"Confirm" gate — CLAUDE.md "missing-required blocked alert"
- **Journey:** idle panel with an empty required param → user tries to run → is stopped with a clear reason and a one-click fix.
- **Precondition:** workflow with ≥1 empty `required_params`, `prereqChecklist.overrideAllowed` falsy.
- **Steps:** 1) Leave a required param empty. 2) Read/attempt `button-run-workflow-panel`. 3) Read the low-confidence / prereq alert if present; click `Fix now` (`:3612` region) → confirm the settings strip opens & scrolls to the field. 4) If an `executionBlockedReason` is set, read `low-confidence-countdown` (`:3602`) and `button-confirm-low-confidence-run` (`:3619`).
- **Expected UX:** states=CTA disabled while unfilled; visual=CTA carries `data-required-unfilled="N"` and a `title` "Fill in N required parameter(s)…"; honesty=the count matches the truly-empty required fields (phase-pinned excluded); interaction=Fix-now opens the editor and stops any auto-confirm timer; Confirm-anyway fires execute with `__executionOverrides.allowLowConfidence=true`; a11y=disabled reason surfaced via `title` (tooltip), not silent.
- **Acceptance:** CTA disabled with correct `data-required-unfilled`; filling the field enables it; Fix-now/Confirm behave per above; countdown (when present) ticks and auto-confirms at 10s with an "Auto-proceeded" toast.
- **Upgrade = V2** behaviourally. **V2 Δ:** §7.1 "Blocker block *next to* the primary action"; deployed renders the blocker in the body, not adjacent to the footer button. **Known gap:** blocker-adjacency (V2GAP §07 P3) — assert the blocker is discoverable & explains the remedy, note the placement Δ.

### B1-ST-03 · Running state — spinner, footer, phase-card spinner — CLAUDE.md "Running" standard
- **Journey:** click Run → immediate, unambiguous "it started" feedback in footer, badge, and at least one phase card.
- **Precondition:** a real short run dispatched (AWS Batch); `invocationId` set so the panel opens `EventSource('/api/workflows/:invocationId/events')`.
- **Steps:** 1) Click Run. 2) Assert action bar `panel-action-bar` `data-status="running"` with `panel-action-pause` + `panel-action-stop` (`:3549-3562`). 3) Assert overall badge flips to `data-status="running"`. 4) Assert ≥1 phase card `phase-group-<key>` `data-status="running"` and its step chip shows the spinner "RUNNING" (`:764`).
- **Expected UX:** states=idle→running observed live; visual=spinner animates, no frozen state; honesty=the running phase is a real one (not a heuristic fake) — if steps emit `step_state` the exact step shows RUNNING, else the progress-heuristic marks one phase and that is acceptable but must not claim a specific step done; interaction=Pause/Stop are live and labelled; a11y=spinner has an accessible "Running" text sibling (the RUNNING chip).
- **Acceptance:** within a few seconds of Run, footer/badge/≥1 phase card all read running; the RUNNING chip renders the animated `Loader2`.
- **Upgrade = V2.** **V2 Δ:** §7.9 state WORD "Running" already present; §7.1 also defines "Halted"/"Awaiting approval" words — "Halted" absent in deployed run-bar. Note the vocabulary Δ; assert the deployed word is honest.

### B1-ST-04 · **Real-time status tracking — live idle→running→terminal (CRITICAL, CLAUDE.md)**
- **Journey:** the panel must reflect live process-state changes as they happen — the user watches phases light up, they don't refresh.
- **Precondition:** a real run through the parent (not injected SSE). Short enough to finish in-session.
- **Steps (Playwright `waitForFunction`, no mocks):** 1) Pre-run: overall badge idle-hidden or phases `data-status="pending"`. 2) After Run: footer immediately "Running…"; badge `data-status="running"`. 3) Observe a `phase-group-<key>` flip `pending→running` (`:607`) as `step_state` arrives; a step row `phase-card-<stepId>` (`:742`) change `data-status`. 4) Terminal: badge `data-status="completed"`, footer becomes `panel-run-again-cta` "Run again"; completion banner `workflow-completion-banner` (`:2854`).
- **Expected UX:** states=**at least one real idle→running→terminal transition observed live** (mandatory per CLAUDE.md); visual=no stuck spinner, no phase left "running" after terminal; honesty=terminal badge matches the true run outcome; interaction=n/a (observation); a11y=`data-status` is machine-readable and mirrored by visible chips.
- **Acceptance:** the transition sequence `pending→running→completed` is captured on ≥1 phase card AND the overall badge, live. Failure path variant → B1-ST-05.
- **Upgrade = V2** (both drive `data-status` off the same SSE + parent status). **Δ:** none in the tracking mechanism; V2's split-stage would show phases + report simultaneously (deferred) but the status semantics are identical.
- **Edge:** SSE drop (`es.onerror`) closes silently and the parent's status poll still drives the badge — assert the badge still reaches terminal even if a phase card lagged.

### B1-ST-05 · Failed state — Restart footer + static triage, live running→failed
- **Journey:** a failing run must land the user on a clear "it failed, here's why, here's the next move" screen — never a stuck spinner.
- **Precondition:** a run that fails a step (bad input).
- **Steps:** 1) Observe a step row flip to a failed `data-status` and phase card `data-status="failed"` (step chip "FAILED" `:766`). 2) Overall badge `data-status="failed"`. 3) Footer CTA "Restart" (or a resume label per the failure's `suggested_action` — B1-FT-02). 4) Read `execution-triage-panel` (`:3389`) "Workflow Failed" + (once fetched) "What went wrong / Suggested fix".
- **Expected UX:** states=running→failed observed live; visual=red FAILED chips + red badge; honesty=triage text is the humanised real error (`sanitizeErrorText`), no raw stack; the error card shows "Analyzing error…" only while `explain_error` is in flight then resolves (30s timeout → honest fallback "Error analysis timed out…"); interaction=`logsOpen` auto-opens on failure; a11y=`XCircle` icon + text label.
- **Acceptance:** ≥1 phase observed transitioning to failed live; badge failed; footer Restart/resume; triage shows a static explanation, never a perpetual spinner.
- **Upgrade = V2.** **Δ:** none material.

### B1-FT-01 · Completed footer — "Run again" + post-run links row
- **Journey:** on completion the user's next actions (view results, download, analyse, methods report) are one row away.
- **Precondition:** completed run, `invocationId`+`runId`.
- **Steps:** 1) Footer `panel-run-again-cta` "Run again" (`:3633`). 2) Post-run links: `button-view-results-link` (`:3222`), `button-download-all-workflow-panel` (`:3236`), `button-analyze-results` (`:3246`), `button-download-methods-report` (`:3259`); QC audit link `button-download-qc-audit` (`:3274`) only when QC data exists. 3) Click AI-analyse → `ai-analysis-panel` (`:3430`) loading→done.
- **Expected UX:** states=each link resolves (download starts / panel opens); visual=links aligned in a single strip, run-metrics strip (`run-metrics-strip` `:3285`) shows duration/started/completed; honesty=metrics are real; per-step-cost cell is commented out → assert absent (`:3312` region is behind a flag); interaction=each click gives immediate feedback (download prompt / spinner); a11y=icon+label on every link.
- **Acceptance:** "Run again" present; every visible link fires its endpoint; AI-analysis reaches `done` with real prose (no placeholder); disabled links explain `!invocationId`.
- **Upgrade = V2.** **Δ:** none; V2 adds an editable Report tab in After-run (B3), not the footer.

### B1-FT-02 · Failed footer — Restart / Resume-from-last / Start-over / Reset-to-defaults
- **Journey:** a failure that is resumable should offer resume, not force a full restart; a carryover-params run should offer a reset.
- **Precondition:** failed run with `nextflowStatus.failure.suggested_action ∈ resume|resume_more_resources|fix_and_resume` vs. one without.
- **Steps:** 1) Resumable → CTA "Fix & resume"/"Resume from last step" + `button-start-over-failed` (`:3667`). 2) Non-resumable → CTA "Restart". 3) Carryover → `button-reset-params-to-defaults` (`:3676`).
- **Expected UX:** states=CTA label matches the failure's suggested action; visual=start-over is a secondary link, not competing with the primary; honesty=resume actually re-dispatches with `-resume`; interaction=resume hits `/rerun`, restart hits `onExecute`, start-over discards cache; a11y=reset link has a `title` explaining "showing params from your last run".
- **Acceptance:** CTA label == suggested_action mapping; resume vs restart hit the right endpoint; reset visible only when showing carried-over params.
- **Upgrade = V2.** **Δ:** none.

### B1-QC-01 · QC gate blocked — two-number measured-vs-threshold, red border, apply/keep/cancel — CLAUDE.md "QC gate" standard + hERG
- **Journey:** a run whose QC gate fails must **halt visibly** and let the user apply the fix, keep-and-proceed, or cancel — never silently pass.
- **Precondition:** a run whose gate fails. **hERG-specific:** the recent backend fix routes ADMET to `admet_standard`, so a hERG-breaching SMILES set must actually fire the gate. Set up a real ADMET run with a known hERG-liable compound; **assert the gate fires (blocked), not a silent pass.**
- **Steps:** 1) On `qc_gate_triggered`, read `qc-gate-inline` (`:2795`). 2) Per failure row: metric name, measured `qc-gate-measured` (**red** `:2814`), operator, threshold `qc-gate-threshold` (**green** `:2818`). 3) Read suggestions. 4) `qc-gate-apply` (`:2840`) → applies + `-resume` rerun; `qc-gate-keep` (`:2844`) → proceed; `qc-gate-cancel-run` (`:2845`) → cancel.
- **Expected UX:** states=gate appears mid-run, dismisses on any action; visual=`alert warn` red-bordered block, two-number display in the **correct colours** (measured red, threshold green), tabular-nums; honesty=**the hERG gate MUST fire for a breaching run** (regression guard on the admet_standard routing) — a completed-clean run for a known-liable compound is a FAIL; interaction=Apply hidden when no suggestions (Keep/Cancel only), each button single-fires; a11y=buttons labelled, danger variant on Cancel.
- **Acceptance:** measured(red)/threshold(green) render with the right testids; hERG-breaching ADMET run shows the blocked gate; each action performs its endpoint call.
- **Upgrade:** two-number + 3-action pattern present. **V2 Δ:** §7.5.1 additionally wants an **evidence-level row** (what kind of claim the threshold rests on), a **before/after suggested-change diff**, the override recorded to the **QC audit** with the overridden measurement, and override gated on **Reviewer/Owner role** ("a gate they can override silently is not a gate"). **Known gaps** (V2GAP §07 P1, PARTIAL): evidence-level row; role-gated override; override→audit surfaced in-panel. Assert the deployed 3-action triad + colours; verify a kept-current override at least shows up in the QC-audit tab (B3-AR-07c) as a non-pass row; note the missing evidence-level line + role gate — do not fabricate them.

### B1-QC-02 · QC gate 10s auto-proceed countdown
- **Journey:** an un-attended gate must not block forever — it counts down and continues with a clear record.
- **Precondition:** gate inline shown (B1-QC-01), no user action.
- **Steps:** 1) Read `qc-gate-countdown` (`:2834`) "Pipeline continues in M:SS…". 2) Wait 10s.
- **Expected UX:** states=auto-dismiss on timeout; visual=countdown visibly decrements; honesty=timeout toast "QC gate timed out … kept current parameters and continued" + `workflow.auto_proceeded` progress event (the user is told it auto-proceeded, not that they approved); interaction=any click clears the timer first; a11y=countdown is text, not colour-only.
- **Acceptance:** countdown decrements and auto-dismisses with the timeout toast.
- **Upgrade = V2.** **Δ:** none.

### B1-QC-03 · QC advisory (near-threshold) step chip
- **Precondition:** `qc_warning` SSE for a process.
- **Steps:** 1) Step card shows `phase-step-advisory-<stepId>` (`:756`) "⚠ {metric} +N". 2) Hover → title tooltip lists metric/value/threshold.
- **Expected UX:** states=amber chip on the correct step; visual=amber (not red — advisory ≠ halt); honesty=only fires with real warnings + a `process_name`; interaction=hover tooltip; a11y=`title` conveys the detail.
- **Acceptance:** chip on the right step, amber, tooltip lists metrics. **Upgrade = V2, Δ none.**

### B1-QC-04 · Per-phase QC threshold editor (edit / reset) — CLAUDE.md "QC Settings section" + "Edit→scroll"
- **Journey:** the user tunes a threshold before/after run; each metric row is name+operator+value with an editable input; edits persist into the run payload.
- **Precondition:** a phase with `displayedQcThresholds.length>0` (from `/api/qc/profiles`).
- **Steps:** 1) Expand a phase; find the QC Gates block. 2) `qc-edit-toggle-<groupKey>` (`:860`) → rows editable. 3) Edit a value → row marked modified (accent). 4) Reset "×" or clear → reverts to default. 5) **Edit→scroll:** from the completed QC results row's "Edit", the QC settings open and scroll to that metric.
- **Expected UX:** states=view↔edit toggle; visual=each row shows metric label, `≥`/`≤` operator, value/unit; modified rows highlighted; honesty=collapsed block shows **every** threshold incl. passed ones (V2GAP §07 DONE); interaction=blur non-numeric → treated as reset; a11y=number inputs labelled by the metric name.
- **Acceptance:** toggle switches edit mode; modified highlight; reset restores default; override flows into `handleExecute` as `__qcConfig.qcOverrides`; Edit→scroll lands on the right metric.
- **Upgrade = V2.** **Δ:** none material; V2's evidence-level (B1-QC-01) is the only add.

### B1-QC-05 · Completed QC results panel (measured vs threshold)
- **Precondition:** completed run, `nextflowStatus.qc_report._all_metrics` non-empty.
- **Steps:** read `qc-report-panel` (`:2866`); each row metric name, measured (green pass / red fail), "✓/✗ thresh N".
- **Expected UX:** visual=per-metric pass/fail colouring; honesty=hidden entirely when no metrics (not an empty box); a11y=✓/✗ + colour, not colour alone.
- **Acceptance:** panel renders with correct colours; absent when no metrics. **Upgrade = V2, Δ none.**

### B1-PP-01 · Parameter override — GlobalParamsPanel all types — CLAUDE.md "Parameter override" standard
- **Journey:** "Edit params" → every param type renders its native control; edits are marked user-overridden.
- **Precondition:** idle, settings tab, a workflow with boolean/select/file/number params.
- **Steps:** 1) Open settings strip. 2) Assert `ParameterGroup` "Required parameters" + "Optional parameters" (or single "Workflow parameters"). 3) Verify boolean→toggle, select→dropdown, file→textarea/browse, number→input(+range hint). 4) Edit → `handleParamChange` marks user-overridden. 5) Dataset params open `GalaxyDatasetBrowser` via `onBrowseDataset`.
- **Expected UX:** states=edited values persist across tab switches; visual=`format-mismatch-warning` alert (`:2948`) shows when a param carries a format warning; honesty="This workflow has no configurable parameters." only when truly empty; interaction=browse opens the dataset picker; a11y=each control labelled.
- **Acceptance:** all four control types render; edits set `userOverriddenParams`; empty-state honest.
- **Upgrade:** `autoFilled` badge + rationale present. **V2 Δ:** §7.4 wants a **5-origin provenance badge** (default/inherited/recommended/confirmed/edited) + expandable why+citation. **Known gap:** 5-origin badge (V2GAP §07 P1, PARTIAL) — assert the `autoFilled` badge is honest; note the taxonomy Δ; do not render a fake 5-origin badge. (The 4-origin taxonomy DOES exist in the *step* view — see B2-SD-02.)

### B1-PP-02 · Per-phase inline params (edit / collapse)
- **Precondition:** a grouped-phase workflow (e.g. cryo-EM) whose `phaseParams` intersect `renderedParameters`.
- **Steps:** 1) Expand phase; read `Parameters (N configured / N required)` header. 2) `phase-params-toggle-<groupKey>` (`:663`) → editable list. 3) Edit boolean/select/text.
- **Expected UX:** visual=collapsed summary lists first 4 params or required-missing in warn colour; required-unfilled outlined `--warn`; interaction=toggle expands/collapses; edits flow to `params`; a11y=controls labelled.
- **Acceptance:** toggle works; edits propagate.
- **Known soft-skip:** phaseless workflows (e.g. `nf-core/differentialabundance`) collapse into a single "Steps" group → `phase-params-toggle` absent. Per master rule a skip is a fail *unless* it's this documented structural absence — record it as "not applicable (no phase_group)", and cover the param editing via B1-PP-01 on that workflow instead. **Upgrade = V2, Δ none.**

### B1-PC-01 · Phase card structure + expand/collapse
- **Journey:** phases are scannable; expanding one shows its steps, params, QC, and (post-run) outputs.
- **Steps:** read `phase-group-<key>` (`:607`) header (phase status chip, `data-status`), expand, read the step list.
- **Expected UX:** visual=status chip word matches `data-status`; honesty=pending phases read "pending", never a fake done; interaction=header toggles open/closed; a11y=expandable region has a control.
- **Acceptance:** header status word == `data-status`; expand reveals steps. **Upgrade = V2, Δ:** V2 status legend (finished/running/waiting/skipped) is UNDONE (V2GAP RunSurface §) — note absence.

### B1-PC-02 · Step preview from a phase card (image/table/FASTA/VCF/text) — CLAUDE.md "Step file preview"
- **Journey:** on a completed step, one click previews an output inline, by type.
- **Precondition:** completed/failed step with `outputFiles`, `activeRunId` set.
- **Steps:** 1) `phase-card-preview-btn-<fileName>` (`:829`) → `StepOutputPreview` opens. 2) Or `phase-card-download-btn-<fileName>` (`:835`) → downloads. Covered in depth by B2-SP-*.
- **Expected UX:** image→`<img>`, table→HTML table, FASTA/VCF/text→code block; honesty=only first 4 files inline + "+N more" chip; preview needs `activeRunId`; a11y=preview/download buttons labelled.
- **Acceptance:** each type renders its evidence-class view; download resolves. **Upgrade = V2, Δ none** (both delegate to `step-output-preview.tsx`).

### B1-PC-03 · Auto-loop panel — gate table halt/advisory/pass + was→now diff — CLAUDE.md "Auto-loop panel"
- **Journey:** when a domain phase auto-remediates, the user sees the gate table (colour-coded), the was→now param diff, and a pass/escalation banner.
- **Precondition:** `autoloop_gate_results`/`autoloop_update`/`autoloop_phase_complete`/`autoloop_escalation` SSE for an autoloop-enabled phase.
- **Steps:** 1) `autoloop-panel` header + level dot. 2) `autoloop-gate-table`: `GateRow` value coloured halt=red/pass=green/advisory=amber + `actionBadge` PASS/ADVISORY/HALT. 3) `autoloop-remediation-card`: was→now diff (red strikethrough `currentParams[k]` → green `param_changes[k]`). 4) `autoloop-phase-complete-banner` "Phase passed" or escalation "Phase escalated — N gates failed".
- **Expected UX:** states=gate→remediation→banner; visual=per-action colours + badges correct; was→now diff legible; honesty=advisory-only shows "N advisory warning(s) — phase will continue" (no fake halt); regulatory actions show REGULATORY cards (no param tuning); interaction=n/a (observation) unless manual (B1-PC-05); a11y=badge text + colour.
- **Acceptance:** table action colours/badges correct; was→now diff strikethrough→green; correct terminal banner.
- **KNOWN LOCK (must flag):** `autoloopLocked=true` is hard-wired (`:905` region toggle commented out); `AutoLoopPanel` mounts only if `autoloopMap[key]===true` AND the gate SSE fires. **This surface requires a backend flag flip / test hook to exercise live.** Per master rule, if it can't be reached it is **untested, not passed** — record it as blocked and route the QC-halt UX coverage through B1-QC-01 (the inline gate, which is the default un-locked path). **Upgrade = V2** where reachable; V2 §7.2 also requires auto-loop always-visible + cap-3 (V2GAP DONE).

### B1-PC-04 · Per-step affordances — Details / Rerun / Params, terminal-gated  *(newly wired — was V2GAP §08 UNDONE)*
- **Journey:** on a finished step the user can open its full view, re-run it, or (on a not-yet-done step) adjust its params — the affordances appear only when they make sense.
- **Precondition:** a completed run with per-step status.
- **Steps:** 1) On a DONE or FAILED step, assert `button-full-step-view-<stepId>` "Details" (`:772`) and `button-run-step-<stepId>` "Rerun" (`:780`) render. 2) On a not-running/not-done step with params, assert `button-adjust-step-<stepId>` "Params" (`:787`). 3) Confirm the Skip button does **NOT** render (commented out `:790-798`).
- **Expected UX:** states=affordances gated on terminal status (`isDone || isFailed` for Details/Rerun; `!isRunning && !isDone` for Params); visual=small ghost buttons in the step head `.actions`; honesty=Skip absent (no backend API) — per CLAUDE.md assert non-render, don't show a dead button; interaction=Details opens `full-step-view-dialog`, Rerun triggers `onRun`, Params opens the adjust flow; a11y=each button has a title.
- **Acceptance:** Details/Rerun present on terminal steps only; Params on non-terminal-with-params only; Skip absent.
- **Upgrade = V2 intent (§8 step-as-object).** **Δ:** the step surface is now interactive (V2GAP had it display-only) — a UX improvement toward §08.

### B1-PC-05 · Auto-loop manual remediation inputs + Apply & Re-run
- **Precondition:** an autoloop remediation whose `confidence='manual'` (subject to the same B1-PC-03 lock).
- **Steps:** enter values in `autoloop-manual-input-<gate>-<key>`; click `autoloop-accept-btn` "Apply N changes & Re-run".
- **Expected UX:** interaction=`buildMergedParams` merges auto+manual, re-executes; Apply hidden when no applicable changes; honesty=empty manual value excluded from merge; a11y=inputs labelled by gate/key.
- **Acceptance:** manual inputs accept values; Apply merges + re-runs. **Blocked by the same lock as B1-PC-03 — record accordingly. Upgrade = V2, Δ none.**

### B1-SK-01 · Skip-dependency map (skippable / blocked / warn) — display-only
- **Precondition:** idle/pending_review, grouped phases, `/api/nextflow/skip-analysis` returns phase info.
- **Steps:** read `skip-dependency` / `skip-phase-<id>` rows with `data-skippable`/`data-skipped`; toggle `skip-toggle-<id>` (only enabled when `canSkip`); read `skip-blocked-<id>` "Can't skip — X and Y depend on it" and `skip-warn-<id>` advisory.
- **Expected UX:** states=three-state (skippable/blocked/warn); visual=non-skippable shows "not declared skippable" + disabled checkbox; honesty=falls back to "does not declare a skip parameter" when analysis absent; **skip is READ-ONLY — no `onToggle` wired (`:3133` region) so toggling does NOT affect the run** — per master rule assert the display states, do NOT assert a phase actually skips; a11y=blocked reason as text.
- **Acceptance:** skippable rows toggle in-UI; blocked rows can't; correct notices; skipped-with-empty-downstream shows the warn.
- **Upgrade:** three-state DONE (V2GAP §13.5 / §2.5.1). **V2 Δ:** §2.5 wants during-run skip + "never red" SKIPPED styling + a QC-audit skip record — not all confirmed. Note the Δ; the read-only nature is the honesty caveat.

### B1-RC-01 · Run-cards-by-domain — run KIND label  *(newly implemented — was V2GAP §13.4 UNDONE)* · v2 §13
- **Journey:** a design/training/sandbox run must not read as a generic "Workflow" — the kicker names the true run kind so the panel can't contradict the composer's lane preview.
- **Precondition:** route four runs: a design run (e.g. `de_novo`/`molecular_design`), a training run (`model_training`), an ad-hoc compute (`data_analysis`/`sandbox`), and a plain pipeline (RNA-seq).
- **Steps:** read `panel-kicker` `data-run-kind` (`:2530`) and the visible kicker text for each. `deriveRunKind()` (`:260`) resolves: `design*`→"Design run", `sandbox|adhoc|compute`→"Ad-hoc · sandbox", `train*`→"Training run", else "Workflow".
- **Expected UX:** visual=kicker reads `DOMAIN · <KIND>` (`:2516`) where KIND is the routed kind, uppercased; honesty=a non-workflow run **never reads "WORKFLOW"** (the core §13 parity rule); interaction=n/a; a11y=`data-run-kind` machine-readable + visible text.
- **Acceptance:** all four runs show the correct `data-run-kind` and matching visible kicker; the design/training/sandbox cases are NOT "WORKFLOW".
- **Upgrade:** now implements the KIND override (ahead of the V2GAP audit). **V2 Δ:** §13.2 also wants the whole card (slots/params/phases/clarifications) to be a function of `wfFor(dom,mod)` — deployed reads one `workflowDefinition`. **Known gap:** per-domain card shape + sandbox card (V2GAP §13 P1/P2 UNDONE). Assert the KIND label is correct; note the deeper per-domain-shape Δ.

### B1-AG-01 · Human approval gate — pauses, never times out · v2 §7.6
- **Journey:** a person-gated action (irreversible / cost / threshold crossed) must pause the run and present what/why/cost/measured/who with Approve / Deny / Ask-reviewer — and it must WAIT, not auto-proceed.
- **Precondition:** a run that reaches `status==='pending_review'` so `<ApprovalGate>` mounts (V2GAP §7.6 DONE, `nextflow-workflow-viewer.tsx` approval-gate region).
- **Steps:** 1) Read the approval card: the action in one line (what), the reason (why — threshold/overwrite/irreversibility), the cost (money/time/versions — not rounded away), the measured rows (same 3 cols as the QC gate), and who (whether this user may approve). 2) Read the state word "Awaiting approval". 3) Confirm Approve / Deny / Ask-a-reviewer buttons.
- **Expected UX:** states=run frozen at "Awaiting approval"; visual=measured rows match the QC-gate 3-column layout; honesty=**the card describes the action at the point the run ACTUALLY paused (§7.6 truthfulness rule) — a plausible-but-different action is worse than no gate**; the cost is real, not rounded away; interaction=**the gate NEVER proceeds on a timeout** (§7.6) — assert no countdown, no implied consent (contrast with the QC gate's 10s auto-proceed, B1-QC-02, which is a machine gate); a11y=3 decision buttons labelled.
- **Acceptance:** approval card shows what/why/cost/measured/who; state word "Awaiting approval"; **no timeout / no auto-advance**; Approve/Deny/Ask-reviewer present.
- **Upgrade:** ApprovalGate DONE (ahead of / abreast V2). **Δ:** parity — this is a v2 §7.6 addition already deployed. If the run never reaches `pending_review` in-session, record as **untested/blocked**, not passed.

### B1-XR-01 · Chat + panel presentation sync — CLAUDE.md "Chat + Workflow Panel Presentation" standard
- **Journey:** the chat message and the right panel must agree — same workflow name, consistent state, a structured pre-exec summary, a workflow card below the AI text.
- **Precondition:** a real workflow request in chat.
- **Steps:** 1) Read the AI chat message: correct workflow name (not "undefined"), a bulleted pre-execution summary (steps/outputs), no hallucinated params, correct intent. 2) Read the workflow card below the text: name + domain badge + step count + "In panel" badge when open. 3) Cross-check the card title == `.panel-name`.
- **Expected UX:** honesty=chat name == panel name; params mentioned map to real workflow params; if the user asked ADMET the message says ADMET; visual=card appears AFTER the text; a11y=card is a labelled region.
- **Acceptance:** chat and panel names match; summary is structured (not a vague one-liner); "In panel" badge shows when the panel is open; no "undefined" anywhere.
- **Upgrade = V2.** **Δ:** none in this standard.

---

## Module B2 — Full step view + panes / output previews · v2 §08, §14

**Full step view** (`steps/step-detail.tsx`): root `step-detail` (`:288`), opened
from `button-full-step-view-<stepId>` into `full-step-view-dialog` (`:3371`).
Provenance `step-provenance` (`:314`); origin badge `param-origin-<label>` w/
`data-origin` (`:174`); output tabs `step-output-tab-<name>` (`:351`);
rendered/raw `rendered-raw-toggle` / `toggle-rendered` / `toggle-raw` (`:364-378`);
`step-output-body` → `raw-view`/`rendered-view` (`:390-397`); `not-default-count`
(`:422`); `param-row-<name>` (`:438`); `param-revert-<name>` (`:449`).
**Preview** (`step-output-preview.tsx`): the evidence-class router
`resolveViewer` (`:88`); `InlineStructureViewer` w/ pLDDT chart wired to 3D
(`:1104`); `parsePlddtFromPdb` (`:968`); "Full step view" affordance
`open-full-step-view` (`:805`); `inline-structure-viewer` w/
`data-has-confidence` (`:1080`); DL sidecars `dl-json-preview` (`:670`).

### B2-SD-01 · Provenance row — honest empty fields
- **Journey:** the step view opens with a one-line "what fed this → what tool → how many outputs → how long".
- **Precondition:** completed step opened via Details.
- **Steps:** read `step-provenance` (`:314`): inputs, tool+version, N outputs, duration.
- **Expected UX:** honesty=`buildStepDetailStep` intentionally omits tool/version/duration/inputs (not tracked per step) → the row **must** show the honest empties: "upstream step output", "tool not reported", "(version n/a)", "duration n/a" — these are the EXPECTED render, not a bug; visual=chips for inputs when present; a11y=text, not icon-only.
- **Acceptance:** provenance shows real values OR the honest empty text; **never a fabricated tool/version/duration**.
- **§8.8 per-state note:** the deployed step view is largely stateless; the spec's per-state copy — Skipped "This step was skipped. Nothing ran, so there is no output to look at." (neutral, **never red**) and Failed "log positioned at the failure, not the top" — is a **Known gap** (V2GAP §08 UNDONE). Assert the honest empties above; do not assert per-state variants present.
- **Upgrade = V2 (§8.2/8.3).** **V2 Δ:** §8.2 wants a "step n of N" + phase-letter header and dataset-*object* input chips (openable) — deployed shows "Full step view" label + string inputs. **Known gap:** step-position header + openable dataset chips (V2GAP §08 UNDONE/PARTIAL). Assert honest empties; note the Δ.

### B2-SD-02 · Resolved params + origin badges (default/inherited/override/unknown)
- **Journey:** the user can see, per param, whether the run used the default, an inherited value, an explicit override, or an unknown-origin value.
- **Precondition:** a step with `parameters`; `workflowDefinition` supplying defaults.
- **Steps:** read `param-row-<name>` (`:438`), origin badge `param-origin-<origin>` w/ `data-origin` (`:174`), and `not-default-count` "N not default" (`:422`).
- **Expected UX:** visual=`default` grey, `inherited` amber, `override` blue, `unknown` dashed; honesty=**unknown shown honestly when no default is known — never guessed as default**; count == override+inherited; `sameValue` loose-matches "5"==5 so a formatting-only diff isn't flagged as override; a11y=badge has text + `data-origin`.
- **Acceptance:** each param's badge matches its true origin; unknown honest; empty → "No parameters were recorded for this step."
- **Upgrade:** 4-origin taxonomy present here (this is where the origin story is honoured, vs the global panel's `autoFilled` — cross-ref B1-PP-01). **V2 Δ:** §7.4/§8.4 want a 5th origin (recommended/confirmed) + reason+citation; deployed has 4. Note the Δ.

### B2-SD-03 · Per-row revert
- **Precondition:** a param whose live value differs from `p.value` with a `defaultValue`.
- **Steps:** when changed, `param-revert-<name>` (`:449`) appears; click → resets to `p.value`.
- **Expected UX:** interaction=revert shows only when changed AND a default exists; clicking restores; honesty=no revert link when no `defaultValue` even if changed; a11y=link labelled per-param.
- **Acceptance:** revert appears/disappears correctly and restores. **Upgrade = V2 (§8.4), Δ:** V2 wants a batched "apply + re-run downstream" button; deployed edits are live (no batch apply). Note Δ.

### B2-SD-04 · Rendered ⇄ raw toggle + RawBytesViewer — the honesty control
- **Journey:** the user can flip any output between its rendered view and its exact raw bytes, and is told the rendered view is *derived from* those bytes.
- **Precondition:** a step with ≥1 output (a text output + a binary output).
- **Steps:** 1) `rendered-raw-toggle` (`:364`); default `rendered-view` (`:397`). 2) `toggle-raw` (`:378`) → `raw-view` (`:392`) → RawBytesViewer fetches `/step-file` first 8000 bytes. 3) Read the footnote "Raw first: the summary above is derived from these bytes…".
- **Expected UX:** states=toggle switches views; loading→"Loading raw bytes…"; visual=monospace bytes "First bytes, exactly as written…"; honesty=**the "Raw first…" copy is the core §8.5 honesty promise — assert its presence**; binary/unreadable → "Raw bytes could not be read as text (HTTP …). Download {name}"; empty → "— empty file —"; a11y=toggle is a labelled 2-position control.
- **Acceptance:** toggle works; raw view fetches + renders real bytes; the "Raw first…" footnote is present. **Upgrade = V2 (§8.5), Δ:** none — this is a DONE strength in both.

### B2-SD-05 · Output tabs + evidence-class render + download
- **Precondition:** a step with multiple outputs (e.g. image + table).
- **Steps:** read `step-output-tab-<name>` per output (first auto-selected); click a tab → `StepOutputPreview` remounts and resolves the evidence view; footer download `Download {name}` → `/step-file?...&download=1`.
- **Expected UX:** visual=one tab per output; selected tab's rendered view via the shared evidence viewer; honesty=no outputs → "This step produced no output files, or none were recorded." (no toggle/footer); a11y=tabs labelled by filename.
- **Acceptance:** tabs render/select; rendered view delegates to `StepOutputPreview`; download link correct.
- **Upgrade = V2 (§8.2), Δ:** V2 wants an evidence badge on each tab — deployed shows filename+icon, no badge. Note Δ.

### B2-SD-06 · "Re-run from here" — verify ABSENT in the panel-opened dialog
- **Journey:** the §8.7 re-run-from-here affordance requires `onAdjustAndRerun`; the panel opens StepDetail WITHOUT it (`:3376-3382`).
- **Steps:** open Details from the panel; assert the "Re-run from here" button (step-detail `:302` region) does **NOT** appear; close via `Close full step view`.
- **Expected UX:** honesty=**assert absence** — a dead re-run button would be a broken half-state; the panel intentionally omits the callback; interaction=Close returns to the panel; a11y=close labelled.
- **Acceptance:** Re-run-from-here NOT present in the panel dialog; Close works.
- **Upgrade = V2 wiring today.** **Known gap:** §8.7 was→now diff + cache arithmetic + side-by-side alternate output all UNDONE (V2GAP §08). Note; don't assert present.

### B2-SP-01 · Image preview + lightbox
- **Precondition:** a step output PNG/JPG/SVG.
- **Steps:** preview → `InlineImageViewer` renders `<img>`; click → lightbox; Esc/click-out closes.
- **Expected UX:** visual=image scaled, "Click to enlarge" hint, hover ZoomIn overlay; honesty=real image bytes (not a placeholder); interaction=lightbox open/close; a11y=`alt`=filename, close button `aria-label`.
- **Acceptance:** `<img>` renders; lightbox opens/closes. **Upgrade = V2, Δ:** §8.5 wants fit/100/200/full-bleed image-stage controls — deployed has lightbox only. Note Δ.

### B2-SP-02 · Table preview (CSV/TSV/JSON/STAR)
- **Steps:** preview a CSV/TSV → `InlineTableViewer`/`TableGrid`; a STAR/RELION file → parsed particle table; a JSON array → keyed table.
- **Expected UX:** visual=sticky header, max 200 rows, "Showing first 200 of N"; honesty=empty → "Empty file"; delimiter auto-detected; a11y=`<table>` semantics.
- **Acceptance:** each table type renders with headers + row cap notice. **Upgrade = V2, Δ:** §8.5 wants per-column stats in the quantitative viewer — absent (V2GAP §08 P1 PARTIAL). Note gap.

### B2-SP-03 · FASTA/FASTQ sequence preview
- **Steps:** preview → `InlineSequenceViewer` lists ≤20 records (id + first 200 bp + length).
- **Expected UX:** honesty="No sequences found" when none; visual=monospace, truncation "…"; a11y=record ids legible.
- **Acceptance:** records render with id/seq/length. **Upgrade = V2, Δ none.**

### B2-SP-04 · VCF + annotation (BED/GFF) preview
- **Steps:** VCF → `InlineVcfViewer` (header from `#CHROM` or default 8-col); BED/GFF → `InlineAnnotationViewer` with the right column set.
- **Expected UX:** honesty="Empty VCF" when none; row cap 100; a11y=table.
- **Acceptance:** VCF + BED/GFF render as tables. **Upgrade = V2, Δ none.**

### B2-SP-05 · Text/log preview with tail toggle
- **Steps:** preview a log → `InlineTextViewer`; when >50 lines, "Show tail (last 80)"/"Show from start" toggle; ANSI stripped.
- **Expected UX:** interaction=tail toggle; visual="… N lines above …" marker; honesty=real bytes; a11y=toggle labelled.
- **Acceptance:** tail toggle switches; ANSI stripped. **Upgrade = V2, Δ:** §8.5 "console follow-tail" during a *running* step is not implemented (step view is stateless) — note.

### B2-SP-06 · Structure viewer + pLDDT chart ↔ 3D selection  *(newly wired — was V2GAP §08 §8.5 UNDONE)*
- **Journey:** a predicted structure opens the 3D view **with** its per-residue confidence chart; clicking a residue in the chart centres the 3D camera — one selection, not two.
- **Precondition:** a step output PDB whose B-factor column carries pLDDT (0–100). Set up a real AlphaFold/ESMFold/Boltz output (or use `models/inference-result.tsx` result which threads pLDDT→3D).
- **Steps:** 1) Preview the `.pdb` → `inline-structure-viewer` (`:1080`) renders 3Dmol cartoon. 2) Assert `data-has-confidence="true"` and the `PlddtChart` renders beside the 3D view (`:1103`). 3) Click a residue band in the chart → assert the 3D view re-styles + zooms to that residue (`centreOnResidue`, `:1055`). 4) Style buttons (cartoon/stick/sphere/line) switch representation.
- **Expected UX:** states=loading→ready; fallback to text dump if WebGL fails (honest, not blank); visual=chart bands coloured by confidence, 3D + chart shown together (the §8.5 promise); honesty=`parsePlddtFromPdb` returns [] when values are outside 0–100 (a crystal structure's real B-factors) → **no chart is shown rather than a fabricated confidence chart** (`data-has-confidence="false"`); interaction=chart click drives the 3D camera live; a11y=style buttons labelled, chart residue selection keyboard-reachable if supported.
- **Acceptance:** for a real pLDDT PDB: chart renders, `data-has-confidence="true"`, residue click centres the 3D view; for a non-confidence PDB: no chart, `data-has-confidence="false"`. This is the §8.5 core-claim test — the confidence view must be honest.
- **Upgrade:** wired (ahead of the V2GAP audit). **V2 Δ:** §8.5 also wants a PAE heatmap shown together — `PaeHeatmap` is built but not wired into the structure viewer. **Known gap:** PAE integration. Assert pLDDT↔3D; note PAE Δ.
- **inference-result.tsx cross-ref:** if the step is a model inference, verify the same pLDDT→3D selection wiring holds in `models/inference-result.tsx` (the models surface reuses the confidence→structure link).

### B2-SP-07 · Binary / interactive-tool fallbacks (RDS, h5ad, density, cryo binary)
- **Steps:** RDS → `RObjectPreview` (sidecar summary if present, else "Open in RStudio"); h5ad/loom → `SingleCellPreview` (CellxGene/Jupyter); MRC/map → `DensityPreview` (3-axis slices); .cs/.csg → download-only.
- **Expected UX:** honesty=binary formats offer the right interactive tool, never a broken inline render; RDS sidecar shows real class/dims/assays or falls back honestly; a11y=launch buttons labelled.
- **Acceptance:** each binary type routes to its correct launcher/viewer; download-only for un-renderable binaries. **Upgrade = V2** (deployed EXCEEDS the reference with cryo FSC/motion/CTF viewers — V2GAP note). **Δ:** deployed adds cryo chart viewers not in the spec.

### B2-SP-08 · "Open full step view" affordance from a preview
- **Steps:** in a preview that receives `onOpenFullStepView`, assert `open-full-step-view` (`:805`) button opens StepDetail; assert it is absent when the owning step is unknown.
- **Expected UX:** interaction=opens the dialog; honesty=absent when no owning step (`:3339-3340` gate); a11y=titled button.
- **Acceptance:** button opens StepDetail when the step is known; absent otherwise. **Upgrade = V2, Δ none.**

### B2-PANE-01 · Panes & navigation — v2 §14 (mostly deferred — honest-absence tests)
- **Journey:** the run panel and chat share the stage; §14.1 wants collapse-to-rail, a "Run panel" reveal chip, <880px auto-collapse, width persistence, and a Reveal control on any collapsed pane.
- **Steps:** 1) Resize the panel via the grip (min 320px). 2) Reload → assert width persistence. 3) Narrow the viewport below 880px. 4) Close the panel → look for a reveal chip.
- **Expected UX:** honesty=**assert what IS honest, do not fabricate the missing choreography**; interaction=grip resizes; a11y=grip is keyboard-operable if supported.
- **Acceptance / Known gaps (V2GAP §14, mostly UNDONE/PARTIAL):**
  - Grip resize to 320px: PARTIAL present → **test it works.**
  - Width persistence: only open/closed persists, **width does NOT** → assert current behaviour honestly (reload resets width); do not claim persistence.
  - Chat collapse-to-46px-rail, "Run panel" reveal chip, <880px auto-collapse, reveal-swap, Reveal control: **UNDONE** → assert they are absent (no half-broken rail); note each as a deferred §14 gap.
  - §14.2 "An artefact is a file object, not a picture of one": DONE (`step-output-preview.tsx:482` "the artifact itself, unmodified" + external-link) → **test the copy + external-link present.** versions/ask-to-edit/open-in-Files affordances: absent → note.
- **Upgrade ≈ V2-partial.** **Δ:** the split-stage + panes choreography is the largest deferred V2 area; treat as conditional-on-adopting-the-split, not a bug.

---

## Module B3 — After-run report (`v2/AfterRunReport.tsx`) · v2 §07.8, §12

Root `.after-run-report` (`:222`). Download `afterrun-download-report` (`:242`).
Failed section `afterrun-failed-section` (`:406`) ABOVE the tab bar. Tablist w/
`data-visible-tabs` (`:263`); tabs `after-tab-<id>` (`:270`) for
outputs/findings/qc/methods/citations/params/software/trajectory. Default tab
`outputs` (`:150`). `isFailed` = status ∈ failed/cancelled/error (`:149`).

### B3-AR-01 · Tab bar composition + hide-when-empty discipline
- **Journey:** the user sees only tabs that have real content — no "Coming soon" dead tabs.
- **Precondition:** completed run; compare a run with vs without methods/citations/software.
- **Steps:** read `data-visible-tabs` (`:263`). Always: outputs, findings, qc, params, trajectory. Conditional: methods (`methods.hasRealContent`), citations (`citations.length>0`), software (`Object.keys(software).length>0`). Default active = outputs.
- **Expected UX:** visual=tab order Outputs, Findings, QC report, [Methods], [Citations], Parameters, [Software], Trajectory; honesty=**optional tabs appear only with real content — a stub methods report (<200 chars / "No QC events recorded") hides the tab, not shows a placeholder**; interaction=tabs switch on click; a11y=`role="tablist"`/`role="tab"` + `aria-selected`.
- **Acceptance:** always-tabs present; optional tabs iff real content; no placeholder tab bodies.
- **Upgrade:** 8 tabs. **V2 Δ:** §7.8/§12 add an **editable Report/DocEditor tab as the FIRST after-run tab**. **Known gap:** no DocEditor Report tab (V2GAP §07/RunSurface UNDONE) — the editable-methods increment (B3-AR-05) is the partial delivery. Note the Δ.

### B3-AR-02 · Outputs tab — table, preview, bulk zip, reproducibility, save-to-project — CLAUDE.md "Outputs" standard
- **Journey:** every output file is listed; previewable ones preview inline; the user can bulk-download, grab a reproducibility bundle, or save to a project.
- **Precondition:** completed run with files (image/csv/text/binary).
- **Steps:** 1) `output-files-table` (`:1121`) Step/File/Type/actions. 2) Preview a previewable file → overlay `<img>`/`<iframe>`/`TextFilePreview` (`:1181-1188`). 3) `afterrun-interactive-tools-row` (`:833`) with `afterrun-launch-<tool>` (`:860`). 4) Bulk: `download_all_zip` JobButton (`:1038`), Reproducibility (`:1046`), Save-to-Project picker (`:1064-1113`).
- **Expected UX:** states=zip JobButton polls then downloads; visual=icon-by-ext, view/dl per row; honesty=**0 outputs → "No output files registered yet." OR (failed) "No outputs — run did not complete successfully."** (`:1007-1010`); non-previewable ext → "Inline preview not available for .{ext}…"; interaction=Save → "✓ Saved to {name}"; a11y=table + labelled buttons.
- **Acceptance:** table lists real files; each preview type works; bulk + save flows fire their endpoints; empty state honest.
- **Upgrade = V2 baseline.** **V2 Δ:** RunSurface `OutputGrid` wants per-output notes (localStorage), search, thumb-by-kind grid — deployed is a list table. **Known gap** (V2GAP RunSurface PARTIAL). Note Δ.

### B3-AR-03 · Findings tab — summary, key results, figures, download — CLAUDE.md "Findings tab" standard
- **Journey:** the user reads a real summary with real numbers, optional headline figures, and a report download — spinner resolves, never hangs.
- **Precondition:** completed run whose findings job resolves ready with a summary.
- **Steps:** 1) `FindingsCard` (`:283`) — while loading "Analyzing outputs…" (findings-card `:176`). 2) Ready → `findings-card` with "Findings Summary", numbers as `finding-number-link`. 3) Optional `findings-figures-panel` (`:1717`): `finding-fig-bars`/`finding-fig-composition`/`finding-fig-qc`. 4) `findings-manifest-note` contract note (`:292`) always present.
- **Expected UX:** states=spinner resolves to real prose (not stuck); visual=summary paragraph + key results + optional figures; honesty=**figures are data-driven from the manifest (never LLM); the manifest contract note renders whether figures are present or not; numbers link to their output** (finding-number-link); interaction=number links open the output; a11y=figures have text values + `aria-label` (the QC ring has `aria-label="{pct}% retained"`).
- **Acceptance:** spinner→real summary; figures render when present + carry a "from {source_file}" caption; contract note always present; a "Download report" path is reachable (B3-AR-08).
- **Upgrade = V2.** **V2 Δ:** §7.8/§8.6 want **every number to be an inline anchor to its output + a number→source claim card** — deployed figures carry `source_file` but the per-number claim card is UNDONE (V2GAP §08 §8.6 P1). Note the Δ; assert the figure-level source caption is honest.

### B3-AR-04 · Findings on a FAILED run — static message, NO spinner (CLAUDE.md must-not-regress)
- **Journey:** a failed run's Findings tab must say, statically, that analysis is unavailable — never poll or spin.
- **Precondition:** `executionStatus='failed'`, findings status pending.
- **Steps:** open Findings on a failed run; read FindingsCard.
- **Expected UX:** honesty=**"Analysis not available — workflow did not complete successfully." (findings-card `:187`) — a STATIC message, NOT "Analysis in progress…" (`:194`) and NOT a spinner** (`runFailed` branch, findings-card `:102/184`); states=terminal, no polling; a11y=plain text.
- **Acceptance:** static failed message; no polling spinner. **A spinner or "Analysis in progress…" on a failed run = BUG.** This is the explicit CLAUDE.md regression guard.
- **Upgrade = V2, Δ none.**

### B3-AR-05 · Methods tab — editable methods (Edit → edit → Save downloads md → Done) + mid-edit-guard  · v2 §12
- **Journey:** the methods report is an editable file object: the user enters edit mode, revises the AI prose, saves an edited markdown, and exits — and a background source refresh must NOT clobber their in-progress edits.
- **Precondition:** completed run whose methods job resolves with real content (tab present only when `hasRealContent`).
- **Steps:** 1) `methods-tab` (`:1268`) default read-only `methods-readonly` (`:1327`). 2) `methods-edit-toggle` (`:1304`) "✎ Edit" → `methods-editor` (`:1313`) `RegulatoryDocumentEditor` opens with the content. 3) Edit the text. 4) `methods-save-edited` (`:1285`) "↓ Save edited version" → downloads `biomate-methods-<name>-<runId>-edited.md`; `methods-save-toast` (`:1275`) "Edited methods report downloaded". 5) `methods-done-editing` (`:1294`) "Done editing" → back to read-only. 6) **Mid-edit-guard:** while editing, simulate a source refresh (the methods job re-resolves / `methods.text` changes) and assert the editor content is NOT reset (`useEffect` re-seeds only `if (!editing)`, `:1242-1245`).
- **Expected UX:** states=read-only ↔ editing; visual=toolbar label switches "Methods report" ↔ "Editing methods report"; honesty=**a source refresh mid-edit must not silently overwrite the user's edits** (the recently-fixed guard) — this is the key UX-honesty case; the edited version is a local markdown download (NOT a persisted server version — no fake version chip, per §12 scope note `:1211-1219`); interaction=Save gives a toast, Done returns cleanly; a11y=Edit/Save/Done buttons titled.
- **Acceptance:** Edit opens the editor with the content; Save downloads the edited md + toast; Done returns to read-only; **mid-edit source refresh does NOT clobber edits.** Tab hidden entirely when methods are a stub.
- **Upgrade:** editable-methods increment present. **V2 Δ:** §12 full thesis (server-side `fileVersions`, chat-propose-diff accept/reject, report in the project file tree, PDF/DOCX/HTML/ZIP export) is DEFERRED. **Known gap** — assert the edit-and-save affordance + the honest "no version chip" scope; do not assert versioning.

### B3-AR-06 · Parameters tab + Run-again-with-edits
- **Steps:** `after-tab-params` → k/v table (`:1377`); `afterrun-run-again-params` (`:1365`) → dispatches `biomate:run-again-with-edits` CustomEvent + `afterrun-cta-toast-params` (`:1370`).
- **Expected UX:** visual=every param as a row; honesty=no params → "No parameter values recorded." (CTA hidden); interaction=CTA dispatches the event + shows the toast (parent wire-up pending — the toast is honest about that); a11y=table.
- **Acceptance:** table renders every param; CTA dispatches + toasts. **Upgrade = V2, Δ none.**

### B3-AR-07 · Software / Citations / QC-audit / Trajectory tabs
- **B3-AR-07a Software** (`SoftwareTab` `:1747`): tab iff `/software` non-empty; "Sourced from versions.yml" + tool/version rows; forced-empty → "No software versions recorded." Honesty: hidden when empty, not a placeholder.
- **B3-AR-07b Citations** (`CitationsTab` `:1769`): tab iff `/citations` ≥1; list + `doi:` / external link; empty → "No citations registered." a11y: links `rel="noreferrer noopener"`.
- **B3-AR-07c QC audit** (`QcAuditTab` `:1440`): always-present tab. With events → `qc-summary` (`:1474`) 4 stats `qc-stat-evaluated`/`qc-stat-passed`(green)/`qc-stat-autoloop`(amber)/`qc-stat-manual`; `qc-audit-log` (`:1518`) cols Timestamp/Gate/Threshold/Observed/Result/Action, `qc-row-<i>` w/ `qc-row-<i>-result` "✓ PASS"/"↻ FAIL → loop"; `qc-chain-of-custody` (`:1563`) SHA-256 text. **Empty (clean run):** `qc-all-passed` (`:1462`) "All quality gates passed" + green check, NO table — **this is the default for good runs, not "no data".** e-signature `qc-e-signature` (`:1585`) is ALWAYS hidden in production (`eSignature` never forwarded by the parent) — assert the hide, not the populated block.
- **B3-AR-07d Trajectory** (`TrajectoryView` via `useFetchTrajectory` `:696`): always-present tab; no backend endpoint yet → probes `/trajectory`, 404 → [] → honest "No entries". Assert the empty state; **no fabricated rows.**
- **Expected UX (all four):** honesty=hide-when-empty (software/citations) or honest-empty (qc-all-passed / trajectory no-entries); visual=stat colours correct; a11y=tables + labelled links.
- **Acceptance:** each tab shows real content when present and the honest empty/hide otherwise; QC stats sum to events.length; e-sig hidden; trajectory "No entries".
- **Upgrade = V2** (trajectory + QC-audit are v2 §7.7 governance, DONE). **Δ:** none material.

### B3-AR-08 · Download comprehensive report (dedup + toast)
- **Steps:** `afterrun-download-report` (`:242`) → "Preparing…" → downloads `biomate-run-<runId>.md`; toast "Report downloaded — check your browser"; double-click deduped (`downloadState` guard `:194`).
- **Expected UX:** interaction=one click starts, second immediate click is a no-op; visual=label flips Preparing→idle; honesty=`buildFullReportMarkdown` (`:1795`) stitches Dataset/Findings/Outputs/Methods/Parameters/Software/Citations/QC/Reproducibility — findings-pending at click → inlines "Findings analysis is still pending…" (honest, not a fake summary); **no S3 URIs leaked** (dataset/outputs shown as references + BioMate endpoints); a11y=button titled.
- **Acceptance:** file downloads with the right name + toast; second immediate click no-ops; report body has no S3 URIs and honest pending notice when applicable.
- **Upgrade = V2 (client-side md).** **V2 Δ:** §12 wants server-side multi-format (PDF/DOCX/HTML/ZIP) export — deferred. Note Δ.
- **Download-report link visibility (CLAUDE.md):** on a completed run, assert a "Download report" affordance is visible (the header `afterrun-download-report` and/or FindingsCard's report link) — must not be missing after completion.

### B3-AR-09 · Failed-run section (badge, humanised error, autofix history, log tail) — CLAUDE.md "Failed" standard
- **Precondition:** `executionStatus='failed'|'cancelled'` (optionally with autofix attempts + log tail).
- **Steps:** 1) `afterrun-failed-section` (`:406`) ABOVE the tab bar. 2) Badge "Run failed"/"Run cancelled" (`:418`) + `afterrun-run-again-failed` (`:424`) → `biomate:run-again-with-edits` + `afterrun-cta-toast-failed` (`:408`). 3) If autofix tried → `afterrun-autofix-summary` (`:434`); toggle `afterrun-autofix-toggle` (`:467`) lazy-fetches `/autofix3/sessions`. 4) `afterrun-error-message` humanised (`:496`, `humanizeNfError` `:65`); failed-steps list; log tail (last 20, `:517`).
- **Expected UX:** states=section above tabs on failure; visual=red "Run failed" badge / grey "Run cancelled"; honesty=**humanised error (no raw stack/timestamps); autofix narrative distinguishes "exhausted after N attempts" (`:451`) vs never-ran; log tail labelled "showing last N of M"**; interaction=Run-again CTA dispatches + toasts (wire-up pending, honestly stated); autofix toggle fetches real attempts; a11y=badge + labelled toggle.
- **Acceptance:** section above tabs; badge/error/log-tail correct; autofix toggle fetches real attempts; error is humanised.
- **Upgrade = V2, Δ none.**

---

## Per-module Δ (Upgrade → V2) summary

| Module | Element | Upgrade (deployed today) | V2 spec (§) | Δ verdict for the UX test |
|---|---|---|---|---|
| B1 | Panel subline | phase-count / description | `project · version · provenance` audit anchor (§7.1) | **Regression-ish** — V2 subline is more auditable; test Upgrade's honesty, note gap |
| B1 | State words | Ready/Running/Completed/Failed | + Halted / **Awaiting approval** (§7.1/7.9) | **V2 improvement** — richer vocabulary; approval gate DONE, "Halted" absent |
| B1 | QC gate | two-number + 3-action (apply/keep/cancel) | + **evidence-level row** + override→audit (§7.5.1) | **V2 improvement** — evidence-level UNDONE; test the triad + colours |
| B1 | Global param provenance | `autoFilled` badge + rationale | **5-origin** badge + why+citation (§7.4) | **V2 improvement** — 4-origin lives in the *step* view; global panel is 1-badge |
| B1 | Run KIND | **`deriveRunKind` implemented** (Design/Training/Sandbox/Workflow) | KIND override + `wfFor(dom,mod)` card shape (§13.2/13.4) | **Ahead of V2GAP audit** — KIND DONE; per-domain card shape still UNDONE |
| B1 | Auto-loop | present but `autoloopLocked=true` | always-visible, cap 3 (§7.2) | **Neutral** — reachable only via flag flip; QC-halt UX via the inline gate |
| B1 | Skip map | display-only (no `onToggle`) | during-run skip + never-red + QC-audit record (§2.5) | **Neutral** — read-only is the honesty caveat; test display states only |
| B1/RunSurface | Stage | **tabbed** (Settings/Phases/After-run) | **split stage** + fold + status legend (§7.1) | **Deliberate arch Δ** — split-dependent elements deferred, not bugs |
| B2 | Step header | "Full step view" label | "step n of N" + phase letter + dock mode (§8.2) | **V2 improvement** — deferred |
| B2 | Step affordances | **Details/Rerun/Params wired, terminal-gated** | step-as-object interactivity (§8) | **Ahead of V2GAP audit** — now interactive |
| B2 | Rendered/raw | DONE + "Raw first…" copy | same (§8.5) | **Parity** — a shared strength |
| B2 | Structure viewer | **pLDDT chart ↔ 3D selection wired** | + PAE heatmap together (§8.5) | **Ahead of V2GAP audit** for pLDDT; PAE integration still UNDONE |
| B2 | Number→source | figures carry `source_file` | per-**number** inline anchor + **claim card** (§8.6) | **V2 core-claim gap** — claim card UNDONE |
| B2 | Panes | grip resize (open/closed persist) | rail/reveal/880-collapse/width-persist (§14.1) | **Largest deferred V2 area** — honest-absence tests |
| B3 | After-run tabs | 8 tabs, hide-when-empty | + **editable Report/DocEditor** first tab (§7.8/§12) | **V2 improvement** — editable *methods* is the partial delivery |
| B3 | Methods | **editable + Save md + mid-edit guard** | full §12 (versions/diff/file-tree/multi-format export) | **Ahead on the edit affordance**; versioning/export deferred |
| B3 | Outputs | list table + preview + bulk + save | `OutputGrid` (notes/search/thumbs) (RunSurface) | **V2 improvement** — deferred |
| B3 | Findings failed-run | **static "Analysis not available…"** | same honesty rule | **Parity** — CLAUDE.md must-not-regress guard |

---

## Execution notes (per master rubric)

1. **Real backend only** — dispatch real runs on `dev-public.biomate.ai` with the
   fixture + bypass token. The critical live cases (B1-ST-04 real-time SSE,
   B1-QC-01 hERG gate, B2-SP-06 pLDDT↔3D, B3-AR-04 failed-findings) require a real
   dispatched run — do not inject SSE or mock a status.
2. **Screenshot every state** — idle / running (≥1 phase running) / completed /
   failed / QC-blocked / findings, in BOTH the chat panel and the right panel,
   and audit against the v2 spec §07/08/12/13/14 + `localhost:7779` reference.
3. **A skip is a fail** — the two structurally-blocked surfaces (B1-PC-03/05
   auto-loop lock; B1-PP-02 phaseless `phase-params-toggle`) are recorded as
   **untested/blocked with the reason**, and their UX intent is covered via the
   reachable path (inline QC gate for halts; global param panel for phaseless
   param editing). They are NOT reported as passed.
4. **Honest-absence, not assert-present** — for every Known-gap element
   (split-stage, number→source claim card, 5-origin badge, evidence-level QC row,
   DocEditor Report tab, panes choreography, PAE), the test asserts the deployed
   surface is honest and free of broken half-states; it never asserts the missing
   element is present.
5. **The three CLAUDE.md standards are folded in as UX criteria** — "Workflow
   Panel" (B1-ST-01..05, B1-QC-*, B1-PP-*, B1-PC-02/04, B1-ST-04 real-time),
   "Chat + Workflow Panel Presentation" (B1-XR-01, and the name/state-sync checks
   throughout), and "Findings tab" (B3-AR-03/04/08). No screenshot may show
   "undefined"/"Analysis in progress…" on a failed run, and the download-report
   link must be visible on a completed run.
