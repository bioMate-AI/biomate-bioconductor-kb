# sandbox/intent_retrieval_v3/

**Status:** sandbox — framework consolidation of `retrieval_v2` (wrapper-level)
and `workflow_search_v2` (workflow-level) patterns. Nothing here is imported
by BioMate production code.

## Why this exists

Two retrieval libraries shipped this session use the same pattern:

- `backend/lib/galaxy/ai/retrievers/family_dedup.py` (wrapper-level, +65pp on 40 queries)
- `sandbox/workflow_search_v2/library/workflow_intent.py` (workflow-level, +12.3pp on 155 queries)

Both:
1. Load a curated YAML mapping intent → canonical resource
2. Match a query against trigger terms / fragments
3. Honor disqualifier lists (`disqualified_if_present`)
4. Either reorder candidates (promote canonical to top) or inject when missing
5. Use `lru_cache` for YAML loading
6. Resolve transitive chains in YAML data
7. Are pure functions — no I/O during the operation, only at load time

This sandbox extracts the common abstractions into `core.py`, then ships
each library as a thin adapter. Plus a prototype `memory.py` adapter to
prove the framework generalizes to Opportunity 1 (memory recall ranking)
from the session review doc.

## Layout

```
core/
  yaml_loader.py        cached YAML loader, chain & cycle resolution
  intent_matcher.py     trigger/disqualifier matching with confidence
  candidate_ops.py      generic prioritize / inject / dedup
adapters/
  workflow.py           wraps core for workflow-level (replaces workflow_intent.py)
  family.py             wraps core for wrapper-level (replaces family_dedup.py)
  memory.py             new — memory recall ranking adapter (Opportunity 1)
tests/
  test_core.py          unit tests on core primitives
  test_adapter_workflow.py  regression: same outputs as workflow_intent.py
  test_adapter_family.py    regression: same outputs as family_dedup.py
  test_adapter_memory.py    new adapter behavior
docs/
  20260519_framework_design_and_validation.md
data/
  memory_intents.yaml   prototype intent map for memory recall
```

## Promotion criteria

Same as prior sandboxes — promote individual files to production paths only
after:
1. Regression tests prove no behavior change vs the existing libraries
2. A new adapter's lift is validated on a curated eval set
3. User reviews and approves

## Running

```bash
PYTHONPATH=. python -m pytest sandbox/intent_retrieval_v3/tests/ -v
```
