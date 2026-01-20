# Workflow Generation Performance Analysis

**Date:** 2026-01-19 16:30
**Status:** Analysis Complete - Issues Identified

---

## Current Flow Analysis

### Path 1: High Confidence (Template Reuse) - FAST ✅
```
Workflow Search (DB) → Template Reuse → Dataset Assignment → Output
```
**LLM Calls:** 0
**Estimated Time:** 1-2 seconds
**Status:** Optimal

### Path 2: Medium Confidence (Template Adaptation) - MODERATE ⚠️
```
Workflow Search (DB) → EnhancedWorkflowGenerator → Dataset Assignment → Output
```
**LLM Calls:** 1-2 (for adaptation)
**Estimated Time:** 5-10 seconds
**Status:** Acceptable

### Path 3: Low Confidence (From Scratch) - SLOW ❌
```
Workflow Search (DB)
    → Domain Detection (pattern)
    → Tool Search (5-stage)
        → LLM Query Analysis [LLM CALL #1]
        → Direct Entity Match (DB)
        → Vector Search (DB)
        → FTS5 Search (DB)
        → RRF Fusion
    → LLM Workflow Structure [LLM CALL #2]
    → Compatibility Validation (DB)
    → Dataset Assignment
    → Galaxy JSON Build
        → For EACH data source tool:
            → LLM Parameter Generation [LLM CALL #3, #4, #5...]
    → Citations (DB)
    → Output
```

**LLM Calls:** 2 + N (where N = number of data source tools)
**Estimated Time:** 15-60+ seconds depending on workflow size
**Status:** TOO SLOW

---

## LLM Call Inventory

| Component | File | LLM Calls | Max Tokens | Purpose |
|-----------|------|-----------|------------|---------|
| Query Analyzer | `query_analyzer.py:146` | 1 | 800 | Extract entities, expand terms |
| FTS5 Query Transform | `galaxy_workflow_generator.py:438` | 1 | 100 | Transform to FTS5 syntax |
| Workflow Structure | `galaxy_workflow_generator.py:611` | 1 | 4096 | Design workflow steps |
| Parameter Generator | `llm_parameter_generator.py:91` | 1 per tool | 1000 | Generate tool parameters |

### Worst Case Scenario

For a workflow with 5 data source tools:
```
LLM Calls = 1 (query) + 1 (FTS5) + 1 (structure) + 5 (params) = 8 calls
Time = 8 × 3-5 seconds = 24-40 seconds
```

---

## Issues Identified

### Issue 1: DUPLICATE LLM Query Analysis ❌

**Problem:** Two separate LLM calls for query processing:
1. `query_analyzer.py:146` - LLM extracts entities (800 tokens)
2. `galaxy_workflow_generator.py:438` - LLM transforms to FTS5 (100 tokens)

**These do similar work!**

**Location:**
- `unified_tool_search.py` calls `LLMQueryAnalyzer.analyze()`
- `galaxy_workflow_generator.py` calls `_transform_query_for_fts5()`

**Fix:** Merge into single LLM call or cache results.

### Issue 2: Sequential Parameter Generation ❌

**Problem:** Each data source tool triggers a separate LLM call:
```python
for step in workflow_structure.get('steps', []):
    if is_data_source:
        parameters = self.parameter_generator.generate_parameters(...)  # LLM CALL
```

**Location:** `galaxy_workflow_generator.py:762-776`

**Impact:** 5 data source tools = 5 sequential LLM calls = 15-25 seconds

**Fix Options:**
1. Batch all parameters in single LLM call
2. Parallelize LLM calls
3. Cache common parameter patterns

### Issue 3: No Caching of LLM Results ❌

**Problem:** Same queries generate same LLM calls repeatedly.

**Example:** "RNA-seq differential expression" always triggers same:
- Query analysis
- Workflow structure generation

**Fix:** Add LLM response caching with TTL.

### Issue 4: Workflow Search Before Tool Search ⚠️

**Problem:** The flow searches workflows THEN searches tools for low-confidence cases.

**Current Flow:**
```
1. Search 951 workflows (fast)
2. If score < 0.5:
   3. Search tools (5-stage, includes LLM)  ← SLOW
   4. Generate workflow (LLM)              ← SLOW
```

**Question:** Why search tools if we already have 951 workflows?

**Observation:** The tool search in low-confidence path might be redundant if we have good workflow templates.

---

## Performance Bottleneck Summary

| Bottleneck | Impact | Fix Difficulty |
|------------|--------|----------------|
| Duplicate query LLM calls | 3-5 sec wasted | Easy |
| Sequential param generation | 15-25 sec for 5 tools | Medium |
| No LLM caching | Repeated slow calls | Medium |
| Redundant tool search | 5-10 sec | Needs review |

---

## Recommended Optimizations

### Priority 1: Batch Parameter Generation (High Impact)

**Current:**
```python
for step in steps:
    if is_data_source:
        params = llm.generate(...)  # 1 call per tool
```

**Proposed:**
```python
data_source_tools = [s for s in steps if is_data_source(s)]
all_params = llm.generate_batch(data_source_tools)  # 1 call for all
```

**Savings:** 4+ LLM calls → 1 LLM call

### Priority 2: Merge Query Analysis LLM Calls

**Current:**
- `LLMQueryAnalyzer.analyze()` → entities, category
- `_transform_query_for_fts5()` → FTS5 query

**Proposed:**
```python
def analyze_and_transform(query):
    # Single LLM call returns both
    return {
        'entities': [...],
        'category': '...',
        'fts5_query': '...',
        'expanded_terms': [...]
    }
```

**Savings:** 2 LLM calls → 1 LLM call

### Priority 3: Add LLM Response Caching

```python
class CachedLLMClient:
    def __init__(self, llm_client, cache_ttl=3600):
        self.llm = llm_client
        self.cache = {}  # query_hash → response

    def generate(self, prompt, **kwargs):
        cache_key = hash(prompt)
        if cache_key in self.cache:
            return self.cache[cache_key]
        response = self.llm.generate(prompt, **kwargs)
        self.cache[cache_key] = response
        return response
```

### Priority 4: Parallel LLM Calls (If Not Batching)

```python
import asyncio

async def generate_params_parallel(tools):
    tasks = [
        asyncio.create_task(llm.generate_async(tool))
        for tool in tools
    ]
    return await asyncio.gather(*tasks)
```

---

## Flow Logic Review

### Does the Current Flow Make Sense?

**Yes and No:**

✅ **Good Design Decisions:**
1. Search-first approach (reuse before generate)
2. Confidence-based strategy selection
3. Tool constraint prevents hallucination
4. Domain-specific workflow phases

❌ **Questionable Design:**
1. **Why 3 generators?** (`GalaxyWorkflowGenerator`, `EnhancedWorkflowGenerator`, template reuse)
   - Could be unified into single generator with modes

2. **Why search tools if score < 0.5?**
   - If no template matches, maybe we should ask user for clarification
   - Or use a more general template and adapt

3. **LLM for FTS5 query transformation?**
   - Simple keyword extraction might be sufficient
   - FTS5 doesn't need sophisticated query transformation

---

## Recommended Architecture Changes

### Option A: Optimize Current Flow (Conservative)
- Batch parameter generation
- Cache LLM responses
- Merge duplicate LLM calls
- **Estimated improvement:** 50-70% faster

### Option B: Simplify Flow (Moderate)
- Remove `_transform_query_for_fts5()` LLM call (use simple extraction)
- Generate all parameters in workflow structure LLM call
- Add caching
- **Estimated improvement:** 60-80% faster

### Option C: Redesign Flow (Aggressive)
- Single unified generator
- One LLM call for entire workflow (structure + parameters)
- Streaming response for progress
- Template fallback only if LLM fails
- **Estimated improvement:** 80-90% faster

---

## Next Steps

1. [ ] Implement batched parameter generation
2. [ ] Add LLM response caching
3. [ ] Merge duplicate query analysis calls
4. [ ] Benchmark before/after improvements
5. [ ] Consider flow simplification
