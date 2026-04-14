# Claude Code Architecture Analysis & BioMate Integration Plan

**Date:** 2026-04-01  
**Source:** `downloads/claude-code-source-code-main` (v2.1.88, ~1,884 TypeScript files)  
**Audit basis:** Full BioMate codebase review — see summary table below

---

## 1. What BioMate Already Has (Do Not Re-implement)

The existing audit confirms most Claude Code patterns are already present in BioMate:

| Feature | BioMate Status | Key Files |
|---|---|---|
| Parallel tool execution | **EXISTS** | `galaxy-assistant.ts:187` (`Promise.all`), `domain_specialist.py:16` (`ThreadPoolExecutor`) |
| Authentication / quota gating | **EXISTS** | `auth-middleware.ts`, `quota-middleware.ts` |
| Pre-execution validation hooks | **EXISTS** | `workflow-prerequisites-validator.ts`, `dataset-validator.ts` |
| Plan mode / step approval UI | **EXISTS** | `pilot-run-panel.tsx`, `task-list.tsx`, `workflow-chain-plan.tsx` |
| Task management (arcs) | **EXISTS** | `conversation-state.ts`, task arc fields in `routes.ts` |
| Context compression | **EXISTS** | `context-compressor.ts:45–100` (threshold 80% of 200k tokens, Claude summary) |
| Sub-agent / domain specialist spawning | **EXISTS** | `agent_orchestrator.py`, `domain_specialist.py`, `unified_intent_router.py` |
| Domain specialist routing + merge | **EXISTS** | `domain_router.py`, `enhanced_domain_router.py`, 22-domain taxonomy; `workflow_assembler.py` handles cross-domain dedup + LLM conflict resolution |
| Session persistence | **EXISTS** | PostgreSQL via Drizzle ORM; `conversation_messages` table (`ltm-schema.ts:159`); `SessionMemoryRepository.addMessage()` persists every message; `project_episodes` for full interaction records |
| Streaming tool results (SSE) | **EXISTS** | `routes.ts` lines 2783–4844, `workflow-sse.ts` |

---

## 2. Genuine Gaps (What's Missing or Partial)

### 2.1 MCP (Model Context Protocol) Integration — **MISSING**

No MCP code exists anywhere in BioMate. Claude Code has a full client covering stdio, SSE, streamable HTTP, and WebSocket transports with OAuth 2.0 per-server, automatic backoff reconnect, and output truncation.

**Value for BioMate:**
- Expose Galaxy + Nextflow as an MCP server → external agents (including Claude Code itself) can orchestrate BioMate workflows
- Consume external bioinformatics MCP servers (e.g., NCBI Entrez, Ensembl, PubMed) without building custom integrations for each

**What to build:**
```python
# backend/mcp/galaxy_mcp_server.py  — stdio transport
# Tools to expose:
#   search_workflows(query)
#   run_workflow(workflow_id, params)
#   get_run_status(run_id)
#   get_output_files(run_id)
#   upload_file(path)
```

Recommended transport: stdio (simplest, no auth surface) for local use; streamable HTTP for remote/cloud deployments.

---

### 2.2 Per-tool Permission Rules (RBAC) — **PARTIAL**

BioMate has subscription tier + billing quota enforcement (`auth-middleware.ts`, `quota-middleware.ts`) but no per-tool allow/deny rules based on user role.

**What's missing:**
- No way to say "this user can search workflows but not execute Nextflow jobs"
- No glob-pattern or tool-name-based rule matching (like Claude Code's `alwaysAllow`/`alwaysDeny` lists)
- No `isDestructive()` / `isReadOnly()` flags on tools to drive automatic confirmation dialogs

**What to add:**
```typescript
// Add to each tool definition
interface BioMateTool {
  id: string
  isDestructive: boolean      // triggers confirmation dialog
  isReadOnly: boolean         // safe to run without approval
  requiredRole: 'guest' | 'user' | 'admin'  // minimum role
}
```

Minimal addition: add `requiredRole` and `isDestructive` fields to the tool registry and check them in the execute path — no new middleware needed.

---

### 2.3 Pluggable Hook Registry — **PARTIAL**

BioMate has event emitters (`galaxyPoller.on(...)`) and pre-execution validators, but no general-purpose pre/post tool hook registry where new hooks can be registered without modifying core code.

**What's missing:**
- No `PreToolUse` / `PostToolUse` hook points
- Adding a new validation (e.g., "check S3 bucket before every Nextflow run") requires modifying `nextflow_executor.py` directly

**What to add:**
```python
# backend/lib/galaxy/ai/hooks/hook_registry.py
class HookRegistry:
    _pre_execution: list[Callable] = []
    _post_execution: list[Callable] = []

    def register_pre(self, fn): self._pre_execution.append(fn)
    def register_post(self, fn): self._post_execution.append(fn)

    async def run_pre(self, ctx: ExecutionContext) -> HookResult:
        for hook in self._pre_execution:
            result = await hook(ctx)
            if result.blocked: return result
        return HookResult(blocked=False)
```

Existing validators (`workflow-prerequisites-validator.ts`, quota checks) can be migrated to register themselves here — no behavior change, just better extensibility.

---

### 2.4 AsyncLocalStorage / Per-request Context Isolation — **MISSING**

BioMate passes conversation context explicitly through function parameters or reads it from the database per request. There is no `AsyncLocalStorage` (Node.js) or `contextvars` (Python) per-request isolation.

**Why it matters:**
- Without request-scoped context, background tasks (polling, SSE) that outlive the original request can accidentally share or leak state
- Logging/tracing has no automatic request correlation — hard to tie a Galaxy API error back to the specific user request that caused it

**What to add (Node.js side):**
```typescript
// frontend/server/request-context.ts
import { AsyncLocalStorage } from 'async_hooks'

export const requestContext = new AsyncLocalStorage<{
  userId: string
  sessionId: string
  requestId: string
  conversationId: string
}>()

// In routes.ts middleware:
app.use((req, res, next) => {
  requestContext.run({ userId: req.user?.id, sessionId: req.sessionID,
                       requestId: crypto.randomUUID(), conversationId: req.body?.conversationId },
    next)
})
```

This enables structured logging, trace IDs, and safe background task context without threading context through every function signature.

---

### 2.5 Universal Destructive Operation Confirmation — **PARTIAL**

`qc-gate-modal.tsx` exists for workflow approval but there is no universal pattern applied to all destructive operations (dataset deletion, S3 path overwrite, Galaxy history deletion).

**What to add:**
- Add `isDestructive: true` flag to relevant tool definitions (covered in 2.2 above)
- Wire a generic `ConfirmationDialog` component that triggers whenever `isDestructive === true` before the tool executes
- Existing `alert-dialog.tsx` UI component can be reused as-is

---

### 2.6 Runtime Feature Flag System — **PARTIAL**

BioMate uses environment variables for feature gating (`BIOMATE_ENABLE_THINKING`, `UX_FEEDBACK_ENABLED`, etc.) but has no runtime flag system that can change without redeployment.

**Gap:** Currently toggling a feature for one user or A/B testing requires a server restart.

**Options (in order of effort):**
1. **Minimal:** Add a `feature_flags` table to the existing Drizzle DB; read at request time — no external dependency
2. **Medium:** Integrate GrowthBook (same system Claude Code uses) — open-source, self-hostable, supports user cohorts
3. **Heavy:** LaunchDarkly / Unleash — skip unless team size justifies it

For BioMate's current scale, option 1 (DB-backed flags) is sufficient and avoids new infrastructure.

---

## 3. What Claude Code Has That BioMate Intentionally Doesn't Need

| Claude Code Feature | Why BioMate Doesn't Need It |
|---|---|
| Git worktree isolation for agents | BioMate agents operate on Galaxy/S3 data, not git repos |
| Terminal UI (React/Ink) | BioMate is a web app — existing React frontend covers this |
| Vim mode / voice input | Out of scope for bioinformatics platform |
| Plan mode as a separate permission mode | Covered by existing `workflow-chain-plan.tsx` + PilotRunPanel |
| JSONL session transcripts | Covered by existing Redis + Drizzle DB persistence |
| Bun compile-time DCE feature flags | Overkill for BioMate's release cadence; DB-backed flags are enough |
| Multi-agent swarm with async mailboxes | Covered by existing `agent_orchestrator.py` + `DomainSpecialistPool` |

---

## 4. Revised Integration Priorities

### Priority 1 — Small effort, high value (1 sprint each)

**MCP Server (galaxy_mcp_server.py)**  
Effort: ~1 week. Exposes 5 Galaxy/Nextflow operations. Unlocks Claude Code ↔ BioMate interop and future external MCP tool consumption.

**Per-request AsyncLocalStorage**  
Effort: ~2 days. Add to `routes.ts` middleware. Unblocks structured logging and eliminates a class of background-task state bugs.

**RBAC tool flags (`isDestructive`, `requiredRole`)**  
Effort: ~3 days. Add fields to tool registry + one check in execute path + reuse `alert-dialog.tsx` for confirmation.

### Priority 2 — Medium effort, good value (2–3 weeks)

**Pluggable hook registry (`hook_registry.py`)**  
Migrate existing validators into registered hooks. Enables adding S3/license/accession checks without touching `nextflow_executor.py`.

**DB-backed feature flags**  
Add `feature_flags` table. Replace scattered env-var checks with a unified `isEnabled(flagName, userId)` call.

### Priority 3 — Strategic, defer to next quarter

**MCP client** (consuming external bioinformatics MCP servers)  
Only build after MCP server is stable and there's a confirmed external server to connect to (NCBI, Ensembl, etc.).

---

## 5. Files to Reference from Claude Code

If implementing the above, these Claude Code files are the best reference:

| What to build | Claude Code reference |
|---|---|
| MCP server/client | `src/services/mcp/client.ts`, `src/entrypoints/mcp.ts` |
| Per-request async context | `src/utils/` (AsyncLocalStorage patterns) |
| RBAC / tool permission rules | `src/utils/permissions/permissions.ts` (52KB) |
| Pluggable hook registry | `src/utils/hooks/AsyncHookRegistry.ts` (8.9KB) |
| Runtime feature flags | `src/services/analytics/` (GrowthBook integration) |
