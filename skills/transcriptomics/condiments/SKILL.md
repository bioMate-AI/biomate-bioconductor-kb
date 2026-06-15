---
name: bioconductor-condiments
description: This package encapsulate many functions to conduct a differential topology analysis. It focuses on analyzing an 'omic dataset with multiple conditions. While the package is mostly geared toward scRNASeq, it does not place any restriction on the actual input format.
when_to_use: Use when: The condiments workflow; Using condiments; Generating more examples; Single-cell RNA-seq analysis (condiments). Not for: Requires R ≥ 4.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# condiments

## Workflows

### Standard Workflow

Perform differential topology, progression, and fate selection analysis on single-cell data across multiple conditions.

```r
library(condiments)
library(slingshot)
library(dplyr)

# Load toy dataset
data("toy_dataset", package = "condiments")
df <- toy_dataset$sd

# 1. Compute imbalance scores
scores <- imbalance_score(
  Object = df %>% select(Dim1, Dim2) %>% as.matrix(),
  conditions = df$conditions
)
df$scores <- scores$scores
df$scaled_scores <- scores$scaled_scores

# 2. Infer a common trajectory using slingshot
rd <- as.matrix(df[, c("Dim1", "Dim2")])
sds <- slingshot(rd, df$cl)

# 3. Test trajectory topology
top_res <- topologyTest(sds = sds, conditions = df$conditions, rep = 10)

# 4. Test for differential progression along lineages
prog_res <- progressionTest(sds, conditions = df$conditions, global = TRUE, lineages = TRUE)

# 5. Test for differential fate selection between lineages
dif_res <- fateSelectionTest(sds, conditions = df$conditions, global = FALSE, pairwise = TRUE)
```
*Note on inputs/outputs:* Input is a cell metadata data frame containing reduced dimensions and condition assignments; outputs are statistical test tables assessing differences in topology, progression, and fate selection between conditions.

## When to Use
- **Differential Topology Analysis:** Determine if a common trajectory can be fitted across conditions or if separate trajectories are required using `topologyTest`.
- **Differential Progression Analysis:** Test if cells from different conditions are equally represented along pseudotime within a lineage using `progressionTest`.
- **Differential Fate Selection:** Assess whether cells differentiate preferentially along specific lineages across different conditions using `fateSelectionTest`.
- **Imbalance Score Estimation:** Identify regions of local condition imbalance in a reduced dimensional space using `imbalance_score`.

## When NOT to Use
- **Gene-Level Differential Expression:** For testing individual gene expression changes along a trajectory, use `tradeSeq` (specifically `fitGAM` and `conditionTest`) instead of `condiments` directly.
- **Strong Topology Disruption:** If `topologyTest` rejects the null hypothesis, do not fit a common trajectory; instead, infer separate trajectories for each condition.

## Data Requirements
- **Reduced Dimensions:** A matrix of coordinates in a reduced dimension space (e.g., PCA, UMAP, t-SNE).
- **Condition Labels:** A vector assigning each cell to a specific condition (e.g., "A" or "B").
- **Cluster Labels:** Cell cluster assignments for trajectory construction.
- **Example Structure:**
  ```r
  data("toy_dataset", package = "condiments")
  df <- toy_dataset$sd
  rd <- as.matrix(df[, c("Dim1", "Dim2")])
  conditions <- df$conditions
  cl <- df$cl
  ```

## Key Parameters
- **Object**: A matrix of reduced dimensions passed to `imbalance_score`.
- **conditions**: A vector of condition assignments for each cell.
- **sds**: A `PseudotimeOrdering` object (from `slingshot`) representing the inferred trajectory.
- **rep** (100): Number of permutations used to generate trajectories under the null in `topologyTest`.
- **methods** ("KS_mean"): The test method(s) to use in `topologyTest` (e.g., `"KS_mean"`, `"Classifier"`, `"wasserstein_permutation"`).
- **global** (TRUE): Logical indicating whether to run a global test pooling all lineages in `progressionTest` or `fateSelectionTest`.
- **lineages** (TRUE): Logical indicating whether to test every lineage independently in `progressionTest`.
- **pairwise** (TRUE): Logical indicating whether to test every pair of lineages independently in `fateSelectionTest`.

## Best Practices
- **Check Integration Quality:** Compute local imbalance scores using `imbalance_score` to verify if integration was successful (some regions should be balanced).
- **Pre-test Topology:** Always run `topologyTest` before downstream differential analysis to justify fitting a common trajectory.
- **Multiple Testing Correction:** Correct the resulting p-values from `progressionTest` and `fateSelectionTest` for multiple testing, especially for trajectories with a large number of lineages.
- **Treat P-values as Suggestions:** Trajectory inference is at the end of a long pipeline; do not put absolute faith in raw p-values and treat them as exploratory suggestions.

## Common Pitfalls
- **Slow Execution of Topology Test:** `topologyTest` can be slow on large datasets; mitigate this by reducing the `rep` parameter or enabling parallelization with `parallel = TRUE` and a configured `BPPARAM`.
- **Noisy Imbalance Scores:** Raw imbalance scores can be noisy; use the `smooth` argument in `imbalance_score` to obtain smoothed, scaled scores.
- **Over-interpreting Uncorrected P-values:** Trajectory tests make multiple comparisons; always apply multiple testing correction to avoid false positives.

## Alternatives
- **slingshot**: For basic trajectory inference without condition-level differential topology tests.
- **tradeSeq**: For gene-level differential expression analysis along trajectories using `fitGAM` and `conditionTest`.
- **scater** / **scran**: For upstream single-cell preprocessing, normalization, and dimensionality reduction.

## Citations
- Street et al. 2018, BMC Genomics (Slingshot trajectory inference)
- Van den Berge et al. 2020, Nature Communications (tradeSeq differential expression)
- Lopez-Paz and Oquab 2016, Arxiv (Classifier two-sample tests)
- Smirnov 1939, Bull. Math. Univ. Moscou (Kolmogorov-Smirnov test)

## References
- Homepage: https://bioconductor.org/packages/condiments
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/condiments/inst/doc/condiments.html
