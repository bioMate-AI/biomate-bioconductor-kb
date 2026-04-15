# Knowledge Utilization Fixes — DB Knowledge Into LLM Context

**Date:** 2026-04-14

---

## Problem

BioMate had collected extensive knowledge in SQLite (`tool_knowledge`, `tools.scientific_context`, `cryo_em_protocols`, etc.) but most of it never reached the LLM or the user. The audit revealed:

- `_build_knowledge_highlights()` ran 3 DB queries on every workflow match and produced `best_practices`, `qc_thresholds`, `literature_guidance` — all silently dropped (no frontend component read the field)
- `scientific_rationale` (from `_build_scientific_rationale()`) reached the frontend UI for parameter hints but was **never injected into the LLM system prompt**
- `QC_RED_LINES.rationale` was present on each threshold item but only surfaced as a tooltip, invisible unless hovered
- The composed-workflow path had no `scientific_rationale` at all — the LLM wrote the response without any DB-verified tool context

---

## Fixes

### 1. Remove dead `_build_knowledge_highlights()` calls (P3)

**File:** `backend/lib/galaxy/ai/ai_assistant.py`

Three call sites removed:
- Template-match path (`_return_nextflow_match`)
- Chain-match path
- Composed-workflow path

The function body is retained (it correctly queries cryo_em_protocols, tool_knowledge, tools) but it is no longer called on every workflow request to produce data nobody reads. It can be repurposed later if a genuine consumer is wired up.

---

### 2. Inject matched-tool DB context into LLM system prompt

**File:** `frontend/server/galaxy-assistant.ts`

Added `_buildMatchedToolContextBlock(generatedWorkflow)` — a private helper that converts `scientific_rationale` into a compact `<matched_workflow_context>` block and injects it into the system prompt alongside `cryoEmContextBlock`.

**Trigger:** only when `runnableWorkflow = true` (a workflow was actually matched or composed). On clarification turns or failures, the block is empty — no tools are known, nothing useful to say.

**Content sourced from `scientific_rationale`:**

| Field | Source table | Injected as |
|---|---|---|
| `tools_used` | `tool_knowledge` | Tool list header |
| `when_to_use` | `tool_knowledge.use_cases` | When this workflow fits |
| `do_not_use_when` | `tool_knowledge.limitations` | When it does NOT fit |
| `common_pitfalls` | `tools.scientific_context.common_errors` | Specific error/cause/fix |
| `parameter_hints` | `tool_knowledge.recommended_parameters` | Key parameter recommendations |

**Example output injected into system prompt:**
```
<matched_workflow_context>
Matched workflow: rnaseq
Tools: STAR, DESeq2, featureCounts

When this workflow fits:
  - Differential expression analysis from RNA-seq count data
  - Multi-factor experimental designs with batch variables

When it does NOT fit:
  - Pre-normalised data (TPM, FPKM, RPKM) — use raw integer counts only
  - Single-cell RNA-seq without modifications

Common pitfalls:
  - Incorrect reference level causes wrong fold-change direction — cause: R alphabetical default — fix: use relevel()

Key parameter recommendations:
  - genome: GRCh38 (recommended reference for human samples)
</matched_workflow_context>
```

This is distinct from Claude's pretraining knowledge — it carries BioMate-specific verified configurations, container-version-matched parameter recommendations, and pitfalls observed from real runs.

---

### 3. Scientific rationale for composed workflows

**File:** `backend/lib/galaxy/ai/ai_assistant.py`

The `nextflow_composed` path previously returned no `scientific_rationale` — the LLM wrote a response about a freshly generated workflow without any DB context about its tools.

Added `_build_scientific_rationale(composed['nextflow_path'], composed['workflow_name'], composed.get('tools_used', []))` call in the composed return path. The result is added to both the top-level response dict and `workflow_ga` (for frontend parameter hints).

Effect: when no existing template matches and BioMate composes a novel workflow, the response LLM now receives the same DB-verified tool context as it does for template matches.

---

### 4. QC threshold rationale visible as text

**File:** `frontend/client/src/components/nextflow-workflow-viewer.tsx`

`QC_RED_LINES` already had a `rationale` field per threshold (e.g., `"> 50% loss = adapter-dominated library; downstream analysis is invalid"`). It was only surfaced as a tooltip (`title` attribute), invisible without hover.

Changed each threshold row from a flat `flex items-center` row to a `flex flex-col` container:
- Row 1: label + direction + number input + reset button (unchanged)
- Row 2: `{t.rationale && <p className="text-[10px] text-muted-foreground ...">}` — always visible in small muted text, right-aligned to the label column (`pr-20` keeps it from flowing under the input)

---

## Information Flow After Fixes

```
Workflow matched (template or composed)
    │
    ├─ backend: _build_scientific_rationale(tools)
    │       ├─ tool_knowledge.use_cases         → when_to_use
    │       ├─ tool_knowledge.limitations       → do_not_use_when
    │       ├─ tool_knowledge.recommended_parameters → parameter_hints
    │       └─ tools.scientific_context         → common_pitfalls, key_assumptions
    │
    ├─ frontend: scientific_rationale.parameter_hints
    │       └─ rendered as rationale text on each parameter input  [unchanged, was working]
    │
    └─ frontend: _buildMatchedToolContextBlock(generatedWorkflow)
            └─ <matched_workflow_context> block injected into LLM system prompt  [NEW]
                    → LLM now knows: which tools, when they fit, what they break on,
                      which parameters have verified recommendations
```

---

## What Is Still Not Wired

| Table | Rows | Gap |
|---|---|---|
| `cryo_em_tools.use_when` | 12 | Queried in removed `_build_knowledge_highlights` path; not yet in `_build_scientific_rationale` |
| `cryo_em_protocols.key_principles` | 6 rows × 6 principles | Reaches LLM via `/api/cryo_em/context` (cryo-EM domain); not available on general turns |
| `tool_knowledge.primary_citation` | 4,117 | Built in `_build_workflow_citations()`, returned in `citations` field — no frontend consumer pre-execution |
| `DOMAIN_CATALOGS` (hardcoded) | — | Lists available workflows per domain but is not sourced from `workflows` DB table; drifts when new workflows are added (P2) |
| `workflow_embeddings` | 0 rows | Schema exists, never populated |
| `learned_domain_keywords` | 0 rows | Schema exists, never written to at runtime |

---

## Files Modified

| File | Change |
|---|---|
| `backend/lib/galaxy/ai/ai_assistant.py` | Removed 3 dead `_build_knowledge_highlights()` calls; added `_build_scientific_rationale()` to composed-workflow path |
| `frontend/server/galaxy-assistant.ts` | Added `_buildMatchedToolContextBlock()`; injects `<matched_workflow_context>` into system prompt when workflow matched |
| `frontend/client/src/components/nextflow-workflow-viewer.tsx` | QC threshold rationale shown as visible small text, not tooltip-only |
