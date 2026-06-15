---
name: bioconductor-syntenet
description: syntenet can be used to infer synteny networks from whole-genome protein sequences and analyze them. Anchor pairs are detected with the MCScanX algorithm, which was ported to this package with the Rcpp framework for R and C++ integration. Anchor pairs from synteny analyses are treated as an undirected unweighted graph (i.e., a synteny network), and users can perform: i. network clustering; ii. phylogenomic profiling (by identifying which species contain which clusters) and; iii. microsynteny-bas
when_to_use: Use when: Inference and Analysis of Synteny Networks. Not for: Requires R ≥ 4.2 and Bioconductor ≥ 3.16
user-invocable: false
---

# syntenet

## Workflows

### Standard Workflow

Infer a global synteny network from multiple proteomes, cluster it, perform phylogenomic profiling, and reconstruct a microsynteny-based phylogeny.

```r
library(syntenet)
data(proteomes)
data(annotation)
data(blast_list)

# Check and process input data
check_input(proteomes, annotation)
pdata <- process_input(proteomes, annotation)

# Infer synteny network
net <- infer_syntenet(blast_list, pdata$annotation)

# Cluster network and perform phylogenomic profiling
data(network)
clusters <- cluster_network(network)
profiles <- phylogenomic_profile(clusters)
```
*Input: Proteome sequences as a list of AAStringSet objects and gene annotations as a GRangesList. Output: A synteny network edge list and a matrix of phylogenomic profiles.*

### Pairwise Synteny Detection

Detect and parse intra- and inter-species syntenic blocks and anchor pairs.

```r
library(syntenet)
data(proteomes)
data(annotation)
data(blast_list)

# Preprocess input data
pdata <- process_input(proteomes, annotation)

# Detect synteny and infer anchor pairs
net <- infer_syntenet(blast_list, pdata$annotation)
```
*Input: Preprocessed proteome sequences and gene annotations along with BLAST/DIAMOND tabular similarity search results. Output: A 2-column data frame representing anchor pairs.*

## When to Use
- **Inference and Analysis of Synteny Networks**: Use when you need to detect conserved gene content and order across multiple genomes from protein sequences and gene annotations.
- **Network Clustering**: Use `cluster_network()` to group synteny networks into clusters using algorithms like Infomap.
- **Phylogenomic Profiling**: Use `phylogenomic_profile()` to identify which species contain which synteny clusters, revealing highly conserved or taxon-specific gene groups.
- **Visualizing Synteny Profiles**: Use `plot_profiles()` to generate highly customizable heatmaps of phylogenomic profiles.

## When NOT to Use
- **Overlapping Communities (e.g., Tandem Arrays)**: Do not use the default Infomap algorithm in `cluster_network()` if genes must belong to multiple clusters; use an alternative like the clique percolation algorithm instead.
- **Simple Sequence Similarity Searches**: Do not use `infer_syntenet()` for simple sequence alignment or similarity searches without genomic coordinate context; use `run_diamond()` or `run_last()` directly.

## Data Requirements
- **Sequence Data (`seq`)**: A list of `AAStringSet` objects containing translated primary transcripts for each species. Can be imported from FASTA files using `fasta2AAStringSetlist()`.
- **Annotation Data (`annotation`)**: A `GRangesList` or `CompressedGRangesList` containing gene coordinates. Can be imported from GFF/GTF files using `gff2GRangesList()`.
- **Similarity Search Results**: A list of data frames containing tabular outputs of all-vs-all searches (e.g., from DIAMOND or BLASTp), which can be loaded using `read_diamond()` or `read_last()`.

## Key Parameters
- **gene_field** (`"gene_id"`): The column name in the GRanges metadata containing gene IDs, used in `check_input()` and `process_input()`.
- **clust_function** (`stats::hclust`): The clustering function used to group columns in `plot_profiles()`.
- **clust_params** (`list(method = "ward.D")`): Additional parameters passed to the column clustering function in `plot_profiles()`.
- **dist_function** (`stats::dist`): The distance function used to compute the distance matrix in `plot_profiles()`.
- **dist_params** (`list(method = "euclidean")`): Additional parameters passed to the distance function in `plot_profiles()`.
- **cluster_species** (`NULL`): A character vector defining the custom display order of species in `plot_profiles()`.

## Best Practices
- Run `check_input()` before processing to verify that sequence names match gene annotations and that isoform sequences are not duplicated.
- Standardize sequence headers and add unique species identifiers to gene and chromosome names using `process_input()`.
- Check if DIAMOND is installed and available in your system PATH using `diamond_is_installed()` before calling `run_diamond()`.
- Pass a named character vector matching a species tree to the `cluster_species` parameter in `plot_profiles()` to visualize synteny patterns in a phylogenetic context.

## Common Pitfalls
- **Isoform Duplication**: Inputting multiple isoforms of the same gene will fail input checks; ensure only primary transcripts are included in the input sequences.
- **Mismatched Gene IDs**: If gene IDs are stored in a non-default column in the GFF/GTF files, you must specify the correct column name using the `gene_field` parameter in `check_input()` and `process_input()`.

## Alternatives
- **MCScanX**: The original C++ command-line tool for synteny detection (syntenet implements a native version of this algorithm in R via Rcpp).
- **igraph**: For alternative network clustering methods that can be passed directly to `cluster_network()`.
- **CliquePercolation**: For clustering algorithms that allow community overlap.

## Citations
- Zhao and Schranz (2017). Network-based approach to analyze synteny. *Scientific Reports*.
- Wang et al. (2012). MCScanX: a toolkit for detection and evolutionary analysis of gene synteny and collinearity. *Nucleic Acids Research*.

## References
- Homepage: bioconductor.org/packages/syntenet
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/syntenet/inst/doc/vignette.html
