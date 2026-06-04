# C1+C2+C3 test plan — Galaxy History agent context

**Date:** 2026-06-03
**Scope:** `frontend/server/galaxy-assistant.ts` — `list_history`, `list_run_outputs`, `_buildRecentRunsBlock`.

## Layering

| Layer | Goal | Where | Cost |
|---|---|---|---|
| **L1 — Unit** | Per-handler edge cases. Pure functions, no real Anthropic / Gemini / DB. | `frontend/server/galaxy-assistant-history-block.test.ts` | ~ms |
| **L2 — Integration** | Wiring: confirm `_buildRecentRunsBlock` actually lands in the prefix string passed to the LLM; confirm dispatch reaches handler. | Same test file, separate `describe` block. | tens of ms |
| **L3 — E2E** | Send a real chat message to dev; verify a real LLM call uses the injected context and dispatches `list_history`. | Manual curl + log inspection on dev. | minutes |

## L1 — unit cases (target: ~30 total, currently 15)

### `_buildRecentRunsBlock` (C2)

Existing (4):
1. Empty list → empty string.
2. Renders id/name/status/date/output-count per row.
3. Storage error → empty string (non-fatal).
4. Requests exactly 5 runs.

Add:
5. **`startedAt` missing** — uses `createdAt` fallback.
6. **All timestamps missing** — renders "recent" not "Invalid Date".
7. **Workflow name missing** — renders "unnamed", does not crash.
8. **Status missing** — renders "unknown".
9. **Outputs is null / not an object** — renders "0 outputs", no crash.
10. **Mixed mode** — sandbox + production runs both surface.
11. **More than 5 runs in store** — storage call still asks for 5 (proven), the prefix never exceeds 5 lines.

### `_toolListHistory` (C1)

Existing (5):
1. Returns formatted runs when userId present.
2. workflow_filter case-insensitive substring.
3. status_filter.
4. limit clamping ([1, 25]; 0 → default; -n → 1).
5. No userId → graceful note, no DB call.

Add:
6. **Combines filters** — `workflow_filter` + `status_filter` AND-together.
7. **Empty result after filter** — count=0, runs=[], no error.
8. **paramKeys length never exceeds 6** even when run had many params.
9. **paramKeys reads execution.parameters then falls back to workflowDefinition.parameters** when execution params absent.
10. **Userid as a number is coerced safely** to string (no crash).
11. **Default limit is exactly 10** (regression for the JS truthiness).
12. **Storage method called with `(userId, undefined, undefined, 50)`** — sufficient overscan for filters.
13. **Storage rejection → `{ error }` shape, not throw** — same non-fatal contract.

### `_toolListRunOutputs` (C3)

Existing (6):
1. Returns files with canonical `param_uri`.
2. `ext_filter` case-insensitive, strips leading dot.
3. Cross-user refusal.
4. Missing `run_id` → error, no DB call.
5. Run not found → error + hint.
6. Empty outputs map → `empty_hint`.

Add:
7. **No userId in context but run has userId** — still returns (admin / internal use), no scope check applies.
8. **Run has userId=null and context userId="u1"** — returns (no owner = public/internal).
9. **Output value shapes**: string path, `{path}`, `{s3_uri}`, raw string filename (no path).
10. **More than 50 outputs** — capped at 50 in `files` array, `count` still reflects post-filter total.
11. **`run_id` with whitespace** — trimmed before lookup.
12. **`ext_filter` with multi-dot ext** (e.g. `.vcf.gz`) — matches "vcf.gz" only when stored that way (intentional simplicity).
13. **Storage rejection → `{ error }` shape, no throw**.

### Cross-cutting

14. **All three handlers handle storage `undefined` return gracefully** — never throws (already covered for some, generalize).
15. **No handler ever leaks fullId without owner check** — verify in both paths.

## L2 — integration

Two cases verifying the wiring beyond unit isolation:

**I-1: prefix assembly includes the recent-runs block.**
- Mock `memoryService.episodes.getRecentUserEpisodes` to return `[]`.
- Mock `memoryService.users.getUserCorrections` to return `[]`.
- Mock `storage.getExecutionRuns` to return 2 runs.
- Call `processMessage` (or whatever the public entry is) with `userId` set and `previousMessages: []` (first-message gate).
- Spy on the system prompt that gets sent to the (mocked) Anthropic client and assert it contains `"Your recent workflow runs"` and both 8-char ids.

**I-2: BIOMATE_TOOLS includes the three history tools.**
- Trivially import `BIOMATE_TOOLS` and assert the three tool names exist with `input_schema.properties` matching the documented contract. Guards future renames / accidental deletions.

## L3 — E2E against dev (optional, run once Galaxy is stable)

Manual recipe:

```bash
BASE="https://dev-public.biomate.ai"
TOK="x-e2e-test-token: biomate-e2e-bypass-token-dev-only"

# 1. Confirm there are some prior runs for the test user
curl -s -m 20 "$BASE/api/workflows/runs/overview?limit=5" -H "$TOK" | jq '.runs[].id'

# 2. Send a chat referencing prior runs
curl -s -m 60 "$BASE/api/chat" -H "Content-Type: application/json" -H "$TOK" \
  -d '{"message":"what workflow runs do I have from this week?","sessionId":"e2e-history-test"}' \
  | head -c 800

# Expect: response references at least one 8-char id and the words "run" / "completed" / etc.
```

```bash
# 3. Inspect Galaxy log to confirm tool dispatch fired
ssh dev "sudo docker logs biomate-dev-frontend --since 5m 2>&1 | grep -E '(list_history|list_run_outputs|C2 recent runs injected)'"
```

Acceptance for L3: prompt injection log line emitted AND at least one tool dispatch line for `list_history` if the user message requires it.

## Out of scope

- Performance benchmarks (these are small, in-memory checks).
- DB integration with a real Postgres (mocked storage is sufficient; storage tests cover that layer separately).
- Fuzz tests on URI shape — the backend resolver in `routes.ts:2898` already handles those bounds.
