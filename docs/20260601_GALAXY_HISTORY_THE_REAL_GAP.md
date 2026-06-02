# Galaxy History as Global Context — The Real Gap

**Date:** 2026-06-01
**Branch:** `integration/next-phase`
**Trigger:** User reminder that Galaxy already has a History module we previously aimed to use as global memory.

## What we built (the plumbing is in place)

We have a complete Galaxy History integration at the data layer. The user's reminder was right — past sessions built this:

### Wiring already done

| Component | Status |
|---|---|
| `galaxy-api-proxy.ts` has 7 history-content methods | ✓ `getHistoryContents`, `getHistoryDatasets`, `uploadDataset`, `uploadFromUrl`, `createCollection`, `createPairedCollection`, `uploadFromUrlToHistory` |
| Each ExecutionRun stores `galaxyHistoryId` | ✓ schema field + persisted on every run |
| Session carries a Galaxy history | ✓ `req.session.galaxyHistoryId` — first upload creates a history; reused for all subsequent files in that session |
| After-completion fetch | ✓ `routes.ts:429, 510, 7342, 8946` all call `getHistoryContents(invocation.galaxyHistoryId)` to enumerate run outputs |
| Filtering by invocation start time | ✓ `itemCreateTime >= invocation.createdAt` so we attribute outputs to the right run |

So at the **data layer**, BioMate ALREADY has the canonical Galaxy concept of:
- A session = a Galaxy history
- A history = an immutable, dataset-id'd record of every input + output + intermediate
- A run output = an HDA (history dataset association) with stable ID, file path, metadata, peek

This is essentially what Galaxy was designed to be — a per-user history that becomes the user's persistent workspace.

## What we DIDN'T build (the gap)

**The chat agent has no tool to read the Galaxy history.**

Three agent tools registered in `galaxy-assistant.ts` (lines 52, 84, 102):
1. `run_code` — operates on `$DATA_DIR/<dataset_id>/<file>` (a locally-staged subset, not the Galaxy history)
2. `read_file` — same scope
3. `query_domain_knowledge` — RAG over curated bio knowledge

None of them call `galaxyAPIProxy.getHistoryContents(...)`. The agent has no `list_history()`, no `read_history_dataset(hda_id)`, no `find_dataset_in_history(name_pattern)`.

So the data flow works one-way only:
```
                                                       ┌─ getHistoryContents ─→ user-facing API only
User uploads → Galaxy History (HDAs) → Run executes ──┤
                                                       └─ NOT exposed to chat agent
```

The chat agent operates on `$DATA_DIR` — a smaller local stage that gets populated when files are explicitly uploaded *in the current message*. It does NOT know about anything else in the user's Galaxy history (including outputs from runs they just completed).

## Why this matters in practice

Live test from earlier this turn:
> Fire `cyp_ddi_panel` with `mock_mode: true` → produces `validated_compound.json` with aspirin chemistry → stored in Galaxy history as HDA.
> Ask chat agent "what were the IC50s from my last cyp_ddi run?" → agent runs `find $DATA_DIR` → empty → tells user "please upload your file"

The file is **in the user's own Galaxy history right next door** — a single `getHistoryContents(req.session.galaxyHistoryId)` call away. The agent simply doesn't have that tool.

## The fix shape

Three new agent tools (~80 lines total):

### 1. `list_history(after?: timestamp, limit?: int)`
Wraps `galaxyAPIProxy.getHistoryContents(req.session.galaxyHistoryId)`. Returns a structured list of every dataset in the user's current Galaxy history with: hda_id, name, format, size, create_time, state, source_run_id. Filterable by `after` (e.g. `after: "1 hour ago"`).

### 2. `read_history_dataset(hda_id: string, lines?: int)`
Wraps `galaxyAPIProxy.getDatasetContents(hda_id)`. Returns text content or structured preview (CSV → table, JSON → parsed, FASTA → record count + first 5 records). Mirror what `read_file` does, but for HDAs not local files.

### 3. `find_history_dataset(name_pattern: string, format?: string)`
Filter `list_history()` results by name regex + format. Returns the matches. Useful for the agent to bridge from natural language ("the IC50 results from yesterday's cyp_ddi run") to a specific hda_id.

After these, the same `What were the IC50s from my last cyp_ddi run?` prompt would resolve as:
```
agent: find_history_dataset(name_pattern="cyp.*ic50|cyp_inhibition", format="json")
       → [{hda_id: "abc123", name: "cyp_inhibition_results.json", ...}]
       read_history_dataset(hda_id="abc123")
       → {CYP1A2: {IC50_uM: 15.3, ...}, CYP2C9: ..., ...}
       → "Here are the IC50 values from your cyp_ddi run:
          - CYP1A2: 15.3 µM (non-inhibitor)
          - CYP2C9: 19.9 µM
          ..."
```

### Bonus: prompt injection of recent history

Even cheaper than tools: inject a brief block at the top of each chat turn, similar to `_buildCrossSessionContextBlock`:

```typescript
private async _buildHistoryContextBlock(session_id: string): Promise<string> {
  const history = await galaxyAPIProxy.getHistoryContents(this.galaxyHistoryId);
  if (!history?.length) return '';
  const recent = history.slice(0, 10).map((d: any) =>
    `  - hda_id=${d.id} name="${d.name}" format=${d.extension} state=${d.state}`
  ).join('\n');
  return `[Your Galaxy history — datasets available for reference; ask for specific files via tools if needed]\n${recent}\n\n`;
}
```

This single block would make the agent AWARE of the history without needing tool calls. Cheap; no API roundtrip per turn beyond the existing `getHistoryContents`.

## Effort estimate

- **3 new tools**: ~80 lines in `galaxy-assistant.ts`, ~30 lines of dataset-content fetch in `galaxy-api-proxy.ts` if not already there.
- **History context block**: ~15 lines, dropped into existing context assembly.
- **Total**: ~125 lines for a complete fix.
- **Test coverage** (from previous doc's 12 test plan): tests 1, 3, 4, 9 all unblocked.

## Why this is better than my earlier `get_run_outputs(run_id)` proposal

My earlier doc proposed adding `get_run_outputs(run_id)` as a one-off lookup. That works, but it's run-centric — the user has to know the run_id.

Galaxy History is **history-centric** — the natural unit of context the user already thinks in. "What did I run last week?" "What datasets do I have?" "Use that file I uploaded yesterday." These are all natural-language history queries that map directly onto Galaxy's HDA model.

We have the infrastructure. We have the wiring. The only missing piece is exposing it to the agent that talks to users.

## Why this isn't yet shipped

Best guess from reading the code: the chat agent was originally designed around a simpler model — user uploads files in the current message, agent processes them, agent returns answer. The `$DATA_DIR` abstraction made sense for that loop. Galaxy History persistence was added at the data layer (runs, sessions, outputs) but the agent's tool surface didn't get updated to take advantage.

Common when teams build "memory" infrastructure: storage works first, retrieval-from-storage works second, **but exposing-retrieval-as-an-agent-capability** is a third step that's easy to forget because the data IS technically "in the system."

## Recommended next session work

Ship the 3 tools + history context block. That's the **single highest-leverage change** to BioMate's context handling. Closes most of the gap from the 12-test plan in `docs/20260601_CONTEXT_AUDIT_AND_TEST_PLAN.md`. Estimated 2-3 hours including tests.
