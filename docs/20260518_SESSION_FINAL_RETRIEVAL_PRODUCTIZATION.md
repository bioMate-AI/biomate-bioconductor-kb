# Session Final — Retrieval Productization & Tool Catalog Architecture

**Date:** 2026-05-18
**Branch:** `integration/next-phase`
**Status:** Library + data shipped; production consumers not yet wired (intentional — opt-in by design)

---

## Read-order for this session's documents

The session produced 10+ docs as the thinking evolved. Read in this order:

1. `20260518_RETRIEVAL_TOOLS_PRODUCTIZATION_AND_USE_CASES.md` — original 5-use-case framing for retrieval tools; sets validation criteria
2. `20260518_TOOL_CATALOG_RESTRUCTURE_AND_DEDUP_PLAN.md` — the architectural insight that the 12,274-row catalog is wrappers, not tools, and proposed 3-level hierarchy
3. `20260518_PHASE0_CLUSTERING_RESULTS.md` — Phase 0 measurement: only 1.43× compression possible by path-extraction alone; 5.1% of catalog is true duplicates; bigger story is function proliferation within toolkit suites
4. `20260518_PHASE1_AB_RESULTS_AND_DECISION.md` — Phase 1 A/B benchmark: canonical DB only +3.3pp at top-1 (below ship threshold); **Phase 1.5 update at bottom**: alias map alone gives +16.7pp — the real lever is data, not schema
5. `20260518_FAMILY_DEDUP_INTEGRATION_GUIDE.md` — how a downstream caller wires `dedup_results_by_family` (post-processor pattern, env-flag rollout)
6. `20260518_REMAINING_ISSUES_AND_PROPOSED_FIXES.md` — pre-existing FTS-quality bug and merge-conflict that surfaced during validation
7. **This document** — final synthesis + canonical-wrapper rerank results + production map

---

## TL;DR

**Architectural finding:** the 12,274-row `galaxy_ai_tools.db` is a flat catalog of Galaxy wrappers, not a hierarchy of tools and their functions. Searching for "samtools" today returns unrelated tools (CLC Mapper, etc.) whose long help_text descriptions mention samtools internally — because FTS5 BM25 has no signal for "this row IS samtools, that row only MENTIONS samtools."

**Solution shipped:** three composable retrieval primitives (library + curated data), all opt-in, no production consumers wired:

```
backend/config/tool_family_aliases.yaml      (155 rules)  — fragment → canonical family
backend/config/tool_family_canonical.yaml   (30 rules)   — family → canonical wrapper
backend/lib/galaxy/ai/retrievers/family_dedup.py — 4 pure functions
```

**Validated on real DB:** top-1 = canonical hit rate improved from **25% → 91.7% (+66.7pp)** when callers fetch L=100 from FTS and pass results through `prioritize_query_family(query, results)`.

---

## The three retrieval primitives

All in `backend/lib/galaxy/ai/retrievers/family_dedup.py`. All pure functions, all cache-loaded data, all opt-in. None wired to any consumer.

### `dedup_results_by_family(results)`
Collapses same-family duplicates while preserving rank order. Adds `canonical_family_id` + `family_member_count` to each surviving result. Use case: search returns 5 samtools_view variants from different authors → user sees 1.

### `rerank_to_canonical(results)`
Within each family present in results, moves the canonical wrapper to position 1 of that family's slice. Preserves inter-family order. Use case: "Picard RevertSam" outranks "Picard MarkDuplicates" → canonical (MarkDuplicates) wins within the picard slice but doesn't change the family's position in the overall list.

### `prioritize_query_family(query, results)`
The strongest reorderer. Identifies the target family from the query string (via alias map / canonical map keys), partitions results into [target_family, others], and promotes the canonical wrapper to position 1. Use case: user types "samtools" → wants samtools_sort at rank 1, not CLC Mapper.

### `canonical_family_key(tool_id, name)`
Underlying helper that computes a wrapper's canonical family from path extraction + alias YAML.

---

## Measured impact (12 canonical-query eval set)

| Method | Top-1 = canonical hit rate |
|---|---|
| Raw FTS, limit=10 (production today) | **25.0%** (3/12) |
| Raw FTS limit=10 + `rerank_to_canonical` | 33.3% (4/12) |
| Raw FTS **limit=100** + `prioritize_query_family` | **91.7%** (11/12) |

Only miss: `gatk4` — its canonical (`nfcore/gatk4/haplotypecaller`) isn't in FTS top-100, so a sibling gatk4 wrapper takes top-1 (right family, wrong function).

Measurement script: `sandbox/retrieval_v2/scripts/measure_canonical_lift.py` — reproducible.

---

## Why this approach beats a schema migration

Earlier in the session we built a full canonical-tools SQLite database (`sandbox/retrieval_v2/output/tool_canonical.db` — 8,572 suites / 11,648 functions / 12,274 wrapper mappings). It works correctly but A/B-tested at only **+3.3pp** top-1 over flat search.

Then we discovered that applying the alias map alone — as data, not schema — lifted **both** flat and canonical-DB paths by +16.7pp. The catalog isn't the bottleneck; the mapping is. So we kept the canonical DB as a sandbox artifact (useful for future agentic workflows where the LLM needs to pick a function within a suite) and shipped only the data files + library functions.

Schema migrations are expensive. Curated YAML data files are cheap. When the data does most of the work, ship the data.

---

## What's wired vs not wired

### Currently wired (production)
- **Nothing.** All library functions are exported but no caller imports them yet.

### Recommended next wiring (separate PR, ~half day)
`backend/lib/galaxy/ai/workflow_ops/autofix/tool_parameter_recommender.py:100` (the `search_tools` method) is the highest-impact integration point. Behind a feature flag:

```python
import os
from backend.lib.galaxy.ai.retrievers import prioritize_query_family

def search_tools(self, query, limit=10):
    # Fetch wider when reranker is enabled so canonical can be found
    fts_limit = limit * 10 if os.environ.get("BIOMATE_FAMILY_PRIORITIZE") == "1" else limit
    rows = self.conn.execute("""
        SELECT tool_id, name, category, description, rawText, version
        FROM tools t JOIN tools_fts fts ON t.tool_id = fts.tool_id
        WHERE tools_fts MATCH ? LIMIT ?
    """, (query, fts_limit)).fetchall()
    results = [_to_tool_info(r) for r in rows]
    if os.environ.get("BIOMATE_FAMILY_PRIORITIZE") == "1":
        results = prioritize_query_family(query, results,
                                           tool_id_key="tool_id", name_key="name")
    return results[:limit]
```

(Earlier in this session a version of this patch was applied and then reverted — intentional sandbox-only stance. The library is ready when production is.)

### Other callers documented in `20260518_FAMILY_DEDUP_INTEGRATION_GUIDE.md`
- `tool_discovery.py` — category-filtered iteration (medium impact)
- `tool_knowledge_collector.py` — batch knowledge collection (low impact)
- `search_ranked` endpoint — workflow level, NOT a fit (different layer)

---

## Tests (69/69 passing)

```
backend/tests/test_family_dedup.py                       29 tests
sandbox/retrieval_v2/tests/test_retrievers.py             17 tests   (live API)
sandbox/retrieval_v2/tests/test_tool_catalog.py           23 tests
```

Run:
```bash
PYTHONPATH=. python -m pytest backend/tests/test_family_dedup.py \
                              sandbox/retrieval_v2/tests/ -v
```

Coverage includes:
- YAML load + drift detection (sandbox copy must be symlink to production)
- Path extraction across all wrapper styles (toolshed/nfcore/biomate/bioconductor)
- Alias chain resolution (transitive) + cycle handling
- Dedup non-mutation + rank preservation
- Rerank-to-canonical: promotes when present, no-op when absent, preserves inter-family order
- Prioritize-by-query: moves target family above unrelated, handles unknown queries gracefully
- Module imports without pulling broken `llm_client.py` (defensive against the unresolved merge issue from another session)
- Live integration: 12-query top-1 canonical lift via `measure_canonical_lift.py`

---

## Maintenance

Adding a new tool family takes ~1 minute, no code change:

1. Add fragments to `backend/config/tool_family_aliases.yaml`:
   ```yaml
   varscan2:
     - varscan
     - varscan_mpileup2cns
   ```

2. Add canonical wrapper to `backend/config/tool_family_canonical.yaml`:
   ```yaml
   varscan2: toolshed.g2.bx.psu.edu/repos/iuc/varscan_mpileup2cns/...
   ```

3. (Optional) Add a test case in `backend/tests/test_family_dedup.py`.

Library reloads YAML automatically; `lru_cache` clears on process restart. To refresh in-process:
```python
from backend.lib.galaxy.ai.retrievers.family_dedup import load_alias_map, load_canonical_map
load_alias_map.cache_clear()
load_canonical_map.cache_clear()
```

---

## Sandbox artifacts (preserved, regenerable)

`sandbox/retrieval_v2/` — full development workspace. Mirrors `frontend/research_agent_v2/` pattern: nothing in here is imported by production. Contents:

- `retrievers/` — three additional retrievers built earlier (Europe PMC literature, OMIM gene→disease, tool_catalog) with 40 passing tests. **Not promoted** because Europe PMC + OMIM serve a different need than the autofix recommender does. May get promoted later if/when tool-use is wired to the production LLM.
- `scripts/` — `cluster_tools.py`, `function_dedup.py`, `build_canonical_db.py`, `run_suite_eval.py`, `measure_canonical_lift.py`. All read-only against production DB.
- `output/` — `tool_canonical.db` (the 3-level catalog SQLite), `tool_clusters.csv`, `function_duplicates.csv`. Regenerable from `build_canonical_db.py`.
- `data/family_aliases.yaml` — symlinked to `backend/config/tool_family_aliases.yaml` to prevent drift.
- `tests/` — 40 tests for sandbox retrievers.

Future agentic-workflow work (where the LLM picks function within a suite) would benefit from re-activating the canonical SQLite catalog. The build script is regenerable.

---

## Open items not addressed this session

- **FTS column-weight fix** for `tools_fts` (proposed in `20260518_REMAINING_ISSUES_AND_PROPOSED_FIXES.md`) was applied and reverted. The reverted state means FTS still returns unrelated tools in top-10 without the library's intervention. The new `prioritize_query_family` works around this by fetching L=100, but the underlying FTS quality issue persists. Re-apply the column weights as a separate decision.
- **`BIOMATE_DISABLE_LLM_FALLBACK` env flag** in `llm_client.py` was applied and reverted. Eval/benchmark reproducibility is currently dependent on the cascading fallback's default behavior. Re-apply as a separate decision.
- **gatk4 canonical** still misses top-1 (canonical wrapper not in FTS index). Either change the canonical to a toolshed-indexed wrapper, or add a DB-injection fallback to `prioritize_query_family`. Out of scope for this PR.
- **Expand canonical map** from 30 → ~80 families to cover the long tail (rseqc, frogs, vienna_rna, hicup, salmon_alevin, etc.). ~30 minutes of curation.
- **Production eval set is 12 queries.** Before flipping any feature flag default-on, expand to 50+ and gather real user-query telemetry.

---

## Files touched (production)

```
backend/config/tool_family_aliases.yaml             NEW   data
backend/config/tool_family_canonical.yaml           NEW   data
backend/lib/galaxy/ai/retrievers/__init__.py          NEW   library (5 exports)
backend/lib/galaxy/ai/retrievers/family_dedup.py      NEW   library
backend/tests/test_family_dedup.py                     NEW   29 tests
```

## Files touched (sandbox)

```
sandbox/retrieval_v2/README.md
sandbox/retrieval_v2/__init__.py
sandbox/retrieval_v2/data/family_aliases.yaml         symlink → backend/database/...
sandbox/retrieval_v2/retrievers/{__init__.py, europe_pmc.py, omim.py, tools.py, tool_catalog.py}
sandbox/retrieval_v2/scripts/__init__.py
sandbox/retrieval_v2/scripts/build_canonical_db.py
sandbox/retrieval_v2/scripts/cluster_tools.py
sandbox/retrieval_v2/scripts/function_dedup.py
sandbox/retrieval_v2/scripts/run_suite_eval.py
sandbox/retrieval_v2/scripts/measure_canonical_lift.py
sandbox/retrieval_v2/tests/__init__.py
sandbox/retrieval_v2/tests/test_retrievers.py
sandbox/retrieval_v2/tests/test_tool_catalog.py
sandbox/retrieval_v2/tests/suite_eval_set.yaml
sandbox/retrieval_v2/output/.gitkeep                  (DB + CSVs regenerable, .gitignored)
sandbox/__init__.py
```

## Docs

```
docs/20260518_RETRIEVAL_TOOLS_PRODUCTIZATION_AND_USE_CASES.md
docs/20260518_TOOL_CATALOG_RESTRUCTURE_AND_DEDUP_PLAN.md
docs/20260518_PHASE0_CLUSTERING_RESULTS.md
docs/20260518_PHASE1_AB_RESULTS_AND_DECISION.md
docs/20260518_FAMILY_DEDUP_INTEGRATION_GUIDE.md
docs/20260518_REMAINING_ISSUES_AND_PROPOSED_FIXES.md
docs/20260518_SESSION_FINAL_RETRIEVAL_PRODUCTIZATION.md   (this file)
```
