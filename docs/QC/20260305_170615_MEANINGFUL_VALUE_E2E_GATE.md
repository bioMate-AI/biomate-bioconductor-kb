# Meaningful Value E2E Gate — Validation Report

**Timestamp:** 2026-03-05 17:06:15 CST  
**Environment:** `BIOMATE_URL=http://localhost:5419`  
**Purpose:** enforce "real user value" pass/fail criteria instead of shallow UI/activity checks.

---

## What was added

A new strict Playwright gate:

- `frontend/e2e/meaningful-value-gate.e2e.ts`

This gate marks a run as **FAIL** unless all of the following are true:

1. Assistant response is domain-meaningful (not generic demo text).
2. Workflow artifact is rendered.
3. Run action is available and executable.
4. Backend run reaches `completed`.
5. Artifact-readiness contract is met.
6. At least one visualizable and one downloadable output is reported by backend.
7. Invocation outputs contain at least one usable output entry.
8. UI shows output section + report/visualization affordance + enabled download action.

The gate emits a machine-readable verdict attachment:

- `frontend/e2e/test-results/meaningful-value-gate.e2e.-f8353-aningful-and-usable-outputs-chromium/attachments/meaningful-value-gate-report-d64cbe692cb654496f768330db73584d7bdaee34.json`

---

## Executed command

```bash
cd /home/yzhang/biomate/frontend
BIOMATE_URL=http://localhost:5419 npx playwright test e2e/meaningful-value-gate.e2e.ts --project chromium
```

Result: **FAILED** (including retry).

---

## Why this is a meaningful failure (not false green)

From the generated verdict report:

- `verdict: "FAIL"`
- failure reasons include:
  - workflow artifact not rendered
  - run button not found
  - no runId captured
  - run did not complete
  - no usable outputs from backend endpoint
  - output/report/download UX affordances missing

At the same time, assistant text was domain-relevant (`assistantDomainHits` populated), proving this is **not** a pure LLM-generation failure. The failure is at conversion-to-runnable-workflow and downstream output usability.

---

## Server log validation

During the failing gate run window, server logs show repeated chat streaming responses but **no matching workflow execute request** for that flow:

- `POST /api/chat/stream 200` (multiple entries)
- repeated `GET /api/workflows/runs ...` polling
- no new corresponding `POST /api/workflows/execute` in the same sequence

This supports the gate's failure reason: response looked informative, but did not become a runnable/output-producing UX flow.

---

## Why this gate improves trustworthiness

This gate prevents the common false-positive pattern:

- old tests pass because "assistant answered" or "keywords appeared";
- user still gets no actionable outputs.

Now a run can only pass when **user-value evidence** exists across:

- conversation quality,
- workflow execution path,
- backend artifact contract,
- visible output affordances in UI.

---

## Next hardening steps

1. Add this gate to CI as a required check for UX-quality claims.
2. Run two prompts per build (`cryo-em` + `rna-seq`) and require both pass.
3. Store the emitted verdict JSON + trace/video as release artifacts.
4. Add a second gate profile that forbids "conversion-only" responses unless workflow artifact appears in same turn.
