# IND Report — E2E Test Plan

**Date:** 2026-05-19
**Sandbox:** `frontend/sandbox/ind-port/`
**Reference:** `frontend/e2e/cryoem-stepwise-and-output.e2e.ts` — 14 test IDs (CS-1 … CS-14), 2,195 lines, per-test audit JSON, super-merged happy-path test, real backend with targeted route-stubs for assertion paths only.
**Goal:** treat the IND port as a real product with the same evaluation discipline as the CryoSPARC pipeline. Replace the 24 happy-path-only tests with a structured suite that exercises every Appendix-B feedback surface, every step-card state, every audit severity, and the responsive flow — and emits a machine-readable audit JSON per test for downstream dashboards.

---

## Spirit (lifted from `cryoem-stepwise-and-output.e2e.ts`)

1. **Test IDs.** Each test has a stable ID (`IND-N`) referenced from commit messages, docs, and dashboards. No anonymous tests.
2. **Per-test audit record.** Every test populates a structured `SuiteRecord` with: testId, startTs/endTs, finalStatus, walltime, feedback-API events that fired, step states observed, audit-finding counts, region state, screenshots, assertions list, error.
3. **One audit JSON written to disk in `afterAll`.** Includes `passed/total` headline + every `SuiteRecord`. Lives at `.test-output/ind-suite-audit.json` so a dashboard can ingest it.
4. **Super-merged happy-path test.** Runs the full pipeline in one test to avoid re-running expensive setup, then writes per-step records into the same audit JSON. Mirrors the cryo suite's `CS-3+4+5+10+12+13+14` super-merge.
5. **Real backend by default.** The 4 Appendix-B endpoints fire against the live `feedback_router.py`. Route-stubs only used when (a) verifying exact request payloads or (b) injecting state the UI can't otherwise reach (CRITICAL findings, paid-tier adapter, imported-from-chat banner).
6. **Screenshots per test ID.** `.snapshots/{IND-1, IND-2, …}` so a reviewer can match a finding to the test that surfaced it.
7. **No assertion fires silently.** Every `expect()` also appends to `audit.assertions` with name + passed + optional note.
8. **Honest naming.** A test named "happy path" must actually exercise the happy path; a test named "CRITICAL blocks signing" must inject a CRITICAL finding and assert the sign button is blocked.

---

## Test inventory

### Section A — Visual / structural landmarks

| ID | Title | Why it matters |
|---|---|---|
| IND-1 | Onboarding EmptyState — 3 reference compound chips, "Start" exits onboarding | Spontaneous-entry path; "what if I have no compound yet" |
| IND-2 | Topbar — breadcrumb / region chips / tutorial / user avatar all present | Page identity; cross-region awareness |
| IND-3 | LeftNav — project list with status dots (signed/in_progress/blocked), active highlight | Project switching is the most-used surface |
| IND-4 | Pipeline structure — 5 step cards stacked, default collapse state | Information density |
| IND-5 | Doc panel — version chip, region selector, 6 section tabs, footer with SHA-256 + sign | Document identity surface |
| IND-6 | OKLCH design tokens — FDA/EMA/NMPA/PMDA chips render in correct hues | Brand parity with prototype |

### Section B — Step cards across states

| ID | Title | Why it matters |
|---|---|---|
| IND-7 | Step 1 Project Setup — kv list, region toggles, compound count, lead SMILES | Setup state must be readable |
| IND-8 | Step 2 ADMET complete state — gates row, model badge, expandable table | Default ADMET result view |
| IND-9 | Step 2 ADMET **running** state — progress bar 0-100%, ETA, feeds-into hint | Must validate non-happy-path renders |
| IND-10 | Step 2 ADMET **imported-from-chat** banner — purple alert with timestamp + Re-run | Spontaneous-entry-path validation |
| IND-11 | Step 3 PBPK passed — EMA criterion box green, two-chip status, lead params | Happy-path PBPK |
| IND-12 | Step 3 PBPK **failed** — red criterion box, "Re-run with new params" CTA | Failure path the prototype designed for |
| IND-13 | Step 4 Lead Selection — top-5 table, OOD chips, applicability-domain count | Lead picking is the regulatory hinge |
| IND-14 | Step 5 IND Document — section list, audit chips, regions, completeness checklist | Pre-sign state |

### Section C — Doc panel + feedback surfaces (Appendix B)

| ID | Title | Why it matters |
|---|---|---|
| IND-15 | DocPanel inline audit chips — `⚠ MAJOR` next to §2.6.1.2 paragraph (data-section match) | **Found broken in round-3 audit** — sections lack `subs`, chips never surface |
| IND-16 | DocPanel paragraph edit (B2) — type → blur → captureEdit POST with diff payload | Core feedback loop |
| IND-17 | DocPanel paragraph no-op — blur without change → no POST | Don't pollute training pool |
| IND-18 | DocPanel cite suggest (B4) — click `+`, fill, "Also suggest" → POST with `document_only=false` | Citation extension flow |
| IND-19 | DocPanel cite document-only — same but `document_only=true` → no queue | Customer controls what reaches us |
| IND-20 | Regenerate-with-instruction (B5) — click regen → modal → instruction → POST | Prompt-tuning signal |
| IND-21 | Region selector — switch FDA → NMPA → hint "incl. GLP declaration" appears | Multi-region awareness |

### Section D — Audit overlay (Appendix B B3)

| ID | Title | Why it matters |
|---|---|---|
| IND-22 | AuditOverlay opens via center-head button, severity counts visible, filter works | Default audit access |
| IND-23 | AuditOverlay dismissal — Dismiss → 4-option picker → submit → captureDismissal POST with reason mapped | Closes the reg-science feedback loop |
| IND-24 | AuditOverlay CRITICAL — inject CRITICAL finding, sign button disabled/blocked | Safety gate |
| IND-25 | AuditOverlay chain integrity footer — "✓ Valid (N records · last verified)" | 21 CFR Part 11 audit trail evidence |

### Section E — Sign & freeze (21 CFR Part 11)

| ID | Title | Why it matters |
|---|---|---|
| IND-26 | SignOverlay opens, 21 CFR Part 11 §11.200 header, document SHA + meaning + creds + TOTP | Regulatory compliance surface |
| IND-27 | SignOverlay validation — Sign disabled until 6-digit TOTP complete | Can't sign by accident |
| IND-28 | SignOverlay success state — frozen document, sig ID, download DOCX + audit trail PDF | Signed-state UI |

### Section F — Cross-cutting

| ID | Title | Why it matters |
|---|---|---|
| IND-29 | Responsive 1024 — doc panel hidden, FAB visible, narrow flow has a working route to the doc (not just `alert()` stub) | Narrow-viewport usability |
| IND-30 | Responsive 1280 — shell columns shrink to 220/1fr/420 | Mid-size laptop coverage |
| IND-31 | Active-adapter badge — paid-tier `X-BioMate-Org-Id` → badge "Customized for {Org Name}" | Moat surface |
| IND-32 | PII strip on free tier — drug names + study IDs replaced before captureEdit POST | Compliance |
| IND-33 | Active adapter API — GET `/api/regulatory/active_adapter` round-trips, badge updates | Live-backend smoke |

### Section G — Super-merged happy path

| ID | Title | Mirrors |
|---|---|---|
| IND-HAPPY | Full flow: onboarding → new project → step 1 setup → import ADMET → PBPK passes → leads → doc generated → review audit → dismiss MINOR → edit paragraph → suggest citation → sign → success | `CS-3+4+5+10+12+13+14` super-merge in cryo |

Total: **34 test IDs**. Current sandbox has 24 happy-path tests; this plan replaces them with structured coverage of every state the prototype supports.

---

## SuiteRecord schema

```typescript
interface FeedbackEvent {
  surface: "edit" | "dismiss" | "cite" | "regenerate";  // Appendix B B2-B5
  paragraph_id?: string;
  finding_id?: string;
  request_payload: Record<string, unknown>;
  response_status: number;
  posted: boolean;     // True if a captured POST actually fired
}

interface IndSuiteRecord {
  testId: string;                     // "IND-15"
  projectId: string | null;           // "p-bm0042"
  startTs: number;
  endTs: number;
  finalStatus: "passed" | "failed" | "skipped";
  wallTimeMs: number;

  // Feedback API calls observed during this test
  feedbackEvents: FeedbackEvent[];

  // Step states observed at end of test
  stepStates: Record<"s1"|"s2"|"s3"|"s4"|"s5", string | null>;

  // Audit findings counts at test start + end
  auditCountsStart: { critical: number; major: number; minor: number; info: number };
  auditCountsEnd:   { critical: number; major: number; minor: number; info: number };

  // Region selector path during the test
  regionAt: ("FDA" | "EMA" | "NMPA" | "PMDA" | "ALL")[];

  // Visual baseline diff (% pixels changed vs approved baseline screenshot)
  visualDiffPct: number | null;

  // Per-test assertions — every expect() also appends here
  assertions: { name: string; passed: boolean; note?: string }[];

  // Screenshots organized by test ID
  screenshots: string[];

  error?: string;
}
```

Written to `frontend/sandbox/ind-port/.test-output/ind-suite-audit.json` in `afterAll`:

```json
{
  "suiteId": "ind-report-e2e",
  "generatedAt": "2026-05-19T...",
  "passed": 28,
  "total": 34,
  "runs": [/* IndSuiteRecord[] */]
}
```

---

## Implementation strategy

### Phase 1 — Foundation (this commit)

`frontend/sandbox/ind-port/e2e.test.ts` — single file, organized like the cryo merged suite:

```typescript
// ===========================================================================
// Helpers — audit, screenshots, route stubs, demo-state knobs
// ===========================================================================

interface FeedbackEvent { ... }
interface IndSuiteRecord { ... }
const SUITE_AUDIT: IndSuiteRecord[] = [];

async function shot(page, testId, name) { ... }
function newAudit(testId): IndSuiteRecord { ... }
async function captureFeedback(page, audit): { unhook: () => void } { ... }
async function setDemoState(page, knobs): Promise<void> { ... }  // ?state=running, ?audit=critical, etc.

test.afterAll(async () => {
  // Write JSON
});

// ===========================================================================
// IND-1 ... IND-N
// ===========================================================================
test("IND-1: Onboarding EmptyState ...", async ({ page }) => { ... });
...
test("IND-HAPPY: full pipeline ... (super-merged)", async ({ page }) => { ... });
```

Phase 1 lands IND-1 through IND-12 + IND-HAPPY (~13 tests, validates the audit-record infrastructure).

### Phase 2 — Feedback-API coverage

Add IND-15 through IND-21 (the 4 Appendix-B surfaces under real-route observation, plus inline audit chips and region selector). Also fixes the round-3 finding (sections need `subs` for inline chips to appear).

### Phase 3 — Audit + sign overlays

IND-22 through IND-28 (audit dismissal, CRITICAL blocking sign, sign-overlay TOTP validation).

### Phase 4 — Cross-cutting + super-merged

IND-29 through IND-33 (responsive, active-adapter, PII strip) + IND-HAPPY.

Each phase commits independently with the suite audit JSON snapshot.

---

## Demo-state knobs (required infrastructure)

The current sandbox `IndReportPage` only renders a single happy-path state. To cover IND-9, IND-10, IND-12, IND-24, IND-28, IND-31, the page needs URL-query knobs:

| Knob | Effect |
|---|---|
| `?state=running` | Step 2 ADMET in `running` state with progress bar |
| `?state=pbpk-fail` | Step 3 PBPK fail-override on |
| `?audit=critical` | Demo audit includes a CRITICAL finding |
| `?imported=1` | Step 2 imported-from-chat banner shown |
| `?signed=1` | Step 5 in signed state |
| `?adapter=org-acme` | Active-adapter badge with `customized_for=acme` |
| `?onboarding=1` | EmptyState (already implemented) |

These mirror the cryo prototype's `knobs.step2State`, `knobs.pbpkFail`, etc. Documented as test fixtures, not production behavior.

---

## What the cryo suite has that this plan doesn't (yet)

| Cryo feature | IND equivalent (deferred) |
|---|---|
| `BIOMATE_URL` env override for dev EC2 | Add `INDREPORT_URL` env when integration moves out of sandbox |
| Real CryoSPARC S3 dataset + license | Real Galaxy backend for the 4 feedback endpoints (live-backend smoke) |
| SSE event injection via `/internal/sse-inject` | n/a — IND doesn't have an SSE channel |
| Cost tracking (`run-metrics-strip`, `Step LLM costs`) | n/a unless production wires the regulatory LLM call costs into the doc panel |
| `e2e/test-results/.last-run.json` + dashboard integration | Sandbox emits to `.test-output/`; integration step makes it pickup-able by the existing dashboard |

---

## Success criteria

The plan succeeds when:

- [ ] All 34 test IDs exist in `e2e.test.ts`, organized by section.
- [ ] Every test populates a `SuiteRecord` (no test bypasses the audit channel).
- [ ] `afterAll` writes `ind-suite-audit.json` with `passed/total` and per-test detail.
- [ ] At least one round fails on first run and surfaces a real port gap (the cryo suite's value came from catching real bugs, not from passing tests).
- [ ] The 24 happy-path tests from rounds 0-3 are absorbed into the new suite (deleted from their own files OR kept as smoke layer underneath).
- [ ] Screenshots organized by test ID — `.snapshots/IND-N-*` style.

---

## Status as of this doc

Phase 1 code lands in this commit (`e2e.test.ts` foundation + first 12 tests + super-merged happy path). Phases 2-4 are subsequent commits.
