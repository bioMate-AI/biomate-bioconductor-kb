# Apply-Impact Simulation — Combined Proposals

Built by copying the live catalog DB to a scratch path, then applying:
- 5 hub-anchored curated chain proposals (`backend/lib/galaxy/ai/chain_composer/proposed_chains/*.json`)
- High-confidence domain reclassifications (`docs/20260610_DOMAIN_RECLASSIFICATION_PROPOSAL.jsonl`, confidence ≥ 0.7, method=llm, target≠general)
- High-confidence placeholder groundings (`docs/20260610_PLACEHOLDER_GROUNDING.jsonl`, confidence ≥ 0.7, method=llm)

The original DB is **not modified**; this simulator is a read-only preview of what applying the proposals would change.

## Operations applied

| Operation | Count | Notes |
|---|---|---|
| New curated chains inserted | 6 | from `proposed_chains/` |
| Workflows relabeled out of `general` | 0 | confidence ≥ 0.7 |
| Placeholder names rewritten in `workflow_chains.steps` | 0 | confidence ≥ 0.7 |
| Distinct placeholders applied | 30 | ≤ steps_rewritten (some appear in multiple chains) |

## Catalog state before vs after

| Metric | Before | After | Δ |
|---|---|---|---|
| executable_workflows | 3,960 | 3,960 | — |
| general_domain | 119 | 119 | — |
| curated_chains | 34 | 40 | +6 |
| chain_step_references | 115 | 134 | +19 |
| chain_steps_grounded_in_catalog | 81 | 100 | +19 |
| chain_step_grounding_pct | 70.4% | 74.6% | +4.199999999999989pp |

## Concrete impact

- **`general` bucket shrinks by 0 workflows** (0% reduction). Those workflows now reachable by domain-faceted features.
- **Curated chain step grounding lifts 70.4% → 74.6% (+4.2pp)**. Each step now more likely to resolve to a real catalog workflow at execution time.
- **6 new curated chains** add coverage for previously-uncovered patterns (time_series_longitudinal, multi_method_consensus / piano, cross_cohort_replication / bacon, scRNA-ADT multimodal, phylogenetic uncertainty).

## Next: re-run calibration against the scratch DB

```bash
export PYTHONPATH=$PWD/backend/lib
export BIOMATE_AI_TOOLS_DB=/tmp/galaxy_ai_tools_PROPOSED.db
python -m galaxy.ai.chain_composer.catalog_audit --output docs/20260610_CATALOG_AUDIT_AFTER_APPLY.md
python -m galaxy.ai.chain_composer.calibrate backend/lib/galaxy/ai/chain_composer/eval_queries.jsonl
```