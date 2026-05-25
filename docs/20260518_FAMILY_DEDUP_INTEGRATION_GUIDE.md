# Family-Dedup Integration Guide

**Status:** Library shipped, **no callers wired yet.** Each integration is opt-in.
**Date:** 2026-05-18
**Library:** `backend/lib/galaxy/ai/retrievers/family_dedup.py`
**Data:** `backend/config/tool_family_aliases.yaml` (155 alias rules)
**Tests:** `backend/tests/test_family_dedup.py` (16 passing)
**Background:** `docs/20260518_PHASE1_AB_RESULTS_AND_DECISION.md` — Phase 1.5 A/B showed +16.7pp top-1 from this approach on the 30-query suite eval set.

## What the library does

```python
from backend.lib.galaxy.ai.retrievers import dedup_results_by_family

deduped = dedup_results_by_family(raw_results)
# raw_results: [{tool_id, name, score, ...}, ...] (rank-ordered)
# deduped:     same list, duplicates by canonical family collapsed,
#              each item now has canonical_family_id + family_member_count
```

Pure function. No DB connection. No side effects. Loads the YAML once on
first call (cached). Returns a new list; does not mutate the input.

## Where to wire it (ranked by impact)

### 1. `tool_parameter_recommender.py` (highest impact — used by autofix)

**File:** `backend/lib/galaxy/ai/workflow_ops/autofix/tool_parameter_recommender.py:118`

This is the only caller today that uses `tools_fts` for **ranked** wrapper search. Its results currently surface as raw wrapper hits — exactly the pattern the alias map was built to fix.

**Patch:**

```python
# At top of file
from backend.lib.galaxy.ai.retrievers import dedup_results_by_family

# Inside the method that runs the FTS query and returns results:
rows = cursor.execute("""
    SELECT t.tool_id, t.name, t.description, ...
    FROM tools t JOIN tools_fts fts ON t.tool_id = fts.tool_id
    WHERE tools_fts MATCH ?
    ORDER BY bm25(tools_fts)
    LIMIT ?
""", (query, limit * 3)).fetchall()    # fetch 3× to give dedup headroom

result_dicts = [dict(zip(cols, r)) for r in rows]
deduped = dedup_results_by_family(result_dicts)[:limit]
return deduped
```

Expected effect: when the auto-fix LLM asks "what tool replaces this missing step?", it gets one Picard, one Samtools, one BWA — instead of three Picard variants from different authors.

### 2. `comprehensive_tool_knowledge_agent.py:345` and `tool_knowledge_collector.py:444`

These iterate **all** wrapper rows for batch knowledge collection. Not ranked-search use cases, so dedup gives no UX win directly. Optional later use: group output by canonical family for cleaner knowledge cards.

### 3. `tool_discovery.py:395` (category-filtered wrapper search)

Returns wrappers in a single category (`SELECT * FROM tools WHERE category = ?`). The category is an over-broad bucket (e.g. "RNA" has 389 rows). Adding family dedup at this layer could turn "show me all RNA tools" into "show me 50 canonical RNA tool families, click any to see wrappers." Higher-effort UI change; defer.

### 4. `/api/ai_assistant/search_ranked` (NOT a direct fit)

This endpoint operates at the **workflow/pipeline level**, not the wrapper level. The alias map doesn't apply directly. A parallel pipeline-level alias map would need to be built (Phase 2 work). Out of scope for this PR.

## Safety properties

- **Cached alias-map load.** First call reads the YAML; subsequent calls hit `lru_cache`. No per-request file I/O.
- **Degraded mode is safe.** If `tool_family_aliases.yaml` is missing or `pyyaml` is unavailable, `load_alias_map()` returns `{}` and `dedup_results_by_family` becomes a pass-through that just adds `canonical_family_id` tags based on path extraction alone. No crash, no behavior change beyond the (small) added fields.
- **Non-destructive.** Input dicts are never mutated; output is fresh copies.
- **Stable rank order.** The first occurrence of each canonical family wins the slot; subsequent same-family hits increment `family_member_count` without changing position.
- **Feature flag pattern (recommended for production rollout):**

  ```python
  import os
  if os.environ.get("BIOMATE_FAMILY_DEDUP", "1") == "1":
      results = dedup_results_by_family(results)
  ```

  Set `BIOMATE_FAMILY_DEDUP=0` to disable instantly without redeploy.

## How to extend the alias map

`backend/config/tool_family_aliases.yaml` is data, not code. Add a new family or fragment by appending to the appropriate section:

```yaml
# Example: add VarScan2 as a family
varscan2:
  - varscan
  - varscan_mpileup2cns
  - varscan_somatic
```

YAML parses on next process start (or call `family_dedup.load_alias_map.cache_clear()` to refresh in-process). No code change required.

**Rules of thumb when adding:**

1. **Only merge same-tool variants.** STAR (RNA-seq aligner) and STAR-Fusion (fusion caller) are different tools — do NOT merge.
2. **Keep major versions separate** when they're materially different (MACS2 vs MACS3, MetaPhlAn2 vs MetaPhlAn4). Merge minor-version author-variants only.
3. **Quote any YAML value containing colons** (`"biomni: foo"`) or other reserved chars.
4. **Add a test case** in `backend/tests/test_family_dedup.py` for any new high-traffic family.

## What ships in this PR vs what's deferred

**Shipped (this PR):**
- `backend/config/tool_family_aliases.yaml` (155 rules)
- `backend/lib/galaxy/ai/retrievers/family_dedup.py` (library)
- `backend/tests/test_family_dedup.py` (16 tests, all passing)
- This integration guide

**Explicitly NOT in this PR:**
- Any wiring into `tool_parameter_recommender.py` or other consumers
- Pipeline-level alias map (`nf-core/rnaseq` etc.)
- The canonical-DB schema (`sandbox/retrieval_v2/output/tool_canonical.db`) — kept as sandbox artifact
- Any production feature flag

**Next PR (whoever picks this up):**
- Wire `dedup_results_by_family` into `tool_parameter_recommender` behind `BIOMATE_FAMILY_DEDUP=1`
- Add an A/B telemetry hook so we can measure top-1 lift in production
- After 1-2 weeks of clean data, flip the default to enabled

## Validation evidence

The Phase 1.5 A/B benchmark on a 30-query suite eval set showed:

| Path | top-1 | top-3 |
|---|---|---|
| Existing flat search (no aliases) | 56.7% | 90.0% |
| Same search + family dedup | **73.3%** | 96.7% |

Source: `sandbox/retrieval_v2/scripts/run_suite_eval.py` against the 12,274-row `galaxy_ai_tools.db`. The same alias map and the same path-extraction logic that produced those numbers are what this library uses verbatim.
