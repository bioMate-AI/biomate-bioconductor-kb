# Auto-Loop — Current Status
*Date: 2026-04-15 | Branch: integration/next-phase*

---

## Overview

"Auto-loop" in BioMate refers to two related but distinct concepts:

1. **CLAUDE.md Dev Loop** — the mandatory iterative process every development task must follow (implement → test → record → audit → fix → repeat)
2. **Agentic Workflow Loop** — an internal AI pipeline feature: a self-correcting LLM loop that retries failed workflow generation steps instead of returning errors to the user

---

## 1. CLAUDE.md Dev Loop

### Definition

The `CLAUDE.md` enforces this 6-step iterative cycle for every task:

```
1. Implement  — write the code change
2. Test       — run E2E or unit test suite
3. Record     — capture screenshots / logs / audit JSON
4. Audit      — review screenshots; read logs for regressions
5. Fix        — patch failures or UI issues
6. Repeat     — loop until all assertions pass + screenshots clean
```

A task is **not done** until the full loop completes with a green test run and a clean screenshot audit.

### Current Status

**Enforced: Yes (manually).** The rule is in `CLAUDE.md` and is followed in development sessions. There is no automated hook that blocks work if the loop is skipped.

**Automation gap:** `docs/20260412_NEXT_VERSION_ARCHITECTURE.md` proposes Claude Code hooks to enforce the loop automatically. These are **BioMate-internal dev tooling** — they fire during Claude Code sessions on this codebase and are invisible to end users.

Hooks live in `biomate/.claude/settings.local.json` (repo-level, already exists with ~500 permission entries). Added as of this session:

```json
"hooks": {
  "Stop": [{
    "hooks": [{
      "type": "prompt",
      "prompt": "Before stopping: confirm the CLAUDE.md iterative loop is complete — green test run + screenshot audit reviewed. If not done, continue."
    }]
  }],
  "PostToolUse": [{
    "matcher": "Write|Edit",
    "hooks": [{
      "type": "command",
      "command": "bash -c 'f=\"$(echo $CLAUDE_TOOL_INPUT_FILE_PATH 2>/dev/null)\"; [[ \"$f\" == *e2e/*.e2e.ts ]] && echo \"[hook] e2e file modified — run: cd frontend && npx playwright test $(basename $f)\" || true'"
    }]
  }]
}
```

**Status: Implemented** — hooks added to `biomate/.claude/settings.local.json`.

### Screenshot Audit Infrastructure

- All E2E suites capture Playwright screenshots into `e2e/screenshots/<suite>/`
- `workflow-controls-comprehensive` writes `audit_<ISO>.json` with per-assertion pass/fail
- Screenshots are captured at: card visible, running state, completion banner, output files
- Manual visual review is required — no automated pixel-diff or layout regression tooling

---

## 2. Agentic Workflow Loop (Self-Correcting AI Pipeline)

### Current Architecture

BioMate's AI pipeline is a **directed acyclic pipeline** (not a loop). It makes 4–7 sequential LLM calls per user message:

```
User message
→ [LLM 1] Intent analysis + decomposition
→ [LLM 2] Clarification question (if ambiguous)  → early return
→ [Search] Tool + dataset retrieval
→ [LLM 3] Domain routing
→ [LLM 4] Domain specialist consultation(s)
→ [LLM 5] Workflow structure generation (JSON)
→ [Validation] Tool ID validation
→ [LLM 6] Workflow assembler refinement
→ [LLM 7] Final natural language response
→ Response to user
```

**Key design constraint:** Tool IDs like `toolshed.g2.bx.psu.edu/repos/devteam/fastqc/...` carry no semantic meaning to the LLM. The pipeline pre-fetches 30 valid tools via `_retrieve_tools_from_index()` and constrains the LLM to that set — preventing hallucination of invalid IDs.

### Status: No Retry Loop Implemented

If `_validate_tool_ids()` in `galaxy_workflow_generator.py` finds invalid tool IDs, it attaches `validation_errors` to the result and returns — **no retry**. The user sees an error instead of a corrected workflow.

### Proposed: One-Retry Loop

`docs/20260401_WORKFLOW_GENERATION_AGENTIC_LOOP.md` proposes a bounded retry:

```python
# In galaxy_workflow_generator.py → _generate_workflow_structure()
for attempt in range(2):  # max 2 LLM calls total
    response = self.llm_client.generate(system_prompt, user_prompt)
    result = json.loads(...)
    valid = self._validate_tool_ids(result, available_tools)
    if valid['success']:
        return result
    if attempt == 0:
        correction_prompt = f"""
Your previous workflow used invalid tool IDs: {valid['invalid_ids']}
Valid IDs from the catalog: {[t['tool_id'] for t in available_tools]}
Return corrected workflow JSON using only valid IDs.
"""
        user_prompt = user_prompt + "\n\n" + correction_prompt
```

**Status: IMPLEMENTED.** Code verified at `backend/lib/galaxy/ai/galaxy_workflow_generator.py` lines 642–680. The `for attempt in range(2)` loop exists, catches invalid tool IDs on attempt 0, builds a `correction_prompt` with the invalid IDs listed, and retries with the corrected prompt on attempt 1.

### Reinforcement Learning / Long-Term Loop

`docs/nextPhase/20260409_RL_WORKFLOW_GENERATION_SURVEY.md` surveys RL-based approaches:
- **Molecule-level RL**: policy-gradient for de novo drug design (ReLeaSE, GCPN, REINFORCE) — active literature, not implemented in BioMate
- **Pipeline-level RL**: automated workflow assembly (AFlow, BIA) — tracked as future research direction
- **Agent-level RL**: tool selection via policy gradient — Claude 4.6 + RLHF already covers this

**Status: Research / future roadmap. Not implemented in BioMate.**

---

## 3. Biomni DeepAgents / AgentHarness

`docs/nextPhase/20260321_DEEPAGENTS_AGENTHARNESS_ANALYSIS.md` analyzed the LangChain DeepAgents framework (LangGraph-based):

| Feature | DeepAgents | BioMate current |
|---------|------------|-----------------|
| Planning loop | `PlanningMiddleware` with `write_todos` | Manual CLAUDE.md loop |
| Subagent delegation | `SubAgentMiddleware` | Specialist LLM calls (non-agentic) |
| Context summarization | `SummarizationMiddleware` | Manual context management |
| Human-in-the-loop | Built-in interrupt | Clarification turns |
| Persistent memory | `MemoryMiddleware` | Session + DB memory P1 done |

**Status: Analysis complete. No DeepAgents integration in BioMate. BioMate's pipeline is custom Python/TypeScript, not LangGraph.**

---

## Summary

| Component | Implemented | Automated | Verified |
|-----------|-------------|-----------|---------|
| CLAUDE.md dev loop (6-step) | ✅ Yes | ❌ Manual only | ✅ In CLAUDE.md |
| Hook enforcement (`Stop` + `PostToolUse`) | ✅ **DONE** | ✅ Fires in Claude Code sessions | Added to `biomate/.claude/settings.local.json` |
| Screenshot audit capture | ✅ Yes | ✅ By Playwright | ✅ e2e/ files confirmed |
| Per-suite audit JSON | ✅ Yes | ✅ By test runner | ✅ WC audit JSON in code |
| Tool validation retry loop | ✅ **DONE** | ✅ In pipeline | ✅ `galaxy_workflow_generator.py` lines 642–680 |
| `timing.json` persistence | ✅ **DONE** | ✅ In executor | ✅ `nextflow_executor.py` lines 2316–2355 |
| RL-based workflow generation | ❌ Future roadmap | — | — |

---

## Priority Actions

1. Confirm WC-10 passes (added to code after last 9/9 doc — schema + live run test)
2. GC-8 (step-level rerun) was removed from `germline-complete-e2e.e2e.ts` — decide whether to restore it to WC-4 coverage or add back as GC-8
3. RL-based workflow generation remains future roadmap
