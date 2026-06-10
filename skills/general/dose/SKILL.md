---
name: bioconductor-dose
description: This package implements five methods proposed by Resnik, Schlicker, Jiang, Lin and Wang respectively for measuring semantic similarities among DO terms and gene products. Enrichment analyses including hypergeometric model and gene set enric
when_to_use: Use when: Use when analyzing high-throughput genomic data (such as RNA-seq or microarray gene lists) to identify associated diseases, or when calculating functional similarity between genes based on disease annotations.
user-invocable: false
---

# DOSE

## Dependencies & Environment

> Package-intrinsic requirements from the Bioconductor landing page — reproduce in any R environment.

- **Version:** 4.6.0 · **Bioconductor:** 3.23 · **R:** ≥ 4.6
- **Imports:** AnnotationDbi, enrichit, ggplot2, GOSemSim, reshape2, yulab.utils
- **Install:** `BiocManager::install("DOSE")`

## When to Use

- **Disease Ontology Analysis**: Performing Disease Ontology Semantic and Enrichment analysis as described by the package authors.

## When NOT to Use

- For formatting R markdown documents, use `knitr` because DOSE is strictly for Disease Ontology analysis.

## Data Requirements

- Requires loading the package into the R session via `library(DOSE)`.

## Key Parameters

- **`gene`**: A vector of Entrez gene IDs for over-representation analysis
- **`organism`**: Organism identifier (default is "human")
- **`pvalueCutoff`**: P-value cutoff threshold for enrichment significance
- **`pAdjustMethod`**: Method used for p-value adjustment (e.g., "BH", "bonferroni")
- **`measure`**: Semantic similarity method (one of "Resnik", "Schlicker", "Jiang", "Lin", or "Wang")

## Workflow Variants

### Disease Ontology Enrichment

**Intent**: Perform over-representation analysis of disease ontology terms on a list of Entrez gene IDs.

**Inputs**:
- `gene_list.txt (a vector of Entrez gene IDs)`

**Steps**:
1. Load the DOSE package
2. Run enrichment analysis using enrichDO, enrichDGN, or enrichNCG
3. Visualize results using simplot or theme_dose.

```r
library(DOSE)
```


---

### Gene Set Enrichment Analysis

**Intent**: Perform gene set enrichment analysis using disease ontology.

**Inputs**:
- `ranked_gene_list.txt (a sorted, named numeric vector of fold changes with Entrez gene IDs as names)`

**Steps**:
1. Load the DOSE package
2. Run gene set enrichment analysis using gseDO, gseDGN, or gseNCG.

```r
library(DOSE)
```


---

### Semantic Similarity Analysis

**Intent**: Calculate semantic similarity between DO terms or genes.

**Inputs**:
- `gene_ids.txt (a vector of Entrez gene IDs or DO term IDs)`

**Steps**:
1. Load the DOSE package
2. Compute semantic similarity using doSim, geneSim, clusterSim, or mclusterSim.

```r
library(DOSE)
```


## Best Practices

- Load the package using `library(DOSE)`.
- Cite the primary publication (Yu et al. 2015) when using DOSE in published research.

## Common Pitfalls

- Inputting gene symbols instead of Entrez gene IDs, which will result in empty or failed enrichment analyses
- Failing to sort the gene list in decreasing order of fold change before running GSEA functions (gseDO, gseDGN, gseNCG).

## Alternatives

- **clusterProfiler**: Use when performing broader functional enrichment analyses such as GO or KEGG pathway analysis
- **meshes**: Use when semantic similarity or enrichment analysis of MeSH terms is required

## Citations

- G Yu, LG Wang, GR Yan, QY He. DOSE: an R/Bioconductor package for Disease Ontology Semantic and Enrichment analysis. Bioinformatics 2015, 31(4):608-609.

## References

- Homepage: https://bioconductor.org/packages/DOSE
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/DOSE/inst/doc/DOSE.html
