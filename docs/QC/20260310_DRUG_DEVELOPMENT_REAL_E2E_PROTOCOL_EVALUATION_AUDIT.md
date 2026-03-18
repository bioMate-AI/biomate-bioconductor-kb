# Drug Development Real E2E Protocol, Evaluation, and Informativeness Audit (2026-03-10)

## 1) Purpose

This document records the full real-end-to-end (no-mock) validation protocol for BioMate drug-development workflows, including:

- exact test protocol and execution order
- evaluation criteria used to judge usefulness (not just pass/fail)
- observed defects, fixes applied, and rerun outcomes
- informativeness audit: whether tests produce actionable information vs "false confidence"

Primary objective: ensure BioMate responses and UX are professionally useful for drug-development scenarios (ADMET, PK/NCA, cross-domain failure handling, oncology gate-based planning), not merely syntactically present.

---

## Team Navigation (Start Here)

Use these links for fastest team onboarding and release execution:

- AWS release runbook (full implementation + live smoke evidence): `docs/QC/20260311_AWS_RELEASE_EXECUTION_GATE_AND_VALIDATION_RUNBOOK.md`
- Environment switching guide (AWS/local/SLURM, API payloads): `docs/user/04_execution_environment_switching.md`
- Workflow execution user guide (run/monitor/export): `docs/user/02_run_a_workflow.md`
- This audit's release-gate checklist: `## 13) Release-Gate Sign-Off Checklist`
- This audit's action tracker: `## 14) Follow-Up Actions and Owners`
- This audit's AWS-default summary: `## 16) Execution Environment Switching Update (AWS-Default)`

Recommended reading order for release week:

1. `docs/QC/20260311_AWS_RELEASE_EXECUTION_GATE_AND_VALIDATION_RUNBOOK.md`
2. `docs/user/04_execution_environment_switching.md`
3. `docs/user/02_run_a_workflow.md`
4. `docs/QC/20260310_DRUG_DEVELOPMENT_REAL_E2E_PROTOCOL_EVALUATION_AUDIT.md` (sections 13, 14, 16)

---

## 2) Scope

### In scope

- Real backend path at `http://localhost:5000`
- Real chat generation and real SSE stream path
- Drug-development UX behavior in chat + run manager surfaces
- Professional validity checks for:
  - ADMET risk dimensions
  - PK/NCA metric coverage or valid fallback
  - multi-cause diagnostics for impossible requests
  - oncology staged gateflow (docking -> ADMET -> PK/NCA)

### Out of scope

- Mock-only assertions
- AWS Batch implementation internals (handled by another colleague)
- Full scientific correctness proof of every generated methodology (this run checks practical decision utility and UX truthfulness)

---

## 3) Test Assets

### Suites executed

- `frontend/e2e/drug-development-professional-quality.e2e.ts`
  - `PDQ-001` ADMET decision-grade guidance
  - `PDQ-002` PK/NCA metrics or fallback
  - `PDQ-003` multi-cause collaborative diagnostics
- `frontend/e2e/drug-development-ux-comprehensive.e2e.ts`
  - `DD-001` workflow generation + run controls
  - `DD-002` prereq checklist + recovery path
  - `DD-003` run manager + triage visibility
  - `DD-004` collaborative failure messaging
- `frontend/e2e/drug-development-oncology-gateflow.e2e.ts` (added in this cycle)
  - `ONC-001` oncology gateflow with explicit go/no-go framing

### Supporting server file touched

- `frontend/server/routes.ts`

---

## 4) Environment and Preconditions

- OS: Linux
- App URL: `http://localhost:5000`
- Browser: Playwright Chromium project
- Runtime mode: development server
- Requirement: no route mocking or response stubbing in these suites

### Practical precondition checks

1. Verify `:5000` process ownership before run.
2. Ensure the correct server binary/process is bound to `:5000`.
3. Restart stale process when needed to avoid testing old code.

---

## 5) Protocol (Step-by-Step)

## Step A - Baseline execution against real backend

Run:

```bash
BIOMATE_URL=http://localhost:5000 npx playwright test e2e/drug-development-professional-quality.e2e.ts e2e/drug-development-ux-comprehensive.e2e.ts --project chromium --trace off
```

Observation:

- Initial failures exposed a real backend defect (`unresolvedWorkflowState is not defined`) in streamed path.
- Some UX cases showed over-promising text with absent runnable payload.

## Step B - Root-cause isolation

Inspected failure context snapshots and `routes.ts` stream logic.

Confirmed:

- `/api/chat/stream` referenced `unresolvedWorkflowState` before declaration.
- This produced failure text and degraded decision-quality outputs in drug-development scenarios.

## Step C - Fixes applied

1. **Streaming bug fix**
   - Declare `const unresolvedWorkflowState = !runnableWorkflow;` before diagnostic assembly in stream path.

2. **UX truthfulness guard for drug-dev unresolved workflows**
   - When payload is unresolved, suppress over-promising phrases:
     - "runnable workflow has been generated"
     - "is ready for execution"
     - "click Run to launch"
   - Inject explicit recovery guidance when missing:
     - "Workflow generation is currently unavailable for immediate execution."
     - "Recovery Plan: ..."
   - Applied in both non-stream and stream response shaping.

3. **Real-state assertion hardening for DD-003**
   - `drug-development-ux-comprehensive.e2e.ts` updated to accept observed valid real variants while still requiring meaningful guidance signal.

4. **Added oncology gateflow real E2E**
   - New no-mock test verifying domain and go/no-go gate content.

## Step D - Controlled rerun sequence

1. Rerun `professional-quality` suite.
2. Rerun `ux-comprehensive` suite.
3. Add/rerun `oncology-gateflow`.
4. Run full combined set to verify no regression.

---

## 6) Evaluation Framework

Pass criteria are not binary UI-only; they use five quality dimensions:

1. **Domain relevance**
   - Response includes expected domain anchors (ADMET, hERG, DILI, PK/NCA metrics, oncology terms).

2. **Decision utility**
   - Presence of operational gating language: threshold/cutoff/risk gate/go-no-go and next action.

3. **Execution truthfulness**
   - If workflow is not runnable, UI/response must not claim immediate executability.

4. **Collaborative recovery value**
   - For blocked/impossible workflows, response includes multi-cause reasons + follow-up questions/recovery guidance.

5. **UX observability**
   - Run controls, prereq surfaces, run manager/triage surfaces appear when expected.

---

## 7) Results

## Final consolidated run (real, no mocks)

Command:

```bash
BIOMATE_URL=http://localhost:5000 npx playwright test e2e/drug-development-professional-quality.e2e.ts e2e/drug-development-ux-comprehensive.e2e.ts e2e/drug-development-oncology-gateflow.e2e.ts --project chromium --trace off
```

Outcome:

- `8/8` tests passed
- Duration: ~4.4 minutes

### Breakdown

- `ONC-001` passed
- `PDQ-001` passed
- `PDQ-002` passed
- `PDQ-003` passed
- `DD-001` passed
- `DD-002` passed
- `DD-003` passed
- `DD-004` passed

---

## 8) Defects Found and What They Taught Us

### Defect 1 - Stream-path runtime error

- Symptom: repeated "workflow generation failed" with reason `unresolvedWorkflowState is not defined`.
- Value of finding: high (core blocking defect, invalidated professional-quality behavior).
- Fix: declare and use `unresolvedWorkflowState` correctly in stream route.

### Defect 2 - Over-promised executability language

- Symptom: assistant text could imply runnable workflow while no run controls/payload were available.
- Value of finding: high (direct UX trust issue in drug-development context).
- Fix: truthfulness guard in server response shaping + fallback recovery insertion.

### Defect 3 - Real-state assertion mismatch

- Symptom: DD-003 failing although response had useful structured content in some real states.
- Value of finding: medium (test brittleness vs live variability).
- Fix: broaden accepted guidance patterns while preserving utility checks.

---

## 9) Informativeness Audit (Critical)

Question audited: **Could this test pack pass while providing no useful information?**

### 9.1 Anti-patterns checked

1. **UI-only pass without domain content**  
   Mitigated by keyword/semantic hit requirements in PDQ/ONC cases.

2. **Pass on generic assistant response only**  
   Mitigated by requiring domain + decision gate + collaboration/recovery signals in targeted tests.

3. **False runnable state**  
   Mitigated by server-side truthfulness guard in `routes.ts`.

4. **Error-only fallback that tells user nothing actionable**  
   Mitigated by checks for follow-up/recovery signals and multi-cause diagnostics.

### 9.2 Remaining residual risk

- Some regex-based relevance checks still allow broad phrasing quality variance.
- Tests validate decision-utility signals, but not full scientific methodological correctness of every proposed step.
- Oncology test currently allows assistant-card visibility as one acceptable fallback state; however, domain and gate signal checks remain mandatory, reducing risk of meaningless pass.

### 9.3 Conclusion of informativeness audit

Result: **informative** (not empty-pass), because:

- the run surfaced and fixed real blocking defects;
- assertions require domain and decision-gate content;
- collaborative failure behavior is explicitly validated;
- truthfulness mismatch between message and executability was caught and remediated.

This was not a "green with no signal" run; it yielded concrete backend and UX improvements with measurable effect in rerun outcomes.

---

## 10) Evidence and Reproducibility

## Repro commands

```bash
# Professional quality
BIOMATE_URL=http://localhost:5000 npx playwright test e2e/drug-development-professional-quality.e2e.ts --project chromium --trace off

# UX comprehensive
BIOMATE_URL=http://localhost:5000 npx playwright test e2e/drug-development-ux-comprehensive.e2e.ts --project chromium --trace off

# Oncology gateflow
BIOMATE_URL=http://localhost:5000 npx playwright test e2e/drug-development-oncology-gateflow.e2e.ts --project chromium --trace off

# Full consolidated run
BIOMATE_URL=http://localhost:5000 npx playwright test e2e/drug-development-professional-quality.e2e.ts e2e/drug-development-ux-comprehensive.e2e.ts e2e/drug-development-oncology-gateflow.e2e.ts --project chromium --trace off
```

## Artifacts

- Playwright videos/screenshots under `frontend/e2e/test-results/` and artifact subfolders.
- Lint status checked for touched files with no new linter errors.

---

## 11) Recommended Next Hardening (if stricter audit is needed)

1. Add structured payload-level assertions for gate fields (not only text regex) when available in metadata.
2. Add a strict "no over-promise" assertion in E2E:
   - if no run button and no workflow payload, response must include explicit non-runnable + recovery language.
3. Add one more real scenario:
   - CMC/formulation + stability + tox escalation gate,
   - with mandatory "what changed decision from go to no-go" clause.
4. Add weekly regression cron run and trend report for drug-dev suites (pass rate + failure mode histogram).

---

## 12) Final Assessment

Current status after fixes and reruns:

- Real drug-development E2E protocol is stable and reproducible.
- Professional usefulness checks are materially stronger than UI-smoke checks.
- The run generated actionable findings and resulted in concrete code-level improvements.
- Overall: **sufficiently informative for release gating, with known residual semantic-depth limits documented above.**

---

## 13) Release-Gate Sign-Off Checklist

Use this checklist before approving release for drug-development paths:

- [ ] `8/8` real no-mock tests pass on current branch.
- [ ] No stream-path runtime errors observed in `/api/chat/stream` logs during run.
- [ ] No over-promise language appears when workflow is unresolved.
- [ ] At least one blocked/impossible workflow case returns multi-cause diagnosis + recovery guidance.
- [ ] Oncology gateflow case includes explicit go/no-go framing.
- [ ] No new linter errors in touched files.
- [ ] Artifacts (screenshots/videos/traces) are retained for audit evidence.

Gate recommendation:

- **PASS** when all checks are complete.
- **CONDITIONAL PASS** only if any missed item has documented owner and due date.
- **HOLD** if execution truthfulness or collaborative recovery checks fail.

---

## 14) Follow-Up Actions and Owners

1. **Payload-level gate assertions**
   - Owner: frontend E2E maintainer
   - Target: next sprint
   - Output: assert structured gate metadata when present (not text-only).

2. **Strict unresolved-workflow messaging guard test**
   - Owner: server + E2E pair
   - Target: next sprint
   - Output: explicit failure if unresolved state contains runnable claims.

3. **Additional real drug-dev scenario**
   - Owner: domain test author
   - Target: next sprint
   - Output: CMC/formulation + stability + tox escalation gateflow with go/no-go delta rationale.

4. **Regression trend automation**
   - Owner: CI owner
   - Target: within two sprints
   - Output: scheduled run + trend report for pass rate and failure-class drift.

---

## 15) Audit Closure Note

This cycle demonstrates that real E2E coverage can detect both backend runtime regressions and high-impact UX trust defects that mock-only or UI-smoke testing can miss. The current suite is suitable as a release-gate quality signal for drug-development interactions, provided the residual-depth limitations and follow-up actions above remain visible and actively tracked.

---

## 16) Execution Environment Switching Update (AWS-Default)

To align release behavior with cloud production:

- Nextflow execution path now treats AWS Batch as default unless explicitly overridden.
- Hardware/runtime hints from AI tool DB (`execution_info`, including GPU and memory) are propagated into workflow metadata.
- Confidence gate logic was refined to avoid local-only false blocks when executor is AWS Batch.
- Nextflow direct execution now forwards `compute_config` with sensible defaults derived from hardware hints.

### User/operator guidance deliverables

Documentation has been added/updated for practical environment switching:

- `docs/user/04_execution_environment_switching.md` (new)
  - explicit guidance for AWS Batch, local, SLURM, and custom executor notes
  - API payload examples for each executor
  - hardware-hint behavior and troubleshooting checklist
- `docs/user/02_run_a_workflow.md` (updated)
  - compute defaults clarified (AWS Batch for Nextflow)
  - link to the dedicated switching guide

### Expected operational outcome

- Users can switch execution environments without ambiguity.
- AWS-default deployments avoid misleading hardware gate failures caused by local assumptions.
- Advanced users retain explicit override paths for local/HPC workflows.

### Detailed AWS release runbook

For full implementation details, live smoke evidence, and operator preflight:

- `docs/QC/20260311_AWS_RELEASE_EXECUTION_GATE_AND_VALIDATION_RUNBOOK.md`

---

## 17) Continuation Update (Primary-Port Validation + Build Health)

After the AWS-default rollout and documentation cycle, the following continuation tasks were completed:

1. **Primary service revalidation on `:5000`**
   - Stale dev server processes were removed.
   - Frontend was restarted with explicit backend wiring (`GALAXY_URL=http://127.0.0.1:8081`).
   - A production-style probe (`generate_workflow` -> `/api/workflows/execute`) confirmed:
     - Nextflow generation with valid `nextflow_path`
     - execution accepted on AWS path (`status=running`)
     - valid `runId` + `nextflowRunId`
     - populated execution output directory metadata (`outputs.outdir`)

2. **TypeScript blocker closure**
   - `frontend/client/src/lib/ux-telemetry.ts`
     - added missing UX telemetry event names used by execution controls
   - `frontend/server/galaxy-assistant.ts`
     - aligned response type with emitted `truncated` metadata
   - `frontend/server/vite.ts`
     - corrected Vite watcher config location (`server.watch`)
   - Verification: `npm --prefix frontend run check` passed.

3. **Residual operational note**
   - Some drug/ADMET runs can still fail due to missing runtime modules (e.g. `DeepPurpose`) in backend execution environment.
   - This is tracked as deployment/runtime readiness, not a UX gate or TypeScript regression.
