# Galaxy History → Agent Context: Handoff

**Date:** 2026-06-02
**Status:** 1 connection done (pending merge), 1 partial, 1 not started
**Goal:** Make BioMate's chat agent able to reason about past datasets, past runs, and past outputs — so users can say "use the FASTQ from last week" or "do the same as my last RNA-seq run but with PARP1" and the agent has the data to answer.

This work is **complementary** to the existing `WorkflowHistoryDialog` (sidebar, shipped 2026-05-21). That dialog is human-facing navigation; this work is agent-facing reasoning. Both should ship.

---

## Connection 1 — Agent tool for past datasets (HDAs)

**Status: NOT STARTED**

The agent has 3 registered tools in `frontend/server/galaxy-assistant.ts:51-120` (BIOMATE_TOOLS): `run_code`, `read_file`, `query_domain_knowledge`. None of them touch Galaxy History.

**What to add:**

1. New tool `list_history` in `BIOMATE_TOOLS`:
   ```ts
   {
     name: 'list_history',
     description: 'List the user's recent uploaded datasets (FASTQ, VCF, h5ad, etc.) from Galaxy History. Use when the user refers to "my last upload", "the FASTQ I sent earlier", or asks what files they have.',
     input_schema: {
       type: 'object',
       properties: {
         limit: { type: 'integer', description: 'How many recent datasets to return (default 20)' },
         file_type: { type: 'string', description: 'Optional filter, e.g. "fastq", "vcf", "h5ad"' },
       }
     }
   }
   ```

2. Optional second tool `get_dataset` for reading metadata/head of a specific HDA:
   ```ts
   { name: 'get_dataset', input_schema: { hda_id: 'string' } }
   ```

3. Tool handlers should call existing Galaxy endpoints:
   - `GET /api/histories/{history_id}/contents` (datasets list)
   - `GET /api/datasets/{dataset_id}` (single dataset metadata)
   - Backend already exposes these via `backend/lib/galaxy/webapps/galaxy/api/histories.py:184+`
   - Use the existing `galaxyProxy` client in `frontend/server/`

**Suggested location:** add `_toolListHistory()` next to existing tool handlers in `galaxy-assistant.ts` (search for `_toolRunCode` for the pattern).

**Test plan:**
- Unit: tool dispatch returns a valid HDA list shape
- E2E: send "what files have I uploaded recently?" → assistant tool-calls `list_history` → response lists at least one dataset

---

## Connection 2 — Inject recent workflow runs into the prompt

**Status: PARTIAL** — pattern exists for memory/corrections, not for runs.

Already in `galaxy-assistant.ts:1682-1739`:
- `_buildEpisodeMemoryBlock(userId)` injects long-term memory
- `_buildCorrectionContextBlock(userId)` injects past correction context

What's **missing**: a `_buildRecentRunsBlock(userId)` that does the equivalent for prior workflow runs.

**What to add:**

1. New method on `GalaxyAssistant` after the two existing blocks (around `galaxy-assistant.ts:1760`):
   ```ts
   async _buildRecentRunsBlock(userId: string): Promise<string> {
     const runs = await storage.getExecutionRuns(userId, undefined, undefined, 5);
     if (!runs?.length) return '';
     const lines = runs.map(r =>
       `- ${r.id.slice(0,8)} · ${r.workflowName} · ${r.execution?.status} · started ${r.startedAt} · ${Object.keys(r.execution?.outputs ?? {}).length} outputs`
     );
     return [
       '### Your recent workflow runs (most recent first)',
       ...lines,
       '(refer to a run by its 8-char ID when the user asks to reuse params or outputs)'
     ].join('\n');
   }
   ```

2. Wire into the system prompt assembly where `_buildEpisodeMemoryBlock` is currently invoked.

**Infrastructure already present:**
- `storage.getExecutionRuns()` is already used at `routes.ts:7915` for AutoFix retry logic — proven to work.
- ExecutionRun rows have `execution.parameters` and `execution.outputs` — both useful to the agent.

**Performance:** limit 5 runs. Don't dump full outputs; just count + status. Outputs become referenceable via Connection 3.

**Test plan:**
- Send a workflow, complete it, then in a new chat say "show me my last run" → assistant cites the run ID from injected context.

---

## Connection 3 — Reference prior-run outputs as new-workflow inputs

**Status: DONE (pending merge)** — implemented in the `workflow-chain-panel` worktree.

### What's already in `main`

`routes.ts:2898-2950` accepts the virtual history URI `run:<runId>`:
- `GET /api/galaxy/histories/run:<runId>/datasets` lists Nextflow output S3 files for that run
- Lets the file-picker UI show prior-run outputs as a "virtual history"

Gap on main: **the agent doesn't know this URI scheme exists** — so it never suggests reusing prior outputs.

### What's in `/home/yzhang/biomate_worktrees/workflow-chain-panel`

`backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py`:
- `_resolve_outputs_for_run(run_id, next_workflow_input_types)` (line ~234) — auto-matches a run's output files to the next workflow's input params by file extension (`*.fastq` → `reads`, `*.vcf` → `variants`, etc.)
- `_apply_connection_handoffs()` (line ~161) — wires multi-step chain handoffs
- API:
  - `POST /api/workflows/chain` (line ~804) submit
  - `GET /api/workflows/chain/{chain_run_id}` (line ~896) poll
  - `POST /api/workflows/runs/{run_id}/resolve-outputs` (line ~972) resolve outputs to next-step inputs

This **is** the missing infrastructure. Once merged, Connection 3 is functionally complete.

### What still needs to happen after merging the worktree

1. Add agent tool `list_run_outputs(run_id)` so the LLM can surface output filenames in chat (and suggest them in next-step param overrides).
2. Document the `run:<runId>` URI scheme in `BIOMATE_TOOLS.system_prompt_addendum` so the agent learns it can pass `run:abc12345:outputs/variants.vcf` as a file param value.

---

## Suggested handoff order

1. **Merge `feature/workflow-chain-panel-4a` worktree into integration/next-phase.** Resolves Connection 3 infrastructure-side. (Largest amount of code, mostly done by another agent — only the merge risk to manage.)
2. **Connection 1** (`list_history` tool, ~80 LOC + handler). Standalone, no dependencies.
3. **Connection 2** (`_buildRecentRunsBlock`, ~30 LOC). Standalone, follows existing pattern.
4. **Connection 3 finishing touches** (`list_run_outputs` tool + prompt addendum, ~50 LOC). Depends on step 1 being merged.

Each step is independently testable and shippable. Total estimated effort: 1 focused day.

---

## Key file references

| Component | Path |
|---|---|
| Agent tool registry | `frontend/server/galaxy-assistant.ts:51-120` |
| Existing memory injection blocks | `frontend/server/galaxy-assistant.ts:1682-1760` |
| Execution-run storage | `frontend/server/storage.ts:503-535` (`getExecutionRuns`) |
| Virtual history URI handler | `frontend/server/routes.ts:2898-2950` |
| Chain panel implementation | `~/biomate_worktrees/workflow-chain-panel/backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` |
| Galaxy History API (backend) | `backend/lib/galaxy/webapps/galaxy/api/histories.py:184+` |
| Existing human-facing dialog | `frontend/client/src/components/workflow-history-dialog.tsx` (Gap 4, 2026-05-21) |

---

## Out of scope (deliberately)

- Indexing: don't ingest all past chats/runs into a vector DB. Recent-N injection is cheaper and explainable.
- Cross-user reuse: every query is scoped to the current `userId`.
- Editing/deleting from chat: the agent reads history but doesn't mutate it.
