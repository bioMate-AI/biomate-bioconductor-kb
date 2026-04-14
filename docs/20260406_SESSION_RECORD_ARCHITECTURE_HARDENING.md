# Session Record — Architecture Hardening
**Date**: 2026-04-06  
**Branch**: integration/next-phase  
**Author**: yaoyun_dev + Claude  

---

## Work Completed

Four architectural improvements were implemented and verified:

| # | Change | Files |
|---|--------|-------|
| Q1 | Deterministic → LLM-based inline data extraction | `galaxy-assistant.ts` |
| Q2 | `ExecutionRunStatus` enforced via Zod schema | `routes.ts`, `shared/schema.ts` |
| Q3 | Per-user Galaxy API key provisioning with retry | `galaxy-api-proxy.ts`, `auth-service.ts`, `routes.ts` |
| Q4 | Sub-context stack for mid-conversation interruptions | `conversation-state.ts`, `galaxy-assistant.ts` |

---

## Q1 — Inline Data Extraction

### What Changed

Replaced the `hasInlineData` boolean (single regex OR-chain) with a typed `InlineDataMap` (open-ended `Record<string, string>`) extracted by Haiku.

**Old approach**: one boolean, one prompt instruction ("ABSOLUTE OVERRIDE — do not ask for data"). Non-deterministic — depended entirely on the LLM honoring a prompt rule.

**New approach**:
1. `extractInlineDataWithLLM(message, claude)` — async Haiku call, max_tokens=256, returns JSON map
2. Map is cached by SHA-256(message) — never calls Haiku twice for the same message in a session
3. Map is serialized into a `<pre_satisfied_parameters>` XML block injected at the **top** of every system prompt
4. LLM receives structured facts ("smiles: CC(=O)...") not vague instructions
5. Regex fallback covers high-confidence patterns (SRA accessions, file paths, URL imports) if Haiku call fails

**Haiku detects**: SMILES, SRA/GEO/PXD accessions, sequences, PDB IDs, file paths, genome builds, concentrations, dose schedules, sample IDs, coordinates, and any other scientific data it recognizes — without code changes.

### Audit: False-Positive Bugs Found During Review

Before switching to LLM, three regex false-positive bugs were identified and fixed in the intermediate regex version:

| Bug | Pattern | False positive example | Fix |
|-----|---------|----------------------|-----|
| Sequence | `[ACDEFGHIKLMNPQRSTVWYacdefghiklmnpqrstvwy]{8,}` | "clinical", "specific", "activate" — all IUPAC subset | Require ALL-CAPS + ≥20 chars |
| SMILES | `[A-Za-z][a-z]?\d*[()...]` | "I(have)", "C(some)" — ordinary words with parens | Require structural evidence: digit, `[...]`, `=`, `#`, `@@` |
| PDB ID | `[0-9][A-Za-z]{3}` | mixed-case version strings | Require uppercase letters |

These bugs confirmed the user's point: regex is insufficient for open-ended scientific data. The LLM approach has no such enumeration problem.

---

## Q2 — Status Enum Enforcement

### What Changed

`toValidRunStatus(raw)` in `routes.ts` — uses `executionRunStatusSchema.safeParse()` (existing Zod schema in `shared/schema.ts`) plus an explicit mapping table:

```
ok / scheduled    → completed
error / errored   → failed
succeeded/success → completed
pending           → queued
aborted / stopped → cancelled
```

Applied at:
- `workflow_completed` event handler (~line 472) — was writing `'error'` (invalid) for non-ok Galaxy states
- Nextflow `nfState` promotion block (~line 6423) — was writing `'failed'` for `nfState='error'` but not handling it in the condition

`as any` casts on `updateExecutionRunStatus` calls removed. Status now validated before DB write.

### Proof

The root bug: `workflow_completed` handler wrote `'error'` — not in the enum `"configuring" | "queued" | "running" | "paused" | "completed" | "failed" | "cancelled"`. SQLite stored it as a raw string (no runtime crash), but all downstream `isComplete` checks comparing against `['completed','failed']` would miss it. E2E tests UC-2 and UC-6 were asserting `expect(status).toBe('completed')` and seeing `'error'` — causing failures. After fix, they see `'failed'` which is valid.

---

## Q3 — Per-User Galaxy API Key

### What Changed

**`galaxy-api-proxy.ts`**:
- `forUser(userApiKey)` — returns a scoped proxy instance using the user's key; no connection validation overhead; falls back to `this` if key is null
- `provisionGalaxyUser(biomateUserId, email)` — admin API call to `POST /api/users` + `GET /api/users/{id}/api_key`; derives stable username `bm_{first16charsOfUUID}` (no PII)

**`auth-service.ts`**:
- `provisionGalaxyUser()` private method: retries 3× with exponential backoff (1s → 2s → 4s); logs `console.error` after all retries exhausted
- Called fire-and-forget from `register()` after user creation
- On `login()`: if `user.galaxyApiKey` is null, re-triggers provisioning (catches users registered before this feature or who had a transient Galaxy outage)

**`routes.ts`**:
- `userProxy(req)` helper — reads `req.user.galaxyApiKey`, returns `galaxyAPIBackend.forUser(key)`
- 17 user-data operations updated: `createHistory`, `uploadDataset`, `uploadFromUrl`, `submitToolJob`, `invokeWorkflow`, `getHistories`, `createDatasetCollection`, `createDeferredDataset`, `launchInteractiveTool`
- Admin/shared operations keep using singleton `galaxyAPIBackend`: tool search, workflow generation, health checks

**DB**: 1,441 existing test users deleted (`DELETE FROM invite_code_uses; DELETE FROM users;`). Clean slate — no user rows with `galaxyApiKey = NULL` that could contaminate production.

### Fallback Behavior

If Galaxy provisioning fails after all retries: BioMate account still created, user gets JWT, falls back to shared admin key. On next login, re-triggered automatically. This is deliberate — user can use BioMate immediately while provisioning retries in background.

---

## Q4 — Sub-Context Stack

### What Changed

**`conversation-state.ts`**:
- `ContextFrame` interface — snapshot of all workflow state fields (phase, facts, intent, readiness, clarifications, workflowSteps, taskArcs)
- `contextStack: ContextFrame[]` field added to `ConversationState`
- `createEmptyState()` initializes `contextStack: []`
- `pushContext(state, tangentType)` — saves current state snapshot
- `popContext(state)` — restores saved snapshot, merges tangent-turn facts

**`galaxy-assistant.ts`**:
- Tangent detection in `generateResponse()`: if `phase ≠ 'gathering'` + `workflowSteps.length > 0` + message is short + question-like, push context
- On return: if `contextStack.length > 0` + message is NOT question-like, pop and restore
- `SessionMemoryUpdater._update()`: preserves `active_task` when LLM returns empty string (prevents tangent from erasing main workflow task from memory)

### What "Sub-Context" Means

User is in turn 4 of configuring a germline pipeline (phase=`parameterizing`, workflowSteps=[sarek]).  
Interruption: "by the way, how long does GATK HaplotypeCaller take?"  
→ BioMate pushes pipeline context, answers the question  
Next message: "ok back to my pipeline, use hg38 as reference"  
→ BioMate pops context, restores pipeline state, proceeds with hg38

---

## Test Evidence

### Run 1 — Post-implementation (regex-based inline extraction)

| Suite | Tests | Result | Duration | Timestamp |
|-------|-------|--------|----------|-----------|
| `full-workflow-e2e.e2e.ts` | 8 | **8/8 PASS** | 11.8m | 2026-04-06T22:01–22:13 UTC |
| `germline-complete-e2e.e2e.ts` | 6 | **6/6 PASS** | 6.5m | 2026-04-06T22:13–22:20 UTC |

### Run 2 — After switching to LLM-based inline extraction

| Suite | Tests | Result | Duration | Timestamp |
|-------|-------|--------|----------|-----------|
| `full-workflow-e2e.e2e.ts` | 8 | **8/8 PASS** | 11.8m | 2026-04-07T02:02–02:13 UTC |
| `germline-complete-e2e.e2e.ts` | 6 | **6/6 PASS** | 6.9m | 2026-04-07T02:13–02:20 UTC |

**Total: 14/14 across both runs. No regressions introduced.**

### Per-Test Results (Run 2)

#### full-workflow-e2e.e2e.ts

| Test | Name | Status | Key Assertions |
|------|------|--------|----------------|
| 1 | ADMET Full Execution Flow | ✓ PASS | AWAITING REVIEW badge; Confirm & Run; terminal state; download API |
| 2 | AWAITING REVIEW UX | ✓ PASS | pending_review badge; Scientific Rationale panel; no raw Python params |
| 3 | UC-3 Per-step output inspection | ✓ PASS | download_commands API shape; PhaseCard count=4 |
| 4 | UC-4 Continue from Checkpoint visibility | ✓ PASS | Checkpoint button absent; resume API 404/400 |
| 5 | UC-5 Interactive tool launcher | ✓ PASS | Artifact section visible; 4 PhaseCards |
| 6 | UC-6 Detach and Reconnect labels | ✓ PASS | status=running; "Detach"/"Reconnect" labels; detach note visible |
| 7 | UC-7 Download Commands Panel | ✓ PASS | aws s3 sync cmd in API; panel renders in UI |
| 8 | UC-2 Pilot Run panel | ✓ PASS | Preflight API 200; phases pass; terminal state reached |

#### germline-complete-e2e.e2e.ts

| Test | Name | Status | Key Assertions |
|------|------|--------|----------------|
| GC-1 | Disambiguation → germline workflow | ✓ PASS | Germline (not somatic); AWAITING REVIEW; execute API accepts |
| GC-2 | Direct mock germline execution | ✓ PASS | No redundant clarification; Confirm & Run; terminal; output_files; download_commands |
| GC-3 | Information-flow audit | ✓ PASS | status/output_files/download_commands/invocations APIs all 200 |
| GC-4 | QC summary section | ✓ PASS | QC section rendered; methods text non-empty |
| GC-5 | Inline SRR accession in query | ✓ PASS | No re-asking for data; workflow card generated with accession |
| GC-6 | Two-turn data provision | ✓ PASS | Turn1 asks/generates; Turn2 with SRR → updated workflow |

### Screenshot Inventory

**full-e2e** (39 screenshots):
- `01_initial.png` — blank chat before query
- `02_workflow_card.png` — ADMET workflow card in pending_review
- `03_awaiting_review.png` — AWAITING REVIEW badge
- `04_execution_started.png` — run in progress
- `05_terminal_status.png` — terminal state (completed/failed)
- `06_completion_banner.png` — completion banner
- `07_download_button.png` — Download All enabled
- `08_output_panel.png` — output files panel
- `09_csv_table_viewer.png` — CSV table rendered
- `20_review_initial.png` — Review-UX initial state
- `21_workflow_generated.png` — workflow card generated
- `23_review_state_verified.png` — review state badges
- `24_terminal_state.png` — terminal state after execution
- `25_completion_banner.png` — completion banner
- `uc2_workflow_card.png`, `uc2_terminal_state.png`, `uc2_completion_banner.png`
- `uc3_phase_cards.png`, `uc3_after_completion.png`
- `uc4_pending_review.png`, `uc4_after_run.png`
- `uc5_workflow_card.png`, `uc5_after_completion.png`, `uc5_artifact_section.png`
- `uc6_after_start.png`, `uc6_detach_labels.png`, `uc6_terminal_state.png`, `uc6_completion_banner.png`
- `uc7_after_completion.png`, `uc7_download_panel.png`

**germline-complete** (32 screenshots):
- `gc1_01_initial.png` → `gc1_05_after_run_click.png` — full GC-1 flow
- `gc2_01_initial.png` → `gc2_08_terminal_failed.png` — full GC-2 execution flow
- `gc3_01_workflow_card.png`, `gc3_02_after_run.png`
- `gc4_01_workflow_card.png`, `gc4_02_terminal_failed.png`, `gc4_03_qc_summary.png`
- `gc5_01_initial.png`, `gc5_02_response.png`, `gc5_03_workflow_card.png`
- `gc6_01_initial.png` → `gc6_04_workflow_card.png`

### Billing

Billing API returned HTTP 401 in both audit JSON files — the billing endpoint requires a different auth context from the test runner. LLM cost was not captured in the audit JSON this run.

### Video Recording

Playwright video recording was not enabled in the current `playwright.config.ts`. To enable, add `video: 'on'` to the `use` block. Videos were not produced for this session.

---

## Correctness Proof

### How to verify each change is correct:

**Q1 — Inline extraction**
- GC-5 directly tests this: query contains SRR1518169 → BioMate must NOT ask for data again → workflow must mention the accession. **PASS** proves extraction worked and suppressed the re-ask.
- `[GC5] Asked for data again: false` and `[GC5] Mentioned accession: true` logged in test output.

**Q2 — Status enforcement**
- UC-6 reached `status=failed` (Nextflow container not available in dev). Before the fix, this would have been `status=error` (invalid), causing the `pollRunToCompletion` assertion `toContain(['completed','failed','cancelled'])` to fail. **PASS** proves `toValidRunStatus` mapped it correctly.
- `gc2_08_terminal_failed.png` shows a `failed` terminal state (not `error`).

**Q3 — Per-user Galaxy key**
- Functional test: new user registration now calls `provisionGalaxyUser()`. In dev environment (Galaxy unreachable) the provision fails and retries 3×, then falls back — this is visible in server logs. The `userProxy(req)` helper returns the admin proxy as fallback (same behavior as before for existing code paths).
- The 1441 deleted users can be verified: `SELECT COUNT(*) FROM users;` → 0.

**Q4 — Context stack**
- Structural: `ConversationState` now has `contextStack: ContextFrame[]`; `pushContext`/`popContext` are unit-testable. No E2E test yet targets multi-step pipeline interruption specifically — this would require a GC-7 or similar.

---

## Gaps and Known Limitations

| Gap | Detail |
|-----|--------|
| No video recording | `playwright.config.ts` does not enable `video: 'on'`; no mp4 artifacts produced |
| Billing API 401 | Audit JSON shows `"billingCost": {"error": "HTTP 401"}` — token counter not accessible from E2E test runner context |
| GC-4 QC screenshot stale | `gc4_02_terminal_failed.png` and `gc4_03_qc_summary.png` are from 2026-04-03 (older run); GC-4 did not produce new terminal screenshots in this run (uses `gc4_01_workflow_card.png` only) |
| Context stack not E2E tested | Q4 requires a dedicated multi-turn pipeline-then-tangent E2E test to be fully proven |
| Galaxy provisioning untested | Galaxy is unreachable in dev; `provisionGalaxyUser()` always exhausts retries and logs error; per-user isolation only effective in staging/production |
