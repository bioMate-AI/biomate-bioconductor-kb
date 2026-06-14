# Applied to Live Catalog — 2026-06-10

**Backup**: `/home/yzhang/biomate/backend/database/galaxy_ai_tools.db.backup-20260610-141017` (318 MB, pre-apply state)

User directive: "all in parallel" — applied all three proposal classes atomically to the live catalog DB.

## What was applied (single transaction)

| Operation | Count | Source |
|---|---|---|
| Curated chains inserted | **5** | `backend/lib/galaxy/ai/chain_composer/proposed_chains/*.json` |
| Placeholder step rewrites in `workflow_chains.steps` | **42 across 21 chains** | `docs/20260610_PLACEHOLDER_GROUNDING.jsonl` (confidence ≥ 0.7, method=llm) |
| Domain reassignments out of `general` | **535 rows** | `docs/20260610_DOMAIN_RECLASSIFICATION_PROPOSAL.jsonl` (confidence ≥ 0.7, method=llm, target ≠ general) |

## Verified deltas (live audit after apply)

| Metric | Before | After | Δ |
|---|---|---|---|
| Total curated chains | 29 | **34** | +5 |
| Unique step names in chains | 69 | 74 | +5 |
| Step names that exist in catalog | 16 (23%) | **51 (69%)** | +35 / **+46pp** |
| Curated chains spanning ≥2 sources | 2 (7%) | **17 (50%)** | +15 / **+43pp** |
| Workflows in `general` domain | 664 | **129** | **-535 (-80%)** |
| Synthetic-eval calibration mode match | 100% | **100%** | unchanged |

## New domain distribution (top 20)

| Domain | Count | Δ from before |
|---|---|---|
| transcriptomics | 1,688 | +108 |
| genomics | 741 | +152 |
| epigenomics | 261 | +14 |
| variant_calling | 179 | +10 |
| proteomics | 174 | +11 |
| `general` | 129 | **-535** |
| drug_discovery | 110 | +12 |
| systems_biology | 106 | **+94** (was 12) |
| single_cell | 85 | +44 |
| imaging | 77 | +2 |
| metagenomics | 75 | +10 |
| metabolomics | 56 | +20 |
| pharmacology | 39 | +16 |
| genetics | 35 | +24 |
| molecular_biology | 33 | +5 |
| bioimaging | 24 | +2 |
| immunology | 23 | +10 |
| microbiology | 17 | +1 |

The `systems_biology` jump from 12 → 106 is the most dramatic: Bioconductor network / pathway / metabolic modeling packages were heavily misclassified to `general` previously.

## Spot-check: existing chain step rewritten correctly

```
chain: rare_disease_multimodal_workup
  step 1: nf-core/sarek
  step 2: nf-core/vcf_annotate_ensemblvep  (was placeholder `vep_annotation`)
```

`nf-core/vcf_annotate_ensemblvep` is a real catalog workflow; the chain is now executable through step 2 instead of failing at the placeholder.

## What did NOT change

- No production code paths touched (`ai_assistant.py`, `galaxy-assistant.ts`, `routes.ts` all unchanged in this session)
- No new workflows added to `workflows` table (all 3,960 executable workflows pre-existed)
- No schema changes
- Calibration mode match stayed at 100% (no regression)
- 119 workflows correctly stay in `general` (true cross-domain utility packages: Biobase, BiocPkgTools, BiocSklearn, BridgeDbR, etc.)

## Reversibility

To revert all changes:

```bash
# Restore from backup:
cp /home/yzhang/biomate/backend/database/galaxy_ai_tools.db.backup-20260610-141017 \
   /home/yzhang/biomate/backend/database/galaxy_ai_tools.db
```

Or to revert selectively (e.g. keep new chains, undo domain reassignments):

```python
import json, sqlite3
# Read the JSONLs in the docs/ folder; they record the BEFORE state in current_domain.
# Write the reverse UPDATE for each row.
```

## What this enables for users (real product effect)

Before today: a user asking *"I want to build a metabolic network model from gene expression data"* would get domain-faceted retrieval blind to BiGGR (was in `general`). The chat composer would have to fall through to L3 free-composition.

After today: the same query routes to `systems_biology` domain, BiGGR surfaces in the candidate list, and the composer can ground the plan in a real catalog workflow. Same logic applies for the 534 other workflows that moved into a specific domain.

Plus: 17 of the 34 curated chains now span multiple sources (cross-domain), vs 2 of 29 previously. The "connect specialties seamlessly" vision is materially closer.

## Tests still passing

```
$ python -m pytest backend/tests/test_chain_composer.py -q
48 passed, 3 skipped, 1 warning in 1.04s
```

Calibration (against the now-modified live DB):
```
queries=20  llm=0  curated=19  stub=1
mode_match_rate:   100.00%
pattern_top_k_hit: 100.00%
```

## Honest caveats

1. **No real-user telemetry yet.** The calibration is on a 20-query synthetic eval. Live traffic may surface mode shifts we haven't anticipated.
2. **The 17 LLM-failure rows in domain reclassification stayed in `general`.** These can be retried with a re-run targeting just those names.
3. **22 placeholders remain ungrounded** (the LLM correctly declined — no catalog fit). These are enumerated catalog gaps that need actual workflow authoring before those chains are fully executable.
4. **`unified_workflow_search` BGE embeddings are stale** for the 534 newly-relabeled workflows. Their embeddings still encode the old `general` domain context. A BGE refresh pass would close this — not done in this session.
5. **`source` field on the 5 new chains is `"curated"`** rather than something like `"learned"` or `"experimental"`. If you want to mark them as new in dashboards, an UPDATE on `source` is a one-liner.
