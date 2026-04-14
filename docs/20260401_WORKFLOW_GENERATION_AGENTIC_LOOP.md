# Workflow Generation: Agentic Loop Analysis

**Date:** 2026-04-01  
**Context:** Deep audit of BioMate's workflow generation path vs Claude Code's while-toolCalls loop  
**Status:** Open for discussion — proposals are starting points, not settled decisions

---

## 1. What BioMate Actually Does (Correcting Earlier Claim)

The earlier document said `processMessage()` is "a single-shot call." That was imprecise. The full generation path makes **4–7 LLM calls** in a structured linear pipeline — it is not a single call, but it is also not a loop.

### The actual pipeline

```
User message
  │
  ▼
[LLM call 1] Intent analysis + decomposition          galaxy-assistant.ts
  │
  ▼  (conditional: if ambiguous)
[LLM call 2] Clarification question generation        galaxy-assistant.ts
  │                                                    → early return to user
  ▼  (if workflow generation needed)
[Search]     Parallel tool + dataset search            galaxy-assistant.ts:1046
  │
  ▼
[LLM call 3] Domain routing (enhanced mode)           enhanced_domain_router.py
  │
  ▼
[LLM call 4] Domain specialist consultation(s)        domain_specialist.py
             (primary + up to 2 secondary, parallel)
  │
  ▼
[LLM call 5] Workflow structure generation            galaxy_workflow_generator.py
             (tool-constrained: tool list pre-fetched,
              LLM output is JSON only)
  │
  ▼
[Validation] tool_id validation, compatibility check  galaxy_workflow_generator.py
  │
  ▼
[LLM call 6] Workflow assembler refinement            workflow_assembler.py
             (conflict removal, step ordering, QC)
  │
  ▼
[LLM call 7] Final natural language response          galaxy-assistant.ts
  │
  ▼
Response to user
```

This is a **directed acyclic pipeline**, not a loop. Each stage passes its output to the next. No stage feeds its output back to an earlier stage.

### Where tool-use infrastructure exists but is unused

`llm_client.py:122–152` parses `tool_use` blocks from the Anthropic response and returns them in the content array. But `stop_reason == 'tool_use'` is never checked anywhere in the pipeline. The LLM is always called with a system prompt containing the full tool catalog and expected to return plain JSON — it never uses native Anthropic tool-call syntax.

---

## 2. What a "True Agentic Loop" Means (Claude Code Pattern)

Claude Code's `query.ts` does this:

```typescript
while (true) {
  const response = await claude.messages.create({ messages, tools, system })
  
  if (response.stop_reason === 'end_turn') break
  
  if (response.stop_reason === 'tool_use') {
    const toolResults = await Promise.all(
      response.content
        .filter(b => b.type === 'tool_use')
        .map(b => executeTool(b.name, b.input)
          .then(result => ({ type: 'tool_result', tool_use_id: b.id, content: result }))
          .catch(err  => ({ type: 'tool_result', tool_use_id: b.id, content: err.message, is_error: true }))
        )
    )
    messages.push({ role: 'assistant', content: response.content })
    messages.push({ role: 'user',      content: toolResults })
    // loop continues
  }
}
```

Key properties:
- The LLM **decides** which tools to call and in what order
- Tool errors are fed back to the LLM; it can recover, retry, or pivot
- The loop terminates when the LLM is satisfied — variable number of iterations
- The LLM sees all prior tool results before deciding next action

---

## 3. Why BioMate's Pipeline Design Is Correct for Bioinformatics

Before proposing changes, it's worth being explicit about why the current design makes sense.

### 3.1 Tool discovery is a domain-knowledge problem, not a reasoning problem

In Claude Code, the LLM can call `search_files("*.ts")` because file paths are self-describing. In BioMate, Galaxy tool IDs like `toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0` carry no semantic meaning to the LLM. A loop that lets the LLM freely request tools would hallucinate tool IDs.

Pre-fetching tools via `_retrieve_tools_from_index()` (30 tools, curated by semantic search) is the right design: the LLM only sees valid, real tool IDs.

### 3.2 Human oversight matters for scientific workflows

Claude Code runs code autonomously and loops until done. In bioinformatics:
- Wrong parameters on a 3-hour GATK run = wasted compute + invalid results
- The current clarification-first, show-workflow-for-review pattern has higher scientific value than silent self-correction

Multi-turn conversation state (turn 1: gather intent, turn 2: show workflow, turn 3: user refines) is the right interaction model.

### 3.3 The pipeline already achieves multi-step reasoning

The concern behind "no agentic loop" was that "the LLM can't see tool results and adapt." In practice:
- Domain specialists see retrieved tools and produce recommendations
- The assembler sees all specialist outputs and resolves conflicts
- The final response generator sees the validated workflow and produces the explanation

This is multi-step reasoning — just orchestrated by code rather than by the LLM itself.

---

## 4. Where Targeted Loops WOULD Help

That said, there are two specific failure modes in the current pipeline where a narrow loop would give a concrete improvement.

### 4.1 Tool validation failure — currently dead-end, no recovery

**Current behavior** (`galaxy_workflow_generator.py`):
```python
valid = self._validate_tool_ids(result, available_tools)
if not valid['success']:
    result['validation_errors'] = valid['errors']
    # Returns workflow with errors attached — no retry
```

If the LLM hallucinates a tool ID or picks a tool outside the pre-fetched list, the workflow is returned with `validation_errors` and the user sees an error. The LLM never gets a chance to fix it.

**Proposed: one retry loop (max 1 iteration)**

```python
def _generate_workflow_structure(self, user_intent, available_tools, detected_domain):
    for attempt in range(2):  # at most 2 LLM calls total
        response = self.llm_client.generate(system_prompt, user_prompt)
        result = json.loads(...)

        valid = self._validate_tool_ids(result, available_tools)
        if valid['success']:
            return result

        if attempt == 0:
            # Feed the error back for one correction attempt
            correction_prompt = f"""
Your previous workflow used these invalid tool IDs: {valid['invalid_ids']}
Valid tool IDs from the catalog are: {[t['tool_id'] for t in available_tools]}
Return a corrected workflow JSON using only valid tool IDs.
"""
            user_prompt = user_prompt + "\n\n" + correction_prompt
            # loop continues for attempt 1

    # After 2 attempts, return best effort with errors noted
    return result
```

This is not a full agentic loop — it's a bounded retry (max 2 LLM calls) triggered only on validation failure. In practice it fires rarely, but when it does it avoids surfacing a confusing error to the user.

**Cost:** +1 LLM call on validation failure only (not on every request).

### 4.2 Input data type context not reaching the generation LLM

There are two distinct dataset concerns in BioMate that are worth separating:

**Concern A — Specific file assignment (wiring Galaxy history files into input slots)**  
`WorkflowDatasetSelector` (`workflow_dataset_selector.py:20–40`) is currently a stub returning `{}`. When implemented, this will let users select specific files from their Galaxy history to wire into workflow input nodes. This requires **user confirmation** — the user should see "these files will be used as inputs" before running.

**Concern B — Input data *type* context shaping workflow structure** (this suggestion)  
This is different and requires no confirmation. The LLM currently generates workflow structure with no awareness of what input data the user has. If a user has paired-end FASTQ files, the LLM should not generate a step that produces FASTQ. If a user has a BAM file, the workflow should start from alignment, not raw sequencing.

**Current gap:** `uploaded_datasets` is passed from the frontend all the way to `generate_workflow_unified()` (`ai_assistant.py:2177`) but is never forwarded to the specialist prompt. The LLM generates blindly.

**Proposed: inject data type context into the specialist prompt (no confirmation needed)**

```python
# In domain_specialist.py, when building the specialist prompt:
if uploaded_datasets:
    # Only pass type/format metadata — not specific file IDs
    data_types = summarize_data_types(uploaded_datasets)
    # e.g. "paired-end FASTQ (Illumina), ~50M reads/sample, 3 samples"
    specialist_prompt += f"""
## AVAILABLE INPUT DATA
The user already has: {data_types}
Shape the workflow to START from this input type.
Do not include upstream steps that would produce data the user already has.
"""
```

This is purely generation context — the LLM uses it to pick the right workflow entry point. No specific file IDs are passed, so there is nothing for the user to confirm. The downstream `WorkflowDatasetSelector` (Concern A) remains the place for explicit file selection with user confirmation.

**Cost:** Zero additional LLM calls. One prompt string addition in `domain_specialist.py`.

---

## 5. What Should NOT Be Changed to an Agentic Loop

### 5.1 Tool discovery should stay pre-fetched

Letting the LLM call `search_tools(query)` in a loop introduces:
- Risk of hallucinated tool IDs in the search query
- Variable number of search calls (unpredictable latency)
- Weaker results than BioMate's current two-stage LLM reranking pipeline

The current approach (search → constrain → generate) is better.

### 5.2 Clarification should stay user-facing

Letting the LLM loop to self-resolve ambiguity (without asking the user) would produce silently wrong workflows. In bioinformatics, the right model is: ambiguity detected → ask the scientist.

### 5.3 Assembler conflict resolution should stay LLM-in-pipeline

The assembler already uses an LLM call with full context of all specialist recommendations. Moving this into a loop where each specialist independently iterates would multiply cost with no quality gain.

---

## 6. Summary of Proposed Changes

| Change | Type | Files | LLM calls added | Effort |
|---|---|---|---|---|
| Validation-failure retry loop (max 1 retry) | Bounded loop | `galaxy_workflow_generator.py` | 0–1 (only on failure) | 1 day |
| Data type context in specialist prompt (Concern B) | Prompt improvement | `domain_specialist.py` | 0 | 2 hours |
| Specific file assignment from Galaxy history (Concern A) | New feature — needs user confirmation UI | `workflow_dataset_selector.py` (stub) | 0 | Separate feature |

Neither change requires restructuring the pipeline. Both are contained to single files.

The broader "add a while-toolCalls loop" suggestion from the earlier document is **not recommended** for BioMate's workflow generation path. The existing pipeline achieves multi-step reasoning correctly for the domain. The two targeted improvements above address the only real failure modes without introducing the latency, cost, and determinism problems of open-ended agentic loops.

---

## 7. Open Questions for Discussion

1. **Validation failure frequency**: How often do tool_id validation errors actually occur in production? If it's rare (< 1%), the retry loop may not be worth the added complexity. Worth checking the error logs.

2. **Dataset-aware prompting**: Is the current prerequisite validator catching failures *before* the workflow reaches the user, or are users commonly seeing "missing data" errors after seeing a generated workflow? If the latter, the upstream prompt fix has higher value.

3. **Extended thinking and tool-use**: BioMate supports extended thinking (`BIOMATE_ENABLE_THINKING`). Extended thinking + agentic tool-use is a more natural fit for complex multi-domain queries. Is this worth exploring for a specific query type (e.g., novel cross-domain analyses where no template exists)?
