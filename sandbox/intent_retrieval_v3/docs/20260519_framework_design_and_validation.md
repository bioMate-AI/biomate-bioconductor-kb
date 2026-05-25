# Intent-Retrieval Framework — Design + Validation

**Date:** 2026-05-19
**Status:** Sandbox framework complete, regression-validated, memory adapter
prototyped. **No production wiring.**
**Implements:** Recommended path A from `docs/20260519_SESSION_REVIEW_AND_DB_RETRIEVAL_GENERALIZATION.md`.

## What's in this sandbox

```
sandbox/intent_retrieval_v3/
├── README.md
├── core/
│   ├── yaml_loader.py        cached YAML loader + chain/cycle resolution
│   ├── intent_matcher.py     trigger/disqualifier matching + confidence
│   └── candidate_ops.py      generic prioritize / inject / dedup primitives
├── adapters/
│   ├── workflow.py           wraps core to reproduce workflow_intent.py
│   └── memory.py             NEW — memory-recall ranking (Opportunity 1)
├── data/
│   └── memory_intents.yaml   prototype intent map for memory recall (8 entries)
└── tests/
    ├── test_adapter_workflow.py   22 tests, including v2-vs-v3 parity
    └── test_adapter_memory.py     8 tests
```

## Validation evidence

### 1. v3 workflow adapter is bit-identical to v2 library

```
22 passed in 0.08s
```

The test file `test_adapter_workflow.py` runs every case through BOTH the v2 library (`sandbox/workflow_search_v2/library/workflow_intent.py`) and the v3 adapter (`sandbox/intent_retrieval_v3/adapters/workflow.py`), and asserts identical output. **All cases match.**

### 2. Full 155-case benchmark parity

Direct A/B on the cross_domain_routing benchmark:

| Method | Top-1 HIT |
|---|---|
| Baseline (`UnifiedWorkflowSearch.search`) | 108/155  (69.7%) |
| v2 library + inject mode | **122/155  (78.7%)** |
| **v3 adapter + inject mode** | **122/155  (78.7%)** |
| v2 == v3 output | **True** |

The framework hosts all the workflow logic without behavior drift.

### 3. Memory adapter generalizes the pattern

8 tests in `test_adapter_memory.py` cover:
- Confident intent promotes/injects canonical memory file
- Injection works on empty candidate lists
- Disambiguation between workflow-vs-family results queries
- Single weak trigger doesn't inject (confidence gate)
- Dict-style candidates supported
- Ambiguous queries pass through

All passing. **Same code path as workflow adapter — the framework is domain-agnostic.**

### 4. No regression in existing tests

```
87 passed (backend/tests/test_family_dedup.py + sandbox/retrieval_v2/ + sandbox/workflow_search_v2/)
```

The framework lift didn't touch any existing library. Both shipped libraries continue to work as before.

## API contract that emerges from the framework

Every adapter follows the same shape:

```python
def prioritize_X_by_intent(query, candidates, *, inject_canonical=False,
                            yaml_path=None) -> list:
    intents = load_intent_map(yaml_path or _DEFAULT_YAML)
    matches = match_intents(query, intents)
    chosen = resolve_single_intent(matches)
    if chosen is None: return list(candidates)
    return prioritize_candidates(candidates, chosen["canonical"],
                                  key_fn=domain_key_fn,
                                  inject_if_missing=inject_canonical,
                                  inject_synthesizer=domain_synth)
```

Each adapter contributes:
1. A YAML path for its intent map.
2. A `key_fn` that extracts the candidate's canonical identifier (workflow name, file basename, gene symbol, etc.).
3. An optional `inject_synthesizer` that knows how to build a synthetic candidate of the right type.

That's ~30 lines per new adapter — confirmed by `adapters/workflow.py` (32 LOC) and `adapters/memory.py` (50 LOC including the dict-style support).

## What the core enables next (Opportunities 2-5)

For each remaining session-review opportunity, a new adapter is now ~30-50 lines plus a YAML:

| Opportunity | Adapter | YAML | Estimated effort |
|---|---|---|---|
| 1. Memory recall | ✓ prototyped | `memory_intents.yaml` | done (this sandbox) |
| 2. Chat session resume | `adapters/chat_session.py` | `chat_intents.yaml` | ~half day |
| 3. Param recommendation | `adapters/parameters.py` | `param_presets.yaml` | ~1 day (preset curation) |
| 4. Entity canonical resolution | `adapters/entity.py` | `entity_canonicals.yaml` | ~1 day if HGNC crosswalk used |
| 5. Regulatory question router | `adapters/regulatory.py` | `regulatory_intents.yaml` | ~2 days (template curation) |

The 2-day framework lift pays for itself by the **third** opportunity. Estimated total cost to ship 1–5 individually was ~5.5 days; with the shared framework it's ~4 days (1.5 days saved + uniform contract).

## Hard constraints the framework preserves (all 6 from session-review)

1. ✅ **Data beats schema** — adapters consume YAML, no schema changes anywhere.
2. ✅ **Investigation gates building** — each adapter should ship with its own A/B (memory adapter still needs one; see "Open" below).
3. ✅ **Estimate-vs-actual calibration** — A/B harness pattern from `sandbox/workflow_search_v2/scripts/measure_intent_lift.py` is reusable per adapter.
4. ✅ **Reorder vs inject distinction** — preserved at `inject_canonical=True` parameter on every adapter.
5. ✅ **Confidence gates** — `intent_matcher.resolve_single_intent` enforces ambiguity_factor + minimum trigger count.
6. ✅ **Sandbox-first** — framework sits alongside existing sandboxes; production paths untouched.

## Open: memory-recall adapter A/B

The framework is validated; the **memory adapter's lift hasn't been measured** yet. To do this properly:

1. Build a memory-recall eval set (~20 queries with expected canonical files).
2. Adapt the `measure_intent_lift.py` pattern to the memory adapter.
3. Report top-1 lift vs current fuzzy-match baseline.

Without that A/B, the memory adapter is structurally proven (framework hosts it, tests pass) but its actual lift on real memory queries is unknown. **Investigation step still owed.**

## Production wiring (only if/when promoted)

```
backend/lib/galaxy/ai/intent_retrieval/
├── core/        (moved from sandbox/intent_retrieval_v3/core/)
├── adapters/    (one Python file per shipping adapter)
└── data/        (YAMLs at backend/config/intent_retrieval/ instead)
```

Each adapter ships behind its own env flag:
- `BIOMATE_WORKFLOW_INTENT_PRIORITIZE=1` (already documented)
- `BIOMATE_MEMORY_INTENT_PRIORITIZE=1`
- etc.

Effort to promote framework + workflow adapter: ~half day (file moves + path updates + ai_assistant.py wiring).

## Cumulative session accounting

| Layer | Status | Tests |
|---|---|---|
| Wrapper-level (`family_dedup`) | sandbox + library shipped | 29 |
| Workflow-level (`workflow_intent`) v2 | sandbox shipped | 18 |
| **Intent-retrieval framework** v3 | sandbox shipped, regression-validated | 30 |
| **Memory adapter** (new — Opportunity 1) | sandbox prototype | 8 |

**117 tests passing across the full session.** Production code: zero modifications since the session start. All progress lives on `origin/integration/next-phase`.
