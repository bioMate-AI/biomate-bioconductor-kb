# Architecture Findings and Planned Solutions
**Date**: 2026-04-06  
**Branch**: integration/next-phase

---

## Q1 — Inline Data and Clarification Logic

### Finding

`galaxy-assistant.ts` uses regex patterns to detect inline data in user messages (SMILES strings, SRR/ERR/DRR accessions, FASTA sequences, file paths, URLs). When detected, `hasInlineData = true` is added to the LLM system prompt via a rule:

```
ABSOLUTE OVERRIDE: User has provided inline data in their message.
Use this data directly. DO NOT ask for any data — treat the message as having all required inputs.
```

This is too broad. Detecting a SMILES string means one parameter (compound structure) is satisfied. It should not suppress clarification about other missing parameters (target protein, docking mode, force field, etc.).

### Root Cause

The system-prompt rule was written as an all-or-nothing gate. It conflates "we have some data" with "we have all required data."

### Planned Fix (server-side, no E2E changes)

Replace the all-or-nothing rule with a typed data inventory rule. For each detected inline data type, tell the LLM exactly what was provided — and leave it free to ask about anything else:

```
INLINE DATA DETECTED:
- compound_structure (SMILES): CC(=O)Nc1ccc(O)cc1

You have the compound structure. Do NOT ask for it again.
You MAY still ask about other missing required parameters (e.g. target protein,
docking mode, output format) if they are not present in the message.
```

The detection function returns a typed map `{ smiles?: string, accession?: string, sequence?: string, ... }` instead of a boolean. Each detected type generates a scoped suppression rule, not a global one.

**Files to change**: `frontend/server/galaxy-assistant.ts` — `hasInlineData` detection block and system prompt injection.

---

## Q2 — `error` vs `failed` Workflow Status

### Status Enum (canonical)

```typescript
// shared/schema.ts (ExecutionRunStatus)
"configuring" | "queued" | "running" | "paused" | "completed" | "failed" | "cancelled"
```

`'error'` is **not a valid status value**. It was a bug.

### Status Lifecycle

| Status | Origin | Meaning |
|--------|--------|---------|
| `configuring` | `POST /api/workflows/runs` | Run record created; waiting for user to confirm parameters |
| `queued` | After confirm; before executor picks it up | Submitted to Nextflow/Galaxy executor queue |
| `running` | `nfState = 'running'` from Nextflow status poll | Nextflow process is actively running |
| `paused` | User clicks Pause | Run is suspended (Nextflow `-pause` not yet implemented; Galaxy invocation paused) |
| `completed` | `nfState = 'succeeded'` OR Galaxy `state = 'ok'/'scheduled'` | All steps finished successfully |
| `failed` | `nfState = 'failed'/'error'` OR Galaxy `state != 'ok'` | One or more steps failed; run is terminal |
| `cancelled` | User clicks Cancel | Run was manually stopped before completion |

### How `failed` Gets Written (two paths)

**Path 1 — Nextflow status poll** (`routes.ts` status endpoint, called every 2s):
```typescript
// nfState promotion block
if ((nfState === 'succeeded' || nfState === 'failed' || nfState === 'error') 
    && run.execution.status === 'running') {
  const mappedStatus = nfState === 'succeeded' ? 'completed' : 'failed';
  // updates DB record
}
```

**Path 2 — `workflow_completed` SSE event** (emitted by `galaxyPoller` when Galaxy/Nextflow terminates):
```typescript
// routes.ts ~line 435
const desiredStatus = data.state === 'ok' || data.state === 'scheduled' 
  ? 'completed' : 'failed';
// updates DB record
```

Prior to the fix in this branch, Path 2 wrote `'error'` for non-ok states. `'error'` is not in the schema enum, but SQLite/Drizzle stored it as a raw string — no runtime crash, but all downstream `isComplete` checks that look for `'failed'` would miss it.

### Downstream Handling of `failed`

- **Viewer**: Banner shown only for `completed`. For `failed`, the step list shows red indicators; no banner. (By design — failed runs need user to read the error, not dismiss a success message.)
- **E2E tests**: Assertions accept `['completed', 'failed', 'cancelled']` as valid terminal states. Banner assertions conditioned on `=== 'completed'`.
- **Output endpoint**: Scans disk regardless of terminal state; returns whatever files Nextflow wrote before failure.
- **Download commands**: Always generated; may be partial if run failed mid-way.

---

## Q3 — Per-User Galaxy API Key

### Current State (Problem)

All frontend→Galaxy requests use a single admin key from `process.env.GALAXY_API_KEY`:

```typescript
// galaxy-api-proxy.ts constructor
this.apiKey = apiKey || process.env.GALAXY_API_KEY;
this.client = axios.create({
  headers: { 'X-API-Key': this.apiKey }
});
```

One singleton `GalaxyAPIProxy` instance handles all users. Histories, datasets, and invocations created by any user belong to the admin Galaxy account. There is no per-user isolation at the Galaxy layer.

The DB schema already has the right fields:
```typescript
// shared/schema.ts
galaxyUserId: text("galaxy_user_id"),   // never populated
galaxyApiKey: text("galaxy_api_key"),   // never populated
galaxyUsername: text("galaxy_username"), // never populated
```

`auth-service.ts` `register()` creates the BioMate user, syncs billing, but never calls Galaxy to provision a user account.

### Plan

**Step 1 — `galaxy-api-proxy.ts`: Add `provisionGalaxyUser()` and `forUser()`**

```typescript
// New admin-only method (uses admin key)
async provisionGalaxyUser(email: string, username: string, password: string): Promise<{
  galaxyUserId: string;
  galaxyApiKey: string;
  galaxyUsername: string;
}> {
  // POST /api/users  (admin key required)
  const createResp = await this.client.post('/api/users', { email, username, password, active: true });
  const galaxyUserId = createResp.data.id;
  // GET /api/users/{id}/api_key  (admin key required)
  const keyResp = await this.client.get(`/api/users/${galaxyUserId}/api_key`);
  const galaxyApiKey = keyResp.data.key ?? keyResp.data;
  return { galaxyUserId, galaxyApiKey, galaxyUsername: username };
}

// Factory: returns a proxy scoped to a specific user's key
forUser(userApiKey: string): GalaxyAPIProxy {
  return new GalaxyAPIProxy(this.galaxyUrl, userApiKey);
}
```

**Step 2 — `auth-service.ts`: Provision Galaxy user on registration**

After the DB transaction commits, fire-and-forget Galaxy provisioning (same pattern as `syncUserToBilling`):

```typescript
this.provisionGalaxyUser(newUser.id, newUser.email);
```

The provisioning function:
1. Derives a stable Galaxy username from the BioMate user ID (avoids collisions, no PII in Galaxy usernames)
2. Calls `galaxyAPIProxy.provisionGalaxyUser(email, username, password)`
3. Writes `galaxyUserId`, `galaxyApiKey`, `galaxyUsername` back to the DB row

**Step 3 — `routes.ts`: Use per-user proxy for user-scoped operations**

Add helper `getProxyForRequest(req)`:
```typescript
function getProxyForRequest(req: Request): GalaxyAPIProxy {
  const userKey = (req.user as any)?.galaxyApiKey;
  return userKey ? galaxyAPIBackend.forUser(userKey) : galaxyAPIBackend;
}
```

Use it in:
- `createHistory()` calls
- `invokeWorkflow()` calls  
- `uploadDataset()` / `uploadFromUrl()` calls
- `submitToolJob()` calls
- `launchInteractiveTool()` calls

Admin-scoped operations (tool search, workflow generation, version check) keep using the singleton `galaxyAPIBackend`.

**Step 4 — Backfill existing users**

Add a one-shot migration endpoint or script that iterates users with `galaxyUserId IS NULL` and provisions them.

### Risk / Rollback

- If Galaxy provisioning fails during registration, the BioMate account is still created; the user falls back to the shared admin key (current behavior). A background retry job (or re-trigger on next login) can complete provisioning later.
- Zero schema migration needed — columns already exist in `shared/schema.ts`.
- No downtime — fallback to admin key is always available.

---

## Q4 — Mid-Conversation Interruption Handling

### What "interruption" means here

The user clarified: not a new chat window — a tangent sub-dialogue inserted mid-conversation in the same chat session. Example: user is configuring a germline variant calling pipeline, then asks "by the way, what does GROMACS stand for?", then returns to the pipeline discussion.

### Current Mechanism

**Context window**: `galaxy-assistant.ts` sends only the last `CONTEXT_WINDOW = 6` messages to the LLM. Older messages are not sent (they are summarized into a separate `sessionMemory` field injected at the top of the prompt).

**Session memory**: `sessionMemory` is a rolling text summary appended to the system prompt. It captures: current workflow intent, parameters collected so far, pending prereq checks. Updated after each turn.

**N4 session store**: The Python backend `WorkflowSessionStore` tracks the last active step per `session_id`. This is used to inject "Active pipeline" context into `generate_workflow` calls.

### How an interruption propagates

1. User sends the tangent question ("what does GROMACS stand for?")
2. `galaxy-assistant.ts` includes it in the 6-message context window
3. `sessionMemory` describes the prior workflow intent
4. LLM sees: prior workflow context in system prompt + tangent in conversation → correctly answers the tangent
5. User's next message returns to the pipeline
6. The tangent question + answer are now in the 6-message window
7. LLM sees: tangent exchange + prior workflow context in memory → should recover context

### Current Gap

The `sessionMemory` update logic does not explicitly handle "tangent then return." If the tangent was about a different domain (e.g., asking about GROMACS while configuring germline pipeline), `sessionMemory` may get overwritten with GROMACS-related context from the tangent response, polluting the next turn's context injection.

Specifically in `generateResponse()`:
```typescript
// sessionMemory is updated after every response
sessionMemory = buildMemory(latestResponse, currentWorkflow);
```

If the tangent triggers a workflow generation attempt (e.g., GROMACS query → finds `gromacs_protein_md`), the `sessionMemory` gets updated with GROMACS context, and the user's return to the germline pipeline gets confused LLM context.

### Planned Fix

Add a **tangent detection** pass before `sessionMemory` update:
- After generating a response, classify whether the current turn was "a tangent" (answer to a factual/informational question unrelated to the active workflow) vs "a workflow step" (collected parameter, ran prereq, confirmed, etc.)
- If classified as tangent: do not overwrite `sessionMemory`; keep the prior workflow context intact
- Use `classifyWithLLM` (already exists in `routes.ts`) for this classification

This is a targeted, low-risk change in `galaxy-assistant.ts`.
