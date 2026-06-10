# Bioc Output-Type Re-Extraction — Proposal

For each of the 50 Bioconductor workflows whose `output_types` is the indexer stub `['table/csv', 'plot/pdf', 'object/rds']`, LLM Haiku picks 1-3 canonical output kinds from a closed vocabulary.

## Aggregate

- Workflows considered: **50**
- Method distribution: {'llm': 50}
- High-confidence proposals (≥0.7): **50** (100%)
- Low-confidence (<0.4) — flag for review: **0**

## Proposed output kind distribution (high-confidence only)

| Output kind | Count | Share |
|---|---|---|
| `visualizations` | 21 | 21.6% |
| `de_table` | 12 | 12.4% |
| `copy_number_segments` | 11 | 11.3% |
| `expression_matrix` | 10 | 10.3% |
| `qc_report` | 8 | 8.2% |
| `general_rds` | 8 | 8.2% |
| `normalized_data` | 6 | 6.2% |
| `cluster_assignments` | 4 | 4.1% |
| `enrichment_results` | 3 | 3.1% |
| `singlecellexperiment` | 3 | 3.1% |
| `pathway_results` | 2 | 2.1% |
| `consensus_score` | 2 | 2.1% |
| `summarizedexperiment` | 2 | 2.1% |
| `feature_selection` | 1 | 1.0% |
| `differential_abundance` | 1 | 1.0% |
| `counts_matrix` | 1 | 1.0% |
| `cell_type_annotations` | 1 | 1.0% |
| `annotated_genes` | 1 | 1.0% |

## To apply

Filter to `confidence >= 0.7` and `method == 'llm'`, then UPDATE workflows SET output_types per accepted row. After applying, re-run the type-flow graph analysis from the deep survey to confirm Bioc connectivity is now visible.