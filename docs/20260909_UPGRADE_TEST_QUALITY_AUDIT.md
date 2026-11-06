# Data-Centric Upgrade — Adversarial Test-Quality Audit

**Date:** 2026-09-09
**Scope:** All ~25 test files touching the data-centric upgrade, reviewed by three
read-only adversarial agents. The question applied to every test: *"if the feature
were broken, would this test still pass?"*

## Headline

- **Pure-function / logic tests are strong** — `laneForText`, `groupProgressMessages`,
  `readIntent`, `sourceUrl`, `classifyRejection`, `reRank`, `isContradiction`,
  `async-guidance` (retry classifier), `clarify-card`, the parameterized router
  self-test. Real value/identity assertions, adversarial ordering, no false-positive risk.
- **Systemic weakness:** stateful/async React wrappers' **error + fallback paths**
  and server route **behavior** are barely tested. Two anti-patterns:
  1. **Client:** static-prop rendering substituted for real-time/streaming behavior
     (SSE transitions asserted only as final state).
  2. **Server:** `SRC.match(regex)` grep of source text as a proxy for behavior —
     cannot catch inverted logic, reversed sorts, dead-code branches, or error paths.

## Fixed + committed this session

| Fix | File | Was |
|---|---|---|
| Positive + failure-path save-to-notes | `citation-panel.save-notes.test.tsx` (new) | disabled-only (broken feature would ship green) |
| Dead `expect(...).toHaveAttribute` (never invoked) | `DesignGenerate.test.tsx` L84 | no-op |
| Tautological `.toBeTruthy()` → real label↔lane | `cold-start-dashboard.test.tsx` L184 | tautology |
| Stale "QC tab hidden when empty" → assert real `qc-all-passed` | `AfterRunReport.test.tsx` L270 | passed for the wrong reason |

## Remaining gaps (ranked; "would ship broken green")

1. **`notes-routes.test.ts` — 100% source-grep, 0% behavior (WEAK).** An inverted
   ownership check (cross-user leak) or reversed `createdAt` sort passes every test.
   LLM-empty→502 not even grepped. → Rewrite as express + fake-repo handler tests
   asserting status + body (owner 201 / cross-user 404 / no-rows 404 / LLM-reject 502
   / freshest-note-first).
2. **`nextflow-workflow-viewer.test.tsx` — real-time SSE untested.** EventSource is an
   inert stub; every test hands a static `status` prop and checks final render. A stuck
   spinner / missed terminal transition ships green. → live-dispatch MockEventSource
   asserting a phase card flips `pending→running`; add `status="failed"` Restart CTA.
3. **`evidence-routes.test.ts` — route auth/502/cache grep-only** (greps dead-code 401
   branches). Adapter half is excellent — keep it. → supertest route tests for
   400/502/cache-hit/partial `source_errors`.
4. **`models.test.tsx` — gate FAIL / not_evaluated verdicts never tested** (only pass);
   **RunPretrained failed-inference** (`result-status-failed`) untested (violates
   "failed run shows error not spinner").
5. **`lane-preview` component — `useServerLane` error+fallback + the `reads as reads as`
   dedup (a shipped bug fix) have no test.** → `lane-preview.component.test.tsx`: fetch
   resolve-cloud upgrades the strip; reject → stays local; `{success:false}` ignored;
   `read:"reads as X"` → no doubled prefix.
6. **`ConflictRow` "Sources disagree" — zero tests anywhere** (§1.3.2 honesty feature).
7. **`data-hub.test.tsx` — file→DatasetObject interaction never exercised** (stub returns
   empty; test stops at the empty prompt) — the "dataset as first-class object" thesis.
8. **`workflow-artifact.qc-summary.test.tsx`** — single happy-path; panel-absent-when-no-gates
   + SSE-live-update untested.
9. **`project-notes.test.tsx`** — refresh/GET-failure `notes-error` banner untested.
10. Minor fallback chains: `source-reader` title||tool_name||Untitled; `why-anchor`
    `defaultFetchRationale` real fetcher + rationaleId path; `clarify-card` skip-on-last +
    Previous + empty-freetext; `skip-dependency` singular-blocker grammar.

**Solid, keep as-is:** `async-guidance`, `skip-dependency`, `source-reader-pane`,
`lane-preview` (laneForText), `chat-progress-fold` (grouping), `clarify-card`,
`dl-viewers`, `step-output-preview`, `step-detail`, `data-perception`.
