# D4 — LLM Workflow Error Analysis: Gap Analysis & Implementation Plan

**Date**: 2026-04-04  
**Source**: Audit finding in `docs/nextPhase/20260330_SESSION_FIXES_AND_AUDIT.md`  
**Status**: LLM path exists but blocked by env configuration; regex fallback active

---

## Current Architecture

```
Workflow fails
  → frontend auto-triggers (status === 'failed', last 30 log lines)
  → POST /api/workflows/explain_error (routes.ts — 20s timeout passthrough)
  → POST /api/workflows/explain_error (ai_assistant.py Galaxy backend)
      ├── if ANTHROPIC_API_KEY in env → Claude Haiku, 400 tokens, returns JSON
      └── else → 4-pattern regex fallback
  → response: {error_type, human_summary, suggested_fix, chat_prompt, llm_used}
  → nextflow-workflow-viewer.tsx shows "What went wrong" + "Fix & Retry via Chat" button
```

The LLM path (Claude Haiku) is fully implemented. The ONLY reason it falls back to regex is that `ANTHROPIC_API_KEY` is not present in the Galaxy backend process environment. The regex fallback covers 4 of 8 error types; the other 4 (`data_format`, `permission_denied`, `nextflow_syntax`, anything complex) return "unknown".

---

## Root Cause

`ANTHROPIC_API_KEY` is available in the Node.js frontend environment (already used by `galaxy-assistant.ts` for all chat calls) but is NOT forwarded to the Galaxy Python backend process. The backend checks `os.getenv("ANTHROPIC_API_KEY")` at call time — no startup warning, silent regex fallback.

---

## Solutions

### Solution 1 — Move error analysis to the Node.js layer (recommended)

**Principle**: The Node.js frontend already has `ANTHROPIC_API_KEY`. Move the LLM call there. The Galaxy backend only needs to surface the error log (which it already does via the existing `GET /api/workflows/runs/:id/logs` endpoint).

**Changes:**

`routes.ts` — replace the passthrough proxy with a full implementation:

```typescript
app.post("/api/workflows/explain_error", optionalAuth, express.json(), async (req, res) => {
  const { run_id, workflow_name, error_log } = req.body as {
    run_id?: string; workflow_name?: string; error_log: string;
  };
  
  // If no log provided but run_id given, fetch last 200 lines from Galaxy backend
  let log = error_log || '';
  if (!log.trim() && run_id) {
    try {
      const galaxyUrl = process.env.GALAXY_URL || 'http://localhost:8081';
      const r = await fetch(`${galaxyUrl}/api/nextflow/status/${run_id}`);
      if (r.ok) {
        const d = await r.json() as any;
        log = (d.log_tail || d.logs || []).slice(-200).join('\n');
      }
    } catch {}
  }
  
  const apiKey = process.env.ANTHROPIC_API_KEY;
  
  if (!apiKey) {
    // Regex fallback — extended to all 8 types
    return res.json(regexFallback(log));
  }
  
  try {
    const Anthropic = (await import('@anthropic-ai/sdk')).default;
    const client = new Anthropic({ apiKey });
    const completion = await client.messages.create({
      model: 'claude-haiku-4-5-20251001',
      max_tokens: 500,
      temperature: 0.1,
      system: ERROR_ANALYSIS_SYSTEM_PROMPT,
      messages: [{
        role: 'user',
        content: `Workflow: ${workflow_name || 'unknown'}\n\nError log (last 4000 chars):\n${log.slice(-4000)}`
      }],
    });
    const text = completion.content[0].type === 'text' ? completion.content[0].text : '';
    const cleaned = text.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    const result = JSON.parse(cleaned);
    result.llm_used = true;
    return res.json(result);
  } catch (err: any) {
    // LLM failed — use extended regex fallback
    return res.json({ ...regexFallback(log), llm_error: String(err?.message) });
  }
});
```

**Advantages**:
- `ANTHROPIC_API_KEY` is guaranteed present (same process as all other Anthropic calls)
- No Galaxy backend change needed
- Galaxy backend `explain_error` endpoint can be removed or kept as unused
- Consistent with the Phase 1 tool-use architecture direction

---

### Solution 2 — Forward env var to Galaxy backend (minimal change)

Add `ANTHROPIC_API_KEY` to the Galaxy backend process env (in `start_backend.sh` or the `.env` file the backend reads).

```bash
# backend/.env or start_backend.sh
export ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
```

**Advantages**: Zero code change, immediately enables LLM path.  
**Disadvantages**: Env var management across two processes; silent failure risk remains if key rotates.

---

### Solution 3 — Extended regex fallback (defense in depth, do regardless)

Whether Solution 1 or 2 is chosen, extend the regex to cover all 8 error types. Currently 4/8 covered; the remaining 4 fall through to "unknown".

**Current coverage (4 patterns):**
```python
"no such file" / "file not found"  → missing_file
"docker" + ("pull" / "error")      → docker_pull  
"memory" / "oom" / "out of memory" → resource_limit
"missing" + "param"                → missing_parameter
```

**Add (4 more patterns):**
```python
# data_format
r"(invalid format|unexpected.*format|parse.*error|cannot parse|malformed|not a valid)" → data_format

# permission_denied
r"(permission denied|access denied|cannot write|read-only filesystem|EACCES|EPERM)" → permission_denied

# nextflow_syntax  
r"(unexpected token|groovy.*error|script.*compilation|nextflow.*syntax|workflow.*script.*error)" → nextflow_syntax

# tool_not_found (bonus — common Nextflow error)
r"(command not found|executable.*not found|No such.*executable|program.*not.*found)" → tool_not_found
```

**TypeScript equivalent** (for Solution 1):
```typescript
function regexFallback(log: string): ErrorExplanation {
  const l = log.toLowerCase();
  if (/no such file|file not found|cannot find file/.test(l))
    return { error_type: 'missing_file', human_summary: 'A required input file was not found.', suggested_fix: 'Check that your input file paths are correct and the files exist.', chat_prompt: 'My workflow failed because an input file was not found. Can you help me fix the file path?', llm_used: false };
  if (/docker.*pull|pull.*docker|container.*pull/.test(l))
    return { error_type: 'docker_pull', human_summary: 'Docker could not pull the required container image.', suggested_fix: 'Ensure Docker is running and you have internet access.', chat_prompt: 'My workflow failed with a Docker pull error. What should I check?', llm_used: false };
  if (/out of memory|oom killer|memory limit|killed.*memory/.test(l))
    return { error_type: 'resource_limit', human_summary: 'The job ran out of memory.', suggested_fix: 'Increase the memory allocation in the workflow parameters.', chat_prompt: 'My workflow failed with an out-of-memory error. How do I increase memory?', llm_used: false };
  if (/missing.*param|required.*param|param.*missing|no value.*param/.test(l))
    return { error_type: 'missing_parameter', human_summary: 'A required parameter is missing.', suggested_fix: 'Provide all required parameter values before running.', chat_prompt: 'My workflow failed because a required parameter was missing. Which parameters do I need?', llm_used: false };
  if (/invalid format|cannot parse|malformed|not a valid|unexpected.*format/.test(l))
    return { error_type: 'data_format', human_summary: 'An input file has an unexpected format.', suggested_fix: 'Verify your input file format matches what the workflow expects.', chat_prompt: 'My workflow failed with a data format error. Can you help me check my input files?', llm_used: false };
  if (/permission denied|access denied|cannot write|eacces|eperm/.test(l))
    return { error_type: 'permission_denied', human_summary: 'The workflow cannot read or write a required file.', suggested_fix: 'Check file and directory permissions for the input and output paths.', chat_prompt: 'My workflow failed with a permission denied error. How do I fix file permissions?', llm_used: false };
  if (/unexpected token|groovy.*error|compilation.*error|nextflow.*syntax/.test(l))
    return { error_type: 'nextflow_syntax', human_summary: 'There is a syntax error in the workflow script.', suggested_fix: 'Review the workflow script for syntax errors and ensure all parameters are valid.', chat_prompt: 'My workflow failed with a Nextflow syntax error. Can you help me fix the script?', llm_used: false };
  if (/command not found|executable not found|no such.*executable/.test(l))
    return { error_type: 'tool_not_found', human_summary: 'A required tool or command was not found in the container.', suggested_fix: 'Ensure the correct container image is specified and all tools are installed.', chat_prompt: 'My workflow failed because a command was not found. What container or tool is missing?', llm_used: false };
  return { error_type: 'unknown', human_summary: 'An unexpected error occurred during workflow execution.', suggested_fix: 'Review the error log below for details.', chat_prompt: 'My workflow failed. Can you help me understand this error log?', llm_used: false };
}
```

---

### Solution 4 — Better log context (complement to 1 or 2)

**Current**: Frontend sends last 30 log lines + `errorMessage`.

**Issues**:
- Multi-stage errors need context from step boundaries, not just tail
- The actual error may be in a FAILED step's `.command.err` file, not the main log
- 30 lines may cut off the stack trace

**Improvements**:

`nextflow-workflow-viewer.tsx` — send more:
```typescript
body: JSON.stringify({
  workflow_name: workflowDefinition?.name,
  error_log: logs.slice(-50).join('\n'),          // 50 lines (was 30)
  error_message: errorMessage,
  failed_steps: updatedPhases                      // NEW: which steps failed
    .filter((p: any) => p.status === 'failed')
    .map((p: any) => ({ name: p.processName || p.name, work_dir: p.workDir })),
  run_id: activeRunId,
})
```

Backend — when `run_id` provided and steps have `work_dir`, optionally read `.command.err`:
```python
# In explain_error endpoint, before LLM call:
for step in request.failed_steps or []:
    err_file = os.path.join(step.get('work_dir', ''), '.command.err')
    if os.path.exists(err_file):
        with open(err_file) as f:
            step_err = f.read(2000)
        log_context += f"\n\n[Step {step['name']} stderr]:\n{step_err}"
```

This means the LLM sees the actual tool stderr, not just the Nextflow orchestration log — dramatically improves diagnosis for tool failures vs infrastructure failures.

---

## Implementation Priority

| Step | Change | Effort | Impact |
|---|---|---|---|
| **1** | Move error analysis LLM call to routes.ts (Solution 1) | 2h | Enables LLM for all users immediately |
| **2** | Extend regex to 8 types (Solution 3) | 1h | Better fallback when LLM unavailable |
| **3** | Pass `failed_steps` with `work_dir` from frontend | 1h | Read `.command.err` for real tool errors |
| **4** | Read `.command.err` in backend/routes.ts | 1h | LLM sees actual tool failure, not Nextflow wrapper |

Total: ~5 hours. Steps 1+2 are independent of Steps 3+4.

---

## What Doesn't Need Changing

- The frontend UI is complete: auto-triggers on failure, shows "What went wrong" + "Fix & Retry via Chat", distinguishes AI-analyzed vs pattern-matched
- The response schema `{error_type, human_summary, suggested_fix, chat_prompt, llm_used}` is correct
- The `onAdjustViaChat` callback is wired (verified in `chat-message.tsx`)
- The 20-second timeout is appropriate for Haiku

---

## LLM System Prompt (finalized)

```
You are a bioinformatics workflow debugging assistant.
A Nextflow workflow has failed. Analyze the error log and respond ONLY with valid JSON:
{
  "error_type": "<one of: missing_parameter, missing_file, docker_pull, resource_limit, data_format, permission_denied, nextflow_syntax, tool_not_found, unknown>",
  "human_summary": "<1-2 sentences: what went wrong in plain language a scientist can understand>",
  "suggested_fix": "<1-2 sentences: the specific action to fix this>",
  "chat_prompt": "<the exact message a user should paste in the chat to get help fixing this>"
}
Rules:
- human_summary must avoid technical jargon. Write for a biologist, not a developer.
- suggested_fix must be concrete and actionable (not "review the logs").
- chat_prompt must be a complete, paste-ready sentence starting with context.
- If the error is in a specific step, name the step in human_summary.
- Respond with ONLY the JSON object, no markdown, no explanation.
```
