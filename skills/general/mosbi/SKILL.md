---
name: bioconductor-mosbi
description: This package is a implementation of biclustering ensemble method MoSBi (Molecular signature Identification from Biclustering). MoSBi provides standardized interfaces for biclustering results and can combine their results with a multi-algorithm ensemble approach to compute robust ensemble biclusters on molecular omics data. This is done by computing similarity networks of biclusters and filtering for overlaps using a custom error model. After that, the louvain modularity it used to extract biclus
when_to_use: Use when: This package is a implementation of biclustering ensemble method MoSBi (Molecular signature Identification from Bicluste; example-workflow; similarity-metrics-evaluation. Not for: Requires R ≥ 4.1 and Bioconductor ≥ 3.16
user-invocable: false
---

# mosbi

## Workflows

### Standard Workflow

Run multiple biclustering algorithms on a data matrix, construct a similarity network with an error model, extract robust communities, and generate consensus ensemble biclusters.

```r
library(mosbi)

# 1. Prepare data matrix
data(mouse_data)
mouse_data_sub <- mouse_data[c(grep("metabolite_identification", colnames(mouse_data)), grep("^X", colnames(mouse_data)))]
# Simple mock matrix for runnable demonstration
data_matrix <- matrix(rnorm(1000), nrow = 100, ncol = 10)
rownames(data_matrix) <- paste0("M", 1:100)
colnames(data_matrix) <- paste0("S", 1:10)

# 2. Run Biclustering Algorithms
fb <- mosbi::run_fabia(data_matrix)
BCisa <- mosbi::run_isa(data_matrix)
BCplaid <- mosbi::run_plaid(data_matrix)
BCqubic <- mosbi::run_qubic(data_matrix)
all_bics <- c(fb, BCisa, BCplaid, BCqubic)

# 3. Compute Bicluster Similarity Network with Error Model
bic_net <- mosbi::bicluster_network(all_bics, data_matrix, n_randomizations = 5, MARGIN = "both", metric = 4)

# 4. Extract Louvain Communities
coms <- mosbi::get_louvain_communities(bic_net, min_size = 3, bics = all_bics)

# 5. Generate Consensus Ensemble Biclusters
ensemble_bicluster_list <- mosbi::ensemble_biclusters(coms, all_bics, data_matrix, row_threshold = 0.1, col_threshold = 0.1)
```

*Input: A numeric data matrix; Output: A list of robust ensemble biclusters.*

## When to Use
- When you want to run multiple biclustering algorithms (e.g., Fabia via `run_fabia`, ISA via `run_isa`, Plaid via `run_plaid`, QUBIC via `run_qubic`) and combine their results.
- When you need to compute a similarity network of biclusters using metrics like Fowlkes-Mallows index, Jaccard index, Bray-Curtis similarity, or overlap coefficient via `bicluster_network`.
- When you want to extract robust bicluster communities using Louvain modularity via `get_louvain_communities` and generate consensus ensemble biclusters via `ensemble_biclusters`.

## When NOT to Use
- For standard single-algorithm biclustering without ensemble combination, where direct packages like `biclust` or `fabia` can be used directly.
- When you do not have a numeric data matrix (e.g., categorical or purely qualitative data).

## Data Requirements
- A numeric data matrix (e.g., `data_matrix` in the vignette derived from `mouse_data` using `log2` and z-score normalization).
- No missing values are preferred (as noted: "The data has a gaussian-like distribution and no missing values").

## Key Parameters
- **n_randomizations** (5): Number of randomizations for the error model in `bicluster_network`.
- **MARGIN** ("both"): Use datapoints for metric evaluation in `bicluster_network`.
- **metric** (4): Similarity metric index (e.g., 4 for Fowlkes-Mallows index) in `bicluster_network`.
- **n_steps** (1000): Number of steps at which the cut-off is evaluated in `bicluster_network`.
- **plot_edge_dist** (TRUE): Plot the evaluation of cut-off estimation in `bicluster_network`.
- **min_size** (3): Minimum size of communities (number of biclusters) to save in `get_louvain_communities`.
- **row_threshold** (0.1): Minimum occurrence of a row-element in the biclusters of a community to be included in the ensemble bicluster.
- **col_threshold** (0.1): Minimum occurrence of a column-element in the biclusters of a community to be included in the ensemble bicluster.

## Best Practices
- Normalize the input data matrix (e.g., using log2 transformation and z-score scaling) before running biclustering.
- Visualize the size distribution of the generated biclusters using `colhistogram` and `rowhistogram` (or a helper like `bicluster_histo`).
- Evaluate the cut-off estimation for the similarity network by setting `plot_edge_dist = TRUE` in `bicluster_network`.
- Visualize the bicluster similarity network using `plot` or `plot_algo_network` to inspect how different algorithms contribute to communities.

## Common Pitfalls
- Running `get_louvain_communities` with a `min_size` that is too high, resulting in zero saved communities. Fix: Lower `min_size` (e.g., to 3).
- Biclustering algorithms throwing errors or returning empty lists. Fix: Ensure the input data matrix has a gaussian-like distribution and no missing values.

## Alternatives
- `biclust` for running individual biclustering algorithms like Plaid.
- `fabia` for Fabia biclustering.
- `QUBIC` for QUBIC biclustering.
- `isa2` for ISA biclustering.

## Citations
- Rose TD (2025). MoSBi: Molecular signature Identification from Biclustering.

## References
- Homepage: bioconductor.org/packages/mosbi
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/mosbi/inst/doc/example-workflow.html
