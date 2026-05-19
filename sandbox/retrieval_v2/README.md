# sandbox/retrieval_v2/

**Status:** sandbox — nothing here is imported by BioMate production code.

Mirrors the `frontend/research_agent_v2/` pattern: a deliberately-isolated
workspace for the retrieval-tools productization work documented in:

- `docs/20260518_RETRIEVAL_TOOLS_PRODUCTIZATION_AND_USE_CASES.md`
- `docs/20260518_TOOL_CATALOG_RESTRUCTURE_AND_DEDUP_PLAN.md`

## Layout

```
retrievers/   # Lifted retriever modules (Europe PMC, OMIM, tool schemas)
              # Originally drafted under backend/lib/galaxy/ai/retrievers/
              # — moved here to keep production paths clean until validated.
scripts/      # One-off analysis scripts (Phase 0 clustering, dedup audit, …)
tests/        # pytest suite — runs in isolation via PYTHONPATH=.
output/       # Generated artifacts (CSVs, cluster summaries, A/B results)
              # gitignored — regenerable.
```

## How to run

```bash
cd /home/yzhang/biomate
PYTHONPATH=. python -m sandbox.retrieval_v2.scripts.cluster_tools
PYTHONPATH=. pytest sandbox/retrieval_v2/tests/ -v
```

## Promotion criteria

Nothing here gets moved to `backend/lib/galaxy/ai/` until:
1. The Phase 0 clustering output is reviewed and approved
2. The canonical-tools schema is agreed
3. A/B routing benchmark shows ≥ +5pp on the existing 120-case suite
4. All tests in `sandbox/retrieval_v2/tests/` pass against live APIs

This README + the plan docs are the source of truth for what's intended.
