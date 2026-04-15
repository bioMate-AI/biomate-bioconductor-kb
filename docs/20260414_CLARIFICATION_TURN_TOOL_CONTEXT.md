# Clarification-Turn Tool Context Injection

**Date:** 2026-04-14  
**Branch:** integration/next-phase

---

## Problem

`_buildMatchedToolContextBlock()` was gated on `runnableWorkflow`:

```typescript
const matchedToolContextBlock = runnableWorkflow
  ? this._buildMatchedToolContextBlock(generatedWorkflow)
  : '';
```

On clarification turns (`success: False`), `runnableWorkflow = false` → block was always `''` → LLM had no DB-verified tool knowledge when asking differentiating questions.

**User objection:** "knowledge information is very important for clarification, for context information collection to differentiate among workflows and tools."

This matters because the LLM should be able to ask targeted questions like:
- "Are you working with raw integer counts or pre-normalized TPM/FPKM values?" (DESeq2 limitation)  
- "Is your specimen helical or globular?" (CryoSPARC vs Helical SPA differentiation)

…rather than generic "What kind of data do you have?"

---

## Fixes

### 1. Remove `runnableWorkflow` gate (frontend)

**File:** `frontend/server/galaxy-assistant.ts`

```typescript
// Before:
const matchedToolContextBlock = runnableWorkflow
  ? this._buildMatchedToolContextBlock(generatedWorkflow)
  : '';

// After:
const matchedToolContextBlock = this._buildMatchedToolContextBlock(generatedWorkflow);
```

The function already self-guards: `if (!sr || !sr.tools_used?.length) return ''`. Removing the gate costs nothing when `scientific_rationale` is absent, and correctly injects when it is present.

---

### 2. Add `scientific_rationale` to chain clarification responses (backend)

**File:** `backend/lib/galaxy/ai/ai_assistant.py` — chain clarification return path

When the chain LLM is uncertain (`clarification_needed = True`), the code now:

1. Iterates over `top_chain.steps` to collect step `workflow_name` values
2. Looks up each step workflow with `self.workflow_search.search()` to get its `tools` list
3. Aggregates tools across all steps (deduped)
4. Calls `_build_scientific_rationale(tools)` to build DB-verified context
5. Includes result as `scientific_rationale` + `workflow_name` in the return dict

```python
_chain_clarif_tools: List[str] = []
for _step in (top_chain.steps or []):
    _wf_name = _step.get('workflow_name', '') if isinstance(_step, dict) else ''
    if _wf_name:
        _wf_hits = self.workflow_search.search(_wf_name, limit=1)
        if _wf_hits and _wf_hits[0].tools:
            _chain_clarif_tools.extend(
                t for t in _wf_hits[0].tools
                if t not in _chain_clarif_tools
            )
_chain_clarif_rationale = (
    self._build_scientific_rationale(
        '', top_chain.display_name, _chain_clarif_tools
    ) if _chain_clarif_tools else {}
)
return {
    'success': False,
    'workflow_type': 'clarification',
    ...
    **({'scientific_rationale': _chain_clarif_rationale,
        'workflow_name': top_chain.display_name}
       if _chain_clarif_rationale else {}),
}
```

---

### 3. Add `scientific_rationale` to pipeline clarification responses (backend)

**File:** `backend/lib/galaxy/ai/ai_assistant.py` — `run_via_pipeline()` clarification path

When the LangGraph pipeline sets `clarification_needed = True`, the code now extracts tools from `workflow_candidates` in the terminal state:

```python
_candidates = terminal_state.get("workflow_candidates") or []
_cand_tools: List[str] = []
for _cand in _candidates[:3]:
    _t = getattr(_cand, 'tools', None) or (
        _cand.get('tools_used', []) if isinstance(_cand, dict) else []
    )
    for _tool in (_t or []):
        if _tool not in _cand_tools:
            _cand_tools.append(_tool)
if _cand_tools:
    _pipeline_clarif_rationale = self._build_scientific_rationale(
        '', 'candidate workflows', _cand_tools
    ) or {}
return {
    "success": False,
    "message": ...,
    "source": "clarification",
    **({'scientific_rationale': _pipeline_clarif_rationale}
       if _pipeline_clarif_rationale else {}),
}
```

---

## Information Flow After Fixes

```
Clarification turn (chain or pipeline)
    │
    ├─ backend: extract tools from candidate workflows / chain steps
    │       └─ _build_scientific_rationale(tools)
    │               ├─ tool_knowledge.use_cases      → when_to_use
    │               ├─ tool_knowledge.limitations    → do_not_use_when
    │               └─ tools.scientific_context      → common_pitfalls
    │
    └─ frontend: _buildMatchedToolContextBlock(generatedWorkflow)
            └─ <matched_workflow_context> injected into LLM system prompt  [NEW]
                    → LLM knows: which tools are candidates, what they break on,
                      when they fit — can ask targeted differentiating questions
```

---

## When Each Turn Has Context

| Turn type | `scientific_rationale` present? | LLM gets `<matched_workflow_context>`? |
|---|---|---|
| Template match (high confidence) | Yes — from `_return_nextflow_match` | Yes |
| Template match (needs user feedback) | Yes — from `_return_nextflow_match` | Yes |
| Composed (no existing template) | Yes — added 2026-04-14 | Yes |
| Chain clarification | Yes — added now | Yes (if chain tools found in DB) |
| Pipeline clarification | Yes — added now | Yes (if candidates have tools) |
| Generic clarification (no candidates) | No | No (block returns `''`) |
| Chain match (confirmed) | N/A (no scientific_rationale field) | No (chain result has no sr) |

---

## Files Modified

| File | Change |
|---|---|
| `frontend/server/galaxy-assistant.ts` | Removed `runnableWorkflow` gate from `matchedToolContextBlock`; updated comment |
| `backend/lib/galaxy/ai/ai_assistant.py` | Chain clarification: build `scientific_rationale` from step workflow tools; pipeline clarification: build `scientific_rationale` from `workflow_candidates` |
