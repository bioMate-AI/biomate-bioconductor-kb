# Connections 1 & 2 — Galaxy History context for the agent (DONE)

**Date:** 2026-06-03
**Branch:** integration/next-phase
**Commits:** `c7914b317` (impl + tests) → `3058bb222` (test fix)
**Predecessor doc:** `docs/20260602_GALAXY_HISTORY_AGENT_CONTEXT_HANDOFF.md`

## TL;DR

C1 and C2 from the Galaxy History handoff are implemented, tested (9/9), and pushed. **C3 does NOT need any UI work** — the `run:<runId>:datasets` virtual-history URI scheme is already live in `routes.ts:2898`. The remaining work for C3 is purely agent-side: a small `list_run_outputs(run_id)` tool and a one-paragraph prompt addendum so the LLM learns it can pass `run:<fullId>:outputs/variants.vcf` as a file param. ~50 LOC, same file. No UI panel needed.

## What the agent can now do

Before today the chat agent had three tools (`run_code`, `read_file`, `query_domain_knowledge`) and zero awareness of the user's past workflow runs. After today:

1. **It can answer "do the same as my last RNA-seq run with PARP1 instead"** — by calling the new `list_history` tool to surface recent runs with their params summary.
2. **It sees recent runs on every first message** — `_buildRecentRunsBlock` injects up to 5 most-recent runs into the system prompt alongside the existing memory/correction blocks, so the LLM has the context even without an explicit tool call.

## C1 — `list_history` tool

### Definition (`BIOMATE_TOOLS`, galaxy-assistant.ts:120-141)

```ts
{
  name: 'list_history',
  description: 'List the user's recent workflow runs (id, workflow name, ...)',
  input_schema: {
    type: 'object',
    properties: {
      limit: { type: 'number', description: 'How many recent runs (default 10, max 25)' },
      workflow_filter: { type: 'string', description: 'Substring filter on workflowName' },
      status_filter: {
        type: 'string',
        enum: ['running', 'completed', 'failed', 'cancelled'],
      },
    },
  },
}
```

### Output shape

```json
{
  "userId": "...",
  "count": 3,
  "filter": { "workflow_filter": null, "status_filter": null },
  "runs": [
    {
      "id": "abcdef12",
      "fullId": "abcdef1234567890",
      "workflow": "ode-signaling-simulation",
      "status": "completed",
      "startedAt": "...",
      "completedAt": "...",
      "paramCount": 2,
      "paramKeys": ["drug_name", "target_node"],
      "outputCount": 2
    }
  ],
  "usage_hint": "..."
}
```

### Handler (`_toolListHistory`, galaxy-assistant.ts:6226-6273)

- Reads `context.userId`; if missing, returns `{ runs: [], note: 'no userId in context' }` with no DB call (graceful in admin/test contexts).
- Pulls the last 50 runs from `storage.getExecutionRuns(userId, undefined, undefined, 50)`, applies optional filters, slices to `limit`.
- Returns compact per-run rows. No raw params/outputs dumps — agent can call other tools to dig deeper.
- Clamps `limit` to `[1, 25]`. `limit: 0` is treated as "use default 10" (JS truthiness).
- Wired into **both** dispatch loops (Gemini at line 1439, Claude at line 6032).

## C2 — recent-runs prompt block

### Method (`_buildRecentRunsBlock`, galaxy-assistant.ts:6276-6300)

Mirrors the existing `_buildEpisodeMemoryBlock` (P1) / `_buildCorrectionContextBlock` (P2) shape:
- Reads up to 5 most-recent runs.
- One compact line per run: `  • abcdef12 · workflow-name · status · YYYY-MM-DD · N outputs`.
- Returns empty string on empty list **or any storage error** — non-fatal.

### Injection (galaxy-assistant.ts:2144-2168)

```ts
const [crossSessionBlock, episodeBlock, correctionBlock, recentRunsBlock] =
  await Promise.all([
    this._buildCrossSessionContextBlock(message, uid),
    this._buildEpisodeMemoryBlock(message, uid),          // P1
    this._buildCorrectionContextBlock(uid),               // P2
    this._buildRecentRunsBlock(uid),                      // C2 (new)
  ]);

// ... concatenation order: corrections → episodes → recent-runs → cross-session
if (recentRunsBlock) {
  prefix += recentRunsBlock;
  log('C2 recent runs injected for user ' + uid);
}
```

Fires only on the **first message** of a session (same gate as P1/P2). After that, the conversation already carries the relevant context.

## Tests (9/9 passing)

`frontend/server/galaxy-assistant-history-block.test.ts` — mocks `storage`, `@anthropic-ai/sdk`, and `@google/generative-ai` so no DB or real API keys are required.

| # | Suite | Test |
|---|---|---|
| 1 | C2 | empty string when user has no runs |
| 2 | C2 | renders id, name, status, date, output count for each run |
| 3 | C2 | swallows storage failure (returns "") |
| 4 | C2 | asks storage for exactly 5 runs (prompt-budget guard) |
| 5 | C1 | populated `runs` array when userId present |
| 6 | C1 | case-insensitive `workflow_filter` works |
| 7 | C1 | `status_filter` works |
| 8 | C1 | clamps `limit` to `[1, 25]`; `limit: 0` → default 10; negative → 1 |
| 9 | C1 | no userId → `{ runs: [], note: 'no userId...' }` without DB call |

Run locally:

```bash
cd /home/yzhang/biomate/frontend
DATABASE_URL=postgres://test@localhost/test \
  ./node_modules/.bin/vitest run ../frontend/server/galaxy-assistant-history-block.test.ts
```

## What's NOT in this work (deliberate scope)

- **C3 — no UI work, no chain panel.** Earlier handoff doc had referenced an in-flight `feature/workflow-chain-panel-4a` worktree as the C3 owner. That direction is dropped — no chain UI is being shipped. The good news: C3's functional goal (let the agent attach a prior run's output as a next workflow's input) can be done **entirely agent-side**. The `run:<runId>:datasets` virtual-history URI handler is already live at `routes.ts:2898-2950`. The remaining work is:
  1. `list_run_outputs(run_id)` tool — handler reads outputs from a single ExecutionRun and returns the file list. ~30 LOC, identical pattern to `_toolListHistory`.
  2. One-paragraph prompt addendum telling the LLM that file params accept `run:<fullId>:outputs/<filename>` URIs.
  Total: ~50 LOC, same file. No UI changes.
- **No raw HDA / uploaded-file listing** — this surfaces RUNS, not uploads. Uploads are surfaced separately via `session.uploadedDatasets` (see `routes.ts:3045`). The original handoff doc had noted both as candidate C1 surfaces; chose runs because of higher info density and direct reuse value.
- **No `get_dataset` companion tool** — `read_file` already covers single-dataset previews. Don't add a redundant surface.
- **No write operations** — agent reads history, never mutates. Re-running a workflow with prior params is still a user-confirmed click in the panel.

## Notes for whoever picks up the rest

1. **Auto-sync is aggressive.** During this session, an earlier draft of these same edits to `galaxy-assistant.ts` was silently wiped between edit and commit. Always `git add && git commit` immediately after a meaningful edit to this file. (Same pattern that strips `from __future__ import annotations` from `nextflow_executor.py`; see `backend/tests/test_nextflow_executor_future_annotations.py` for one of the CI guards.)
2. **The non-fatal contract matters.** Both methods catch all errors and return empty/error-noted output. Do not change this — if storage hiccups while a user is chatting, we drop the injection silently rather than break the response stream.
3. **Test-mocking pattern.** The existing `execution-env-policy.test.ts` uses vitest. The new test uses `vi.mock` for storage AND the Anthropic/Gemini SDKs — the SDKs throw `dangerouslyAllowBrowser` in the vitest runtime otherwise. Follow this pattern for any future test that exercises `new GalaxyAssistant(...)`.

## File index

- `frontend/server/galaxy-assistant.ts` — tool def at line 120, dispatch wires at 1439 + 6032, injection at 2148, handlers at 6226 + 6276
- `frontend/server/galaxy-assistant-history-block.test.ts` — 9 cases
- `docs/20260602_GALAXY_HISTORY_AGENT_CONTEXT_HANDOFF.md` — original plan
- `docs/20260603_C1_C2_AGENT_HISTORY_DONE.md` — this file
