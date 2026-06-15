---
name: bioconductor-bionar
description: the R package BioNAR, developed to step by step analysis of PPI network. The aim is to quantify and rank each protein’s simultaneous impact into multiple complexes based on network topology and clustering. Package also enables estimating of co-occurrence of diseases across the network and specific clusters pointing towards shared/common mechanisms.
when_to_use: Use when: BioNAR: Biological Network Analysis in R. Not for: Requires R ≥ 3.5.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# BioNAR

## Workflows

### Standard Workflow

Build, annotate, and analyze a protein-protein interaction (PPI) network to identify central proteins, functional communities, bridging proteins, and disease/annotation overlaps.

```r
library(BioNAR)

# 1. Build the network from a data frame
file <- system.file("extdata", "PPI_Presynaptic.csv", package = "BioNAR")
tbl <- read.csv(file, sep="\t")
gg <- buildNetwork(tbl)

# 2. Annotate vertices with gene names and diseases
gg <- annotateGeneNames(gg)
afile <- system.file("extdata", "flatfile_human_gene2HDO.csv", package = "BioNAR")
dis <- read.table(afile, sep="\t", skip=1, header=FALSE, strip.white=TRUE, quote="")
gg <- annotateTopOntoOVG(gg, dis)

# 3. Estimate vertex centrality measures
gg <- calcCentrality(gg)
mc <- getCentralityMatrix(gg)

# 4. Fit degree distribution to power law and estimate entropy rate
pFit <- fitDegree(as.vector(igraph::degree(graph=gg)), threads=1, Nsim=5, plot=FALSE)
ent <- getEntropyRate(gg)
SRprime <- getEntropy(gg, maxSr = NULL)

# 5. Perform community detection (clustering) and evaluate modularity
nm <- normModularity(gg, alg = 'louvain')
mem <- calcMembership(gg, alg = 'louvain')
gg <- calcClustering(gg, alg = 'louvain')

# 6. Recluster dense communities
remem <- calcReclusterMatrix(gg, mem, alg = 'louvain', 10)

# 7. Build consensus matrix and evaluate cluster robustness
conmat <- makeConsensusMatrix(gg, N = 5, alg = 'louvain', type = 2, mask = 10, reclust = FALSE)
clrob <- getRobustness(gg, alg = 'louvain', conmat)

# 8. Calculate and plot bridgeness
br <- getBridgeness(gg, alg = 'louvain', conmat)
gg <- calcBridgeness(gg, alg = 'louvain', conmat)
g <- plotBridgeness(gg, alg = 'louvain', VIPs = c('8495', '22999'), Xatt = 'SL')
```
*Input: A data frame of protein-protein interactions. Output: An annotated igraph object with calculated centralities, community memberships, and bridgeness metrics.*

## When to Use
- Analyzing protein-protein interaction (PPI) networks to identify key topological features and central proteins using `calcCentrality()`.
- Detecting functional communities or complexes using multiple clustering algorithms (e.g., Louvain, Walktrap) via `calcAllClustering()`.
- Identifying bridging proteins that connect different functional communities using `getBridgeness()`.
- Evaluating network scale-free properties and entropy rates using `fitDegree()` and `getEntropyRate()`.

## When NOT to Use
- For reconstructing networks directly from raw gene expression data (e.g., co-expression network construction); use `WGCNA` instead.
- For basic, non-biological general graph theory operations where standard `igraph` or `tidygraph` suffices without biological annotations.

## Data Requirements
- Input data frame with interaction pairs (columns representing interacting nodes, e.g., Entrez IDs).
- Annotation files mapping Entrez IDs to gene names, diseases (HDO), or GO terms.

## Key Parameters
- **alg**: Clustering algorithm to use (e.g., `"louvain"`, `"wt"`, `"fc"`, `"infomap"`, `"lec"`).
- **N**: Number of randomization rounds for consensus matrix generation (typically 500).
- **type**: Sampling scheme for consensus matrix (1 for sampling edges, 2 for sampling vertices).
- **mask**: Percentage of edges or vertices to mask during perturbation.
- **Xatt**: Centrality measure to plot against bridgeness (e.g., `"SL"` for semilocal centrality).

## Best Practices
- Ensure all nodes have non-empty `GeneName` attributes before running downstream annotation and analysis functions.
- Use `calcAllClustering()` to compare multiple community detection algorithms and evaluate their modularity using `clusteringSummary()`.
- Run at least 500 randomization rounds (`N = 500`) in `makeConsensusMatrix()` for real-world robustness analysis.

## Common Pitfalls
- Using too few randomization rounds for consensus matrix: Leads to inaccurate bridgeness and robustness estimates. Fix: Increase `N` to at least 500 in `makeConsensusMatrix()`.
- Missing gene name annotations: Causes downstream functions that rely on gene names to fail. Fix: Run `annotateGeneNames()` and verify with `any(is.na(V(gg)$GeneName))`.

## Alternatives
- `igraph`: For general network analysis and basic clustering without specialized biological workflows.
- `pRoloc`: For spatial proteomics and organelle assignment (not network-topology based).

## Citations
- Menche et al. 2015, Science (for disease-disease overlap).
- Nepusz et al. 2008 (for bridgeness).

## References
- Homepage: bioconductor.org/packages/BioNAR
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/BioNAR/inst/doc/BioNAR.html
