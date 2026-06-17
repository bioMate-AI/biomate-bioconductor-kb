# IntentClarificationCard — End-to-End Verification Report

**Date:** 2026-06-16
**Test:** `frontend/e2e/intent-clarification.e2e.ts`
**Result:** **3/3 tests PASS (2.3m total runtime)**

## Method

Scene-based E2E against the local dev server on `:5001`. Uses Playwright's `page.route()` to intercept the first `/api/chat/stream` POST and inject `context.testForceIntent='tool_search'` — this deterministically triggers the cross-intent ambiguity detection without depending on Gemini non-determinism. Backend gates `testForceIntent` behind the `E2E_TEST_TOKEN` header in `routes.ts` so the hook cannot be exploited in production.

## Server setup

```
PORT=5001
SCHEMA_GROUNDED_EXTRACTION=1
E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only
CORS_ORIGINS=http://localhost:5001   # required — without this Vite client modules 500 on the dev mode
```

## Test results

### Test 1 — API: forced misclassification fires the card

Directly POST `/api/chat/stream` with `context.testForceIntent='tool_search'` and assert the SSE `final` event's `metadata.intentClarification`:

- ✅ Payload present
- ✅ `originalIntent === 'tool_search'`
- ✅ `originalMessage` carries the user query
- ✅ `candidates.length >= 2` with `workflow_generation` marked `primary: true`
- ✅ Negative case (forceIntent=`workflow_generation`) → no card payload
- ✅ Negative case (forceIntent=`tool_search` + non-design query "What is the typical hERG IC50…") → no card payload

### Test 2 — UI: card renders, primary chip click re-submits, workflow panel opens

Full browser flow:

1. Login as shared fixture user (`lifeifei163361@163.com`)
2. Send the design query via real DOM input
3. Route intercept injects `testForceIntent='tool_search'`
4. Wait for `[data-testid="intent-clarification-card"]` to be visible
5. Assert primary chip is present and labeled "Run a design workflow"
6. Click primary chip → frontend dispatches `biomate:intent-clarification-resolved` → chat-with-artifacts re-submits with `context.intentOverride='workflow_generation'`
7. Wait for the bispecific workflow card to appear in the second assistant reply

All assertions pass.

**Screenshots:**

- `02-card-rendered.png` — full card with prompt, three candidate chips (highlighted **Run a design workflow** primary, plus secondary "Just search for tools" and "Answer as a research question"), skip-to-rephrase link, and the diagnostic reason badge ("Why I'm asking: matched patterns — design-verb+modality")
- `03-after-pick.png` — original message re-submitted automatically; BioMate "thinking" indicator visible
- `04-workflow-rendered.png` — second BioMate reply begins with "Bispecific Format Triage (CrossMab) —" confirming the workflow_generation path

### Test 3 — UI: skip button hides card without re-submit

1. Same setup as Test 2
2. Click `[data-testid="intent-clarify-skip"]`
3. Assert no new user-message bubble appears in the next 3s (re-submit MUST NOT fire)

Passes.

## Bug found and fixed mid-audit

`chat-interface.tsx:954` hand-builds the assistant message's `metadata` object with a fixed whitelist of fields. Neither `intentClarification` nor `paramClarifications` was in the list — the backend payload landed correctly in `data.metadata` but the frontend dropped it when constructing the persisted message. The IntentClarificationCard's render gate (`message.metadata?.intentClarification?.candidates?.length > 0`) was therefore never satisfied.

Caught only by this UI E2E run — the API path test passed cleanly because it inspects the SSE response directly without going through the persistence path. The fix forwards both clarification fields explicitly in the message-metadata construction. Without this commit the IntentClarificationCard (and the ParamClarificationCard before it) would have shipped silently broken on the rendered chat surface.

## What this report proves

- The cross-intent ambiguity detector (`_detectCrossIntentAmbiguity`) fires for all 3 design-shaped patterns (design-verb + modality, "verb modalities for", in-vivo therapy)
- The `intentClarification` payload survives the SSE → message-metadata pipeline (after the missing-forward fix)
- The IntentClarificationCard renders with correct content, primary-button highlighting, and three candidates
- Clicking the primary chip re-submits the original message with `context.intentOverride='workflow_generation'` (via the `onRegisterSendMessage` parent-registered sender added in this PR)
- The backend respects the override on the second pass and routes to `workflow_generation`, producing the workflow card in the next assistant reply
- The skip button does NOT trigger a re-submit (user is expected to rephrase)

12/12 unit tests (`intentAmbiguity.local.ts`) still green; full `tsc --noEmit` clean.
