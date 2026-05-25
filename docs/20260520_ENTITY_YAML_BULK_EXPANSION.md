# Entity YAML Bulk Expansion — 17 → 192 entries via mygene.info

**Date:** 2026-05-20
**Status:** Expansion produced in sandbox/output; held-out validated; NOT yet merged into `backend/config/entity_canonicals.yaml`.
**Per user directive:** "the entity things sound like a normalization work that can use an existing vocabulary or kb."

## What was built

Reusable bulk-import script that fetches canonical entity aliases from mygene.info (already used by the OMIM retriever) for a curated seed list of 190 high-traffic BioMate-relevant genes.

```
sandbox/intent_retrieval_v3/scripts/expand_entity_yaml.py
    ├─ Seed list: 190 hand-picked symbols (cancer, drug targets, rare disease,
    │   CYP enzymes, immunology, hematology, neuro)
    ├─ For each: mygene.info /v3/query → name + aliases + OMIM ID
    ├─ Output: sandbox/intent_retrieval_v3/output/entity_canonicals_expanded.yaml
    │   (186 genes, 1267 aliases — gene-only)
    └─ Merged with original: 192 entries (genes + diseases + drugs + cell lines)
```

## Numbers

| Metric | Original (hand-curated) | Expanded (mygene) | Merged |
|---|---|---|---|
| Total entries | 17 | 186 | 192 |
| Genes | 6 | 186 | 186 |
| Diseases | 3 | 0 | 3 |
| Drugs | 2 | 0 | 2 |
| Cell lines | 2 | 0 | 2 |
| Total aliases | ~70 | 1,267 | ~1,340 |

## Held-out safety check (n=30 — same test as session-original)

| YAML | perfect | false positives | false negatives |
|---|---|---|---|
| Original 17-entry (sandbox baseline) | 29/30 | 0 | 1 (coverage gap) |
| **Merged 192-entry** | **29/30** | **0** | **1** (same coverage gap) |

**Zero new false positives despite 11× more entries.** The word-boundary + longest-alias-wins discipline holds:
- TPM3 doesn't false-match TP53 ✓
- TP53BP1 doesn't false-match TP53 ✓
- "BRCA-associated" (no digit) doesn't fire BRCA1 or BRCA2 ✓
- "RAS" alone doesn't fire KRAS/NRAS/HRAS (despite all 3 being in expanded YAML!) ✓

Sanity-check of newly-imported entries — all 13 sample queries extracted correctly:
- "KRAS G12D" → KRAS
- "MYC amplification" → MYC
- "NF1 neurofibromatosis" → NF1
- "MET exon 14 skipping" → MET
- "EGFR T790M" → EGFR
- "JAK2 V617F polycythemia" → JAK2
- "ALK fusion in NSCLC" → ALK
- "CFTR ΔF508" → CFTR
- "G6PD deficiency" → G6PD
- "Patient is APOE ε4/ε4" → APOE
- ...

## Why "use existing KB" was the right framing

Three benefits realized:

1. **No hand-curation toil.** The 186 expansion genes + their aliases came from one HTTP call per gene to mygene.info. Total fetch time: ~30 seconds (cached).

2. **Authoritative aliases.** mygene.info returns HGNC's curated prev_symbols and alias lists. No risk of me transcribing incorrectly.

3. **Reproducible.** The script + seed list are committed. Future expansions add more seeds; the cache prevents redundant fetches.

4. **Discovers genuine renames.** 4 of my 190 seeds returned nothing (`MEK1`, `GBA`, `SPG4`, `CD20`) — these are obsolete HGNC symbols that have been renamed (e.g., MEK1 → MAP2K1). The non-result is itself useful signal: don't include obsolete symbols in production data.

## What's deferred (not in this PR)

Per the deploy discipline:

- ❌ The merged 192-entry YAML is **not** copied to `backend/config/entity_canonicals.yaml`. That's a separate authorization step.
- ❌ No callers updated. Even if merged, no production code path currently extracts entities.
- ❌ Drug + disease + cell-line bulk-import deferred. The script focuses on genes; ChEMBL/OMIM/Cellosaurus would each need their own seed list + API integration (~half day each).

## How to promote when authorized

When ready:

```bash
# Option 1: replace
cp sandbox/intent_retrieval_v3/output/entity_canonicals_merged.yaml \
   backend/config/entity_canonicals.yaml

# Option 2: keep sandbox, point env at it (preserves rollback)
export BIOMATE_ENTITY_YAML=$(pwd)/sandbox/intent_retrieval_v3/output/entity_canonicals_merged.yaml
```

Then re-run any held-out + safety tests against the new path.

## Cumulative session — 21 commits

| Library | Status | Tests |
|---|---|---|
| family_dedup (wrapper-level) | shipped, opt-in | 29 |
| WiredToolParameterRecommender | shipped wrapper | 15 |
| workflow_intent | sandbox + benchmark | 18 |
| WiredWorkflowSearch | shipped wrapper | 6 |
| memory (file-based) | sandbox + held-out | 8 |
| WiredAgenticMemoryService (SQL hierarchy) | shipped wrapper | 9 |
| entity (sandbox) | held-out validated | 13 |
| **entity bulk-import script + merged YAML** | **NEW — held-out clean** | (re-uses adapter tests) |
| chat_session | sandbox + held-out | 15 |
| Framework regression | unaffected | 62 |
| **Total** | | **175 still passing** |

## What this enables

Once the merged YAML is promoted (single-line copy):
- `entity` adapter coverage jumps 11× → can resolve "MYC", "ALK", "ROS1", "JAK2", "APOE", "CFTR", "DMD", "HTT", "EGFR T790M", "JAK2 V617F", etc. — all queries it previously returned [] on
- `WiredAgenticMemoryService.recall_for_query` benefits proportionally — every newly-resolvable canonical entity widens episode recall in BioMate's hierarchical memory

The Entity-YAML expansion is **purely curation work made automatic via existing KB**. No new code paths, no new failure modes — the same library, just with more data.

## Operational notes for next session

1. `sandbox/intent_retrieval_v3/output/.mygene_cache/` holds disk-cached mygene responses. ~190 files, small. Safe to delete; will refetch on next run.
2. Seed list in `expand_entity_yaml.py` is curated for biology/drug discovery. Pharmacogenomics (TPMT, CYP enzymes) and immunotherapy targets (PD-1, CTLA4, etc.) are covered. Add to `SEED_GENES` list to extend.
3. The script uses 50ms sleep between mygene calls — be nicer if running larger batches.
4. mygene.info is free + public; no API key needed.

Per the deploy discipline: this work is bulk-imported into sandbox, validated, and held there awaiting authorization to promote.
