# Bioc Output Re-Inference — Applied to Live DB

**Date**: 2026-06-10
**Backup**: `backend/database/galaxy_ai_tools.db.backup-20260610-141017` (from earlier session apply)

## Why this work happened

The user's question — *"why do you do this? isn't there an output field for you to use already?"* — pointed at a redundant LLM-judge approach. The per-workflow signal was already in `workflow_json` header comments:

```nextflow
// Bioconductor workflow: DESeq2 — standard_de_from_matrix
// Perform standard differential expression analysis starting from a raw count matrix and sample metadata.
// Input: cts, coldata
// ...
// Steps:
//  * 1. [Input & Preparation] Construct DESeqDataSet from matrix
//  * 2. [Core Analysis] Pre-filter low count genes
//  ...
//  * 6. [Visualization & Output] Visualize results (MA-plot, plotCounts)
//  * 7. [Visualization & Output] Export results to CSV
```

Three fields (header purpose, `Input:` line, `Steps:` list) extractable via regex at 100% coverage. Plus `annotation_v2.when_to_use` (81% coverage). All free, all deterministic.

The originally-planned LLM-judge run would have cost ~$14 and run ~5.7 hours to derive what `grep` extracts in 0.3 seconds.

## What was applied

Atomic SQL UPDATE batch:

| Operation | Count |
|---|---|
| Bioc rows with stub output_types pre-apply | 2,775 |
| Confidence-thresholded proposals (≥0.7) | 2,122 |
| Rows actually UPDATEd | **2,123** (one extra match — whitespace tolerance) |
| Bioc rows remaining on stub | 652 (23% — the no-match cases) |

## Resulting catalog state

| Metric | Pre-apply | Post-apply |
|---|---|---|
| Workflows with real typed outputs | 310 (non-Bioc only) | **2,492** |
| Type-flow graph scope | non-Bioc only | **whole catalog** |
| Bioc producing `de_table` | invisible | **487** |
| Bioc producing `enrichment_results` | invisible | **199** |
| Bioc producing `gwas_summary_statistics` | invisible | **89** |
| Bioc producing `copy_number_segments` | invisible | **138** |
| Bioc producing `singlecellexperiment` | invisible | **74** |
| Calibration mode match | 100% | **100%** (no regression) |
| Unit tests | 48 pass | 48 pass |

## What this enables for chain discovery

The deep-survey (`docs/20260610_DEEP_WORKFLOW_SURVEY.md`) found 4 cross-source bridges from non-Bioc producers to Bioc consumers. With Bioc outputs now visible, those bridges become **bidirectional**: Bioc workflows can be both consumers AND producers, enabling chains like:

- `nf-core/rnaseq → deseq2 → clusterprofiler` (every typed-port hop now verifiable)
- `nf-core/sarek → musicatk → katdetectr` (variant→signature→hypermutation)
- `xcms → camera → biosigner` (LC-MS pipeline)
- `nf-core/scrnaseq → scater → mast / monocle` (single-cell DE)

All four of the 6 newly-applied chains from this session are now traceable end-to-end at the type level for the first time.

## Distribution of inferred kinds (top 10)

| Kind | Count | Bioc count after apply |
|---|---|---|
| visualizations | 1,294 | 1,294 |
| de_table | 487 | 487 |
| normalized_data | 345 | 345 |
| cluster_assignments | 288 | 288 |
| enrichment_results | 199 | 199 |
| copy_number_segments | 138 | 138 |
| consensus_score | 93 | 93 |
| gwas_summary_statistics | 89 | 89 |
| counts_matrix | 87 | 87 |
| expression_matrix | 87 | 87 |
| singlecellexperiment | 74 | 74 |

## The 648 no-match remain on stub

Specialized analyses my keyword rules don't catch (alternative polyadenylation, epimutation, vulnerability profiling, anvil billing, etc.). Three options for closing the gap:

1. **Expand `_RULES` in `bioc_output_inferrer.py`** with another ~15 patterns covering the no-match topics. Re-run. Free + deterministic.
2. **Run LLM judge on just the 648** — ~$3, ~1 hour. Now affordable since only 23% need it.
3. **Leave as stub** — they're rarely-queried analyses; impact on chain discovery is small.

(1) is the obvious next step if you want to close the gap.

## Reversibility

To revert all 2,123 rows to the stub:

```bash
sqlite3 backend/database/galaxy_ai_tools.db <<'SQL'
UPDATE workflows
SET output_types = '["table/csv", "plot/pdf", "object/rds"]'
WHERE source = 'bioconductor';
SQL
```

Or restore from the pre-session backup:

```bash
cp backend/database/galaxy_ai_tools.db.backup-20260610-141017 \
   backend/database/galaxy_ai_tools.db
```

## Lesson recorded

The user's question saved ~$14 and ~5.7 hours by forcing a re-check of the data before invoking the LLM. The pattern: **before any LLM-judge run on a structured catalog field, audit which fields ALREADY contain the signal**. Header comments, structured annotation fields, and JSON config files often carry more than the surface-level typed fields suggest.
