# Agent Architecture — Implementation Log

**Date**: 2026-04-04  
**Branch**: integration/next-phase  
**Status**: Core implemented, TypeScript clean

---

## What Was Built

### Phase 1: Code execution tool

**New file**: `frontend/server/code-runner.ts`
- `runCode(req: CodeRunRequest): Promise<CodeRunResult>`
- Runs Python / R / bash in a Node.js `spawn()` subprocess
- Stages Galaxy input datasets to `/tmp/biomate_code/<session>/input/<dataset_id>/`
- Captures stdout/stderr (truncated to 8KB/4KB), scans `/output/` for result files
- Configurable timeout (default 15s, max 60s)

**New endpoint**: `POST /api/code/run` (routes.ts)
- Calls `runCode()` with `galaxyAPIProxy.downloadDataset` for input staging
- Returns `{stdout, stderr, exit_code, output_files, duration_ms}`

### Phase 2: File reading tool

No new backend needed — `GET /api/outputs/:id/preview` already exists.
Tool handler `_toolReadFile()` in galaxy-assistant.ts calls it.

### Phase 3: Domain knowledge tool

Tool handler `_toolQueryKnowledge()` in galaxy-assistant.ts:
- `cryo_em` domain → `POST /api/cryo_em/context` (existing RAG pipeline)
- Other domains → `POST /api/knowledge/query` (extensible)

### Agent loop in galaxy-assistant.ts

**New constant**: `BIOMATE_TOOLS: Anthropic.Tool[]`
- 3 tools defined: `run_code`, `read_file`, `query_domain_knowledge`
- (`dispatch_workflow` deferred — requires replacing the parallel generation flow)

**New type**: `AgentToolEvent` (exported)
- `type: 'tool_call' | 'tool_result'`
- Carries `tool_use_id`, `name`, `input`, `output`, `error`, `duration_ms`

**Modified**: `generateResponse()` — replaced single API call with agent loop
- Tools only enabled when NOT in thinking mode (Anthropic constraint) AND `onToolEvent` callback is provided
- First turn: streaming — text deltas via `onResponseDelta`, tool_use blocks accumulated from stream events
- Subsequent turns (after tool results): non-streaming
- Max 5 iterations before forcing termination
- `_executeTools()` dispatches all tool_use blocks in parallel, emits `onToolEvent` for each

**New methods**:
- `_executeTools(blocks, context, onToolEvent)` — parallel dispatch, returns Anthropic `tool_result` messages
- `_toolRunCode(input)` — calls `runCode()` via dynamic import
- `_toolReadFile(input, context)` — calls `/api/outputs/:id/preview`
- `_toolQueryKnowledge(input)` — calls domain knowledge endpoints

**Modified signatures** (backward-compatible, `onToolEvent` optional):
- `processMessage(msg, ctx, onResponseDelta?, onToolEvent?)`
- `generateResponse(..., onToolEvent?)`
- `processMultiIntent(..., onToolEvent?)`

### SSE streaming of tool events

**Modified**: `POST /api/chat/stream` (routes.ts)
- Passes `(event) => safeSend("tool_event", event)` as `onToolEvent`
- `tool_event` SSE events carry `AgentToolEvent` JSON

### Frontend

**New component**: `frontend/client/src/components/code-execution-block.tsx`
- `CodeExecutionBlock` — renders a single `ToolBlock` (call + result merged)
- Language badge, collapsed/expandable code (3-line default preview)
- Status: pending spinner, green check, red X
- Duration display
- Stdout (truncated 2KB, expandable), output files with preview
- Works for `run_code`, `read_file`, `query_domain_knowledge` (each has appropriate layout)

**Modified**: `chat-interface.tsx`
- Accumulates `tool_event` SSE events into `toolBlocksMap` (keyed by `tool_use_id`)
- Merges `toolBlocks` array into placeholder message `metadata` during streaming
- On `final` event: includes `toolBlocks` in payload
- `chatHistoryService.getSession()` used for metadata merge (not replacement)

**Modified**: `chat-message.tsx`
- Renders `message.metadata?.toolBlocks` as `CodeExecutionBlock` list above the text response

---

## What Doesn't Change

- Existing workflow dispatch path (parallel `generateWorkflow()` → `generateResponse()`) is unchanged
- The `dispatch_workflow` tool is not yet wired (planned separately — requires architectural change to workflow generation flow)
- Galaxy Jupyter/RStudio still available for long-running interactive sessions
- All existing tool search, parameter filling, workflow execution untouched

---

## Known Limitations / Next Steps

1. **`dispatch_workflow` tool** not yet implemented — the current parallel flow generates workflows before `generateResponse()`. Wiring `dispatch_workflow` as a tool call requires the workflow generation to move inside the agent loop.

2. **Tool execution only when streaming** — tools are only enabled when `onToolEvent` callback is provided (streaming path). The non-streaming `/api/chat` endpoint does not use tools. This is intentional for now (streaming is the primary chat path).

3. **No system prompt trimming yet** — the static `DOMAIN_SPECIALIST_GUIDANCE` blocks are still injected. Removing them (Step 7 from the plan) is a separate change once tool calls are verified in production.

4. **`_toolReadFile` internal fetch** — uses `localhost:PORT` self-call. If the port is not 5000, reads will fail and fall back to direct Galaxy dataset proxy.

5. **`query_domain_knowledge` fallback** — for domains other than `cryo_em`, calls `/api/knowledge/query` which may not exist yet on the Galaxy backend. Returns a structured fallback message.

---

## TypeScript Status

Zero `error TS` at implementation end.
