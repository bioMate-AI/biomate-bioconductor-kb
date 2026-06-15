---
name: bioconductor-fgsea
description: A tabular file with gene symbols in the first column, and a ranked statistic (e.g. t-statistic or log fold-change) in the second column
when_to_use: "Use when: Fast pathway enrichment analysis on pre-ranked gene lists from differential expression studies; Analyzing transcriptomic or proteomic data with predefined pathway databases; Studies requiring permutation-based statistical testing of gene set enrichment; Researchers needing both tabular results and visualization of top enriched pathways. Not for: Unranked gene lists or raw count data (requires external ranking step); Studies without established gene set databases; Real-time analysis requiring very small p-value thresholds (limited by permutation count); Analyses requiring sample-level enrichm"
user-invocable: false
---

# fgsea

A tabular file with gene symbols in the first column, and a ranked statistic (e.g. t-statistic or log fold-change) in the second column

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 1.38.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** Rcpp, data.table, BiocParallel, ggplot2, cowplot, fastmatch, Matrix, scales
- **Install:** `BiocManager::install("fgsea")`

## When to Use

- Fast pathway enrichment analysis on pre-ranked gene lists from differential expression studies
- Analyzing transcriptomic or proteomic data with predefined pathway databases
- Studies requiring permutation-based statistical testing of gene set enrichment
- Researchers needing both tabular results and visualization of top enriched pathways

## When NOT to Use

- Unranked gene lists or raw count data (requires external ranking step)
- Studies without established gene set databases
- Real-time analysis requiring very small p-value thresholds (limited by permutation count)
- Analyses requiring sample-level enrichment scores rather than pathway-level statistics

## Scientific Assumptions

- {'assumption': 'Gene identifiers are unique within the ranked genes file (no duplicates)', 'violation_context': 'Duplicate gene identifiers may lead to unpredictable behavior or incorrect enrichment calculations', 'quote': 'Gene identifiers must be unique (not repeated) within the file'}
- {'assumption': 'The ranking statistic (e.g., t-statistic, log fold-change) is continuous and reflects biological effect size or significance', 'violation_context': 'Categorical or non-quantitative rankings may produce meaningless enrichment results', 'quote': 'A tabular file with gene symbols in the first column, and a ranked statistic (e.g. t-statistic or log fold-change) in the second column'}
- {'assumption': 'Gene sets are biologically meaningful and appropriately curated', 'violation_context': 'Poorly curated or irrelevant gene sets may produce spurious enrichment results', 'evidence_url': 'http://www.broadinstitute.org/gsea/msigdb', 'quote': "GMT files for human gene sets can be obtained from the Broad's MSigDB collections."}
- {'assumption': 'Permutation-based p-values assume exchangeability of gene rankings under the null hypothesis', 'violation_context': 'Violations may occur with highly correlated genes or non-random gene ranking distributions'}
- {'assumption': 'The ranked list represents a single biological comparison or contrast', 'violation_context': 'Mixing multiple contrasts or conditions in a single ranked list may confound enrichment results'}

## Common Pitfalls

- {'mistake': 'Using gene identifiers that do not match between ranked genes file and gene sets file', 'consequence': 'Gene sets will not be properly matched to ranked genes, resulting in missing or incorrect enrichment results', 'recommendation': 'Ensure gene identifiers are the same type (e.g., all gene symbols, all Entrez IDs) in both input files. Convert identifiers if necessary before running fgsea.'}
- {'mistake': 'Setting gene set size thresholds too restrictively, excluding most pathways', 'consequence': 'Reduced statistical power and potentially missing biologically relevant pathways', 'recommendation': 'Use default thresholds (minimum 1, maximum 500) or justify custom thresholds based on pathway database characteristics. Review excluded pathways.'}
- {'mistake': 'Using insufficient permutations (too few) for desired p-value precision', 'consequence': 'Limited resolution in p-values; minimum nominal p-value is 1/nperm, so 1000 permutations gives minimum p-value of 0.001', 'recommendation': 'Use at least 1000 permutations (default); increase to 10000 for more stringent significance thresholds or multiple testing correction'}
- {'mistake': 'Not accounting for multiple testing correction when interpreting results', 'consequence': 'Inflated false discovery rate; many pathways may appear significant by chance', 'recommendation': 'Apply multiple testing correction (e.g., Benjamini-Hochberg FDR) to p-values or use adjusted p-values if provided in output'}

## Key Parameters

- {'parameter': 'number_of_permutations', 'scientific_meaning': 'Controls the number of random permutations used to calculate empirical p-values for gene set enrichment. Higher values provide more precise p-value estimates.', 'typical_values': '1000 (default), 10000 (for stringent analysis)', 'context_guidance': {'exploratory_analysis': 1000, 'publication_quality': 10000, 'very_stringent_thresholds': 100000}, 'quote': 'Minimal possible nominal p-value is about 1/nperm. Default: 1000'}
- {'parameter': 'minimum_size_of_gene_set', 'scientific_meaning': 'Filters out gene sets smaller than this threshold. Smaller sets may be less statistically robust but more specific.', 'typical_values': '1 (default, no filtering), 5-15 (common for pathway analysis)', 'context_guidance': {'exploratory_analysis': 1, 'pathway_analysis': 5, 'robust_analysis': 15}, 'quote': 'Minimal size of a gene set to test. All pathways below the threshold are excluded. Default: 1'}
- {'parameter': 'maximal_size_of_gene_set', 'scientific_meaning': 'Filters out gene sets larger than this threshold. Very large sets may represent broad biological processes with less specificity.', 'typical_values': '500 (default), 200-300 (for more specific pathways)', 'context_guidance': {'broad_analysis': 500, 'specific_pathways': 300, 'focused_analysis': 200}, 'quote': 'Maximal size of a gene set to test. All pathways above the threshold are excluded. Default: 500'}
- {'parameter': 'file_has_header', 'scientific_meaning': 'Specifies whether the ranked genes file contains a header row. Affects how data is parsed.', 'typical_values': 'Yes (default), No', 'context_guidance': {'standard_tabular_files': 'Yes', 'headerless_files': 'No'}, 'quote': 'If this option is set to Yes, the tool will assume that the ranked genes file has a column header in the first row and the identifers commence on the second line. Default: Yes'}

## Result Interpretation

- {'guidance': 'The output tabular file contains gene set rankings with enrichment statistics. Interpret NES (Normalized Enrichment Score) as the magnitude and direction of enrichment; positive NES indicates enrichment at the top of the ranked list, negative at the bottom. P-values indicate statistical significance of enrichment.'}
- {'guidance': 'PDF plots (if generated) show the running enrichment score for top pathways, visualizing how genes in each pathway are distributed across the ranked list. Peaks indicate where pathway genes are concentrated.'}
- {'guidance': 'Validate results by checking that enriched pathways are biologically consistent with the experimental design and ranked statistic used. Cross-reference with literature and other enrichment tools.'}
- {'guidance': 'RData output file can be loaded into R for custom downstream analysis, visualization, or integration with other analyses. Useful for advanced users requiring detailed access to intermediate calculations.', 'quote': 'Output all the data used by R in the fgsea analysis, can be loaded into R.'}

## Alternatives

- {'tool': 'GSEA (Broad Institute)', 'when_to_prefer_this': 'fgsea is faster for preranked analysis and integrates well into analysis pipelines', 'when_to_prefer_alternative': 'GSEA preferred when analyzing raw expression matrices or requiring class-based comparisons'}
- {'tool': 'clusterProfiler', 'when_to_prefer_this': 'fgsea is optimized for preranked GSEA; clusterProfiler offers broader enrichment methods', 'when_to_prefer_alternative': 'clusterProfiler preferred for over-representation analysis or multiple enrichment methods in one tool'}
- {'tool': 'Enrichr', 'when_to_prefer_this': 'fgsea provides more rigorous statistical testing with permutations', 'when_to_prefer_alternative': 'Enrichr preferred for quick web-based analysis or when gene list ranking is unavailable'}

## Citations

- Korotkevich G, Sukhov V, Budin N, Shpak B, Kupiec M, Sergushichev A. (2021). Fast gene set enrichment analysis. bioRxiv. doi:10.1101/060012

## References

- {'title': 'fgsea Bioconductor package'}
- {'title': 'MSigDB collections', 'url': 'http://www.broadinstitute.org/gsea/msigdb'}
- {'title': 'GMT format specification', 'url': 'http://www.broadinstitute.org/gsea/msigdb'}

<!-- biomate-cta -->
---

## Run this on BioMate

This skill is the **knowledge layer** — when, why, and how to use `fgsea`. To **run this analysis on your own data** with managed compute, automated QC, and reproducible outputs, use **[BioMate](https://www.biomate.ai?ref=kb&pkg=fgsea)** — free to start.

▶ **[Open `fgsea` on BioMate →](https://www.biomate.ai?ref=kb&pkg=fgsea)**
