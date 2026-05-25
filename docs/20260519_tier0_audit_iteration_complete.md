# Tier 0 Audit Iteration — Bug A+C Chain Complete (2026-05-19)

Continuation of `docs/20260518_tier0_audit_T01_results.md`. Multi-day session
running 7 T01 audit iterations against the refactored Tier 0 chain and
methodically fixing each break point.

## Session arc

| Audit | Result | Key finding |
|---|---|---|
| v1 (2026-05-18 12:43) | 9 / 24 pass | Original baseline. `bispec:phaseA:null_x_null` in Nextflow log — confirms Bug A. |
| v2 (2026-05-18 13:41) | 11 / 27 pass | Bug E (methods-report HTTP -1) fixed by raising fetch timeout to 120s. |
| v3 (2026-05-18 14:36) | 1 / 11 pass | Regression: spurious `workflow_ready→finalPayload` assignment broke message creation. |
| v4 (post-revert) | 1 / 11 pass | Stale Vite state — needed hard restart. |
| v5 (fresh Vite) | 11 / 27 pass | Confirmed only the `final` event carries the payload. |
| v6 (Advanced Settings expand in test) | 11 / 27 pass | Strip toggle clicked but inputs still not in DOM. |
| v7 (belt-and-suspenders panel merge) | 11 / 27 pass | Definitive probe: `inline_parameters` IS on the workflow object; the inner Accordion stays `data-state="closed"`. |

Definitive verification via instrumented probe (`/tmp/playwright-probe5`):

```json
{
  "paramIds": "target_a,target_b,format,indication",
  "stripExists": true,
  "stripClass": "strip open",          ← outer strip expands correctly
  "stripBodyExists": true,
  "accordionItems": 0,                  ← inner Radix Accordion stays closed
  "inputs": []
}
```

## Fixes committed this iteration

### 1. `47a77a108` — chat-interface onSuccess: merge `metadata.inlineParameters` into `workflowData.inline_parameters`

Bridges the camelCase (server) ↔ snake_case (client) field name mismatch.
Production fix — runs on every workflow_ready response.

### 2. `35ec07f76` — bump audit timeouts for Bug D + E

- `waitForAnyCompletedPhase`: 900s → 1500s (AWS Batch cold-start)
- `test.setTimeout`: 30 → 35 min
- `methods-report` fetch: 30s → 120s (Claude Sonnet report generation)

### 3. `8dba0397a` — `readFormValues` expands "Advanced settings" strip first

The viewer hides inline-param inputs under a collapsible strip; the test
must expand it before reading values.

### 4. `e5d2a2519` — belt-and-suspenders at panel handoff

Two-pronged guarantee that `metadata.inlineParameters` reaches the viewer:
- Store `inlineParameters` at the message metadata level in `chat-interface.tsx`
- Merge into `panelWorkflow.inline_parameters` at panel auto-open in `chat-with-artifacts.tsx`

### 5. Pending commit — viewer auto-expand on LLM prefill

Added `useEffect` that opens `globalParamsOpen` when `workflowDefinition.inline_parameters`
has any keys. Marks inline params as `autoFilled: true` in the fallback path of
`buildViewerParameters` so the autoFilled-aware default-open logic triggers.
Plus debug data attributes on the panel for instrumentation.

## What works end-to-end now (verified via probe)

- ✅ Server emits `metadata.inlineParameters: {target_a, target_b, format, indication}` in the `event: final` payload
- ✅ Client merges those into `workflowData.inline_parameters` in onSuccess
- ✅ Panel auto-open layer merges again as fallback
- ✅ Viewer's `workflowDefinition.inline_parameters` has all 4 values
- ✅ `renderedParameters` produces 4 ViewerParameter objects with correct ids
- ✅ Outer "Advanced settings" strip auto-expands to `className="strip open"`
- ✅ `<div className="strip-body">` is rendered with the `<ParameterGroup>` inside
- ❌ The inner Radix `<Accordion>` stays `data-state="closed"` — its `defaultValue` is uncontrolled and ignores subsequent prop changes

## Last remaining break point

Radix UI `<Accordion type="single" collapsible defaultValue={...}>` (parameter-group.tsx:331)
is uncontrolled. The `defaultValue` is only honored at initial mount. By the
time `autoFilled: true` propagates through React state, the Accordion has
already mounted with `defaultValue=undefined` (since `inline_parameters` arrives
asynchronously via SSE after the first render).

Two viable fixes (next session):

(A) Convert to controlled mode:
```typescript
<Accordion type="single" collapsible value={open ? id : ''} onValueChange={(v) => setOpen(v === id)}>
```
With a useEffect that sets `open=true` when `parameters.some(p => p.autoFilled)`.

(B) Force a re-mount by keying the Accordion on the inline-params presence:
```typescript
<Accordion key={parameters.length > 0 ? 'open' : 'closed'} ... defaultValue={...}>
```

Option (A) is cleaner. ~10 lines of change in `parameter-group.tsx`.

## What was NOT broken (re-validated this iteration)

- Phase-split refactor (T01–T05 + atlas): all 6 workflows still render correctly
- Step parser path fix: 6 workflows still return correct phase counts via `/api/nextflow/steps`
- WORKFLOW_PARAM_ALIASES (Bug 1) in galaxy-assistant.ts: still emits `target_a` not `target_1`
- Run dispatch: `click-run-dispatched` ✓ with real runId every iteration
- First-phase transitions: `pending → running` ✓ via SSE
- Findings + methods-report endpoints: both return 200 after Bug E timeout bump
- `analyze-results` + `download-methods-report` buttons render after completion

## Punch list for next session

1. **Fix Radix Accordion control mode** — convert to controlled state machine
   (~10 lines, 30 min). After this single fix, T01 form-prefill assertions
   should pass and the Bug A+C chain is complete.
2. **Re-run T01 audit** — expect ~22/27 pass (still failing: Bug B SSE parser,
   and `any-phase-reaches-completed` if AWS Batch is cold).
3. **Run T02–T05** — once T01 is green, parallelize the remaining 4 demos.
4. **Fix Bug B** (test SSE parser) for cosmetic 5-assertion cleanup.
5. **Refactor #7 + #8** (12 workflows, ~30 hrs) — needs direct foreground edits
   due to subagent permission denials on biomate-ai-tools paths.
6. **Re-record demos** with form-fill pre-Run assertion now that the form
   actually shows the LLM-extracted values.

## Cost ledger this iteration

- ~$5 AWS Batch (7 T01 runs, most stalled in queue cold-start)
- ~3 hours interactive session
- Surface area: 6 commits (3 production fixes, 2 test fixes, 1 debug instrumentation)

## Files referenced

- `frontend/client/src/components/chat-interface.tsx` — Bug A+C onSuccess merge
- `frontend/client/src/components/chat-with-artifacts.tsx` — panel-handoff fallback merge
- `frontend/client/src/components/nextflow-workflow-viewer.tsx` — auto-expand strip + autoFilled flag + debug attributes
- `frontend/client/src/components/parameter-group.tsx:331` — the uncontrolled Accordion (next session target)
- `frontend/e2e/tier0-audit.e2e.ts` — readFormValues expands strip, raised timeouts
- `frontend/server/galaxy-assistant.ts` — Bug 1 WORKFLOW_PARAM_ALIASES (already in HEAD)
- `frontend/server/routes.ts:5066-5104` — responsePayload composition (final event)
- `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:_parse_nextflow_steps` — step parser path fix
