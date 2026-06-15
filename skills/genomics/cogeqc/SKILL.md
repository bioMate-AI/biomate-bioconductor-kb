---
name: bioconductor-cogeqc
description: cogeqc aims to facilitate systematic quality checks on standard comparative genomics analyses to help researchers detect issues and select the most suitable parameters for each data set. cogeqc can be used to asses: i. genome assembly and annotation quality with BUSCOs and comparisons of statistics with publicly available genomes on the NCBI; ii. orthogroup inference using a protein domain-based approach and; iii. synteny detection using synteny network properties. There are also data visualizat
when_to_use: Use when: Assessing genome assembly and annotation quality; Assessing orthogroup inference; Assessing synteny identification; Quality control and preprocessing (cogeqc). Not for: Requires R ≥ 4.2.0 and Bioconductor ≥ 3.16
user-invocable: false
---

# cogeqc

## Workflows

### Standard Workflow

Assess genome assembly and annotation quality by comparing custom statistics against NCBI genomes and evaluating gene space completeness with BUSCO.

```r
library(cogeqc)

# 1. Retrieve and compare genome assembly statistics
maize_stats <- get_genome_stats(taxon = "Zea mays")
my_stats <- data.frame(
    accession = "my_lovely_maize",
    sequence_length = 2.4 * 1e9,
    gene_count_total = 50000,
    CC_ratio = 2
)
comparison <- compare_genome_stats(ncbi_stats = maize_stats, user_stats = my_stats)
plot_genome_stats(ncbi_stats = maize_stats, user_stats = my_stats)

# 2. Read and plot BUSCO summary statistics
output_dir <- system.file("extdata", package = "cogeqc")
busco_summary <- read_busco(output_dir)
plot_busco(busco_summary)
```

*Input: Custom genome assembly statistics and BUSCO output directories; Output: Quality control comparison tables and summary visualization plots.*

## When to Use
- Assessing genome assembly and annotation quality by comparing custom statistics against NCBI genomes using `get_genome_stats`, `compare_genome_stats`, and `plot_genome_stats`.
- Assessing gene space completeness using BUSCO via `run_busco`, `read_busco`, and `plot_busco`.
- Assessing orthogroup inference (e.g., from OrthoFinder or OrthoMCL) using a protein domain-based approach with `read_orthogroups` and `assess_orthogroups`.

## When NOT to Use
- For performing the actual genome assembly, gene annotation, or orthogroup clustering itself. Use external tools like Flye, Liftoff, or OrthoFinder, then use `cogeqc` for downstream quality control.

## Data Requirements
- For genome stats: A data frame of user-defined assembly statistics containing at least an `accession` column and other matching NCBI fields (e.g., `sequence_length`, `gene_count_total`, `CC_ratio`).
- For BUSCO: A directory containing BUSCO output files or pre-parsed BUSCO summary data frames.
- For orthogroups: An OrthoFinder `Orthogroups.tsv` file or a parsed data frame with columns `Orthogroup`, `Species`, and `Gene`.

## Key Parameters
- **taxon** (NULL): Taxon name or NCBI Taxonomy ID to retrieve statistics for in `get_genome_stats`.
- **filters** (NULL): List of key-value pairs to filter NCBI Datasets API results in `get_genome_stats`.
- **ncbi_stats** (NULL): Reference data frame of NCBI genome statistics in `compare_genome_stats` and `plot_genome_stats`.
- **user_stats** (NULL): Data frame of user-observed genome statistics to compare or highlight.
- **lineage** (NULL): Lineage dataset name for BUSCO in `run_busco`.
- **mode** (NULL): BUSCO run mode (e.g., "genome") in `run_busco`.
- **outpath** (NULL): Path to directory where BUSCO output will be stored in `run_busco`.
- **download_path** (NULL): Path to directory where BUSCO datasets will be downloaded in `run_busco`.

## Best Practices
- Use the `CC_ratio` (ratio of contigs to chromosome pairs) as a robust measurement of contiguity that allows cross-species comparisons.
- Filter NCBI reference genomes to match your assembly level (e.g., chromosome-scale) and annotation status using the `filters` parameter in `get_genome_stats`.
- Check if BUSCO is installed in your PATH using `busco_is_installed` before calling `run_busco`.
- Consider genomes with >90% complete BUSCOs as high quality when visualizing with `plot_busco`.

## Common Pitfalls
- `run_busco` failing due to missing system dependencies. Fix: Ensure BUSCO is installed and in your system PATH, or check with `busco_is_installed()`.
- Column mismatch when comparing custom stats with NCBI stats. Fix: Ensure the column names in your custom data frame exactly match the column names returned by `get_genome_stats` (e.g., `sequence_length` instead of `genome_size`).

## Alternatives
- `quast` (external tool) for general genome assembly quality metrics.
- `OrthoFinder` (external tool) for orthogroup inference.

## Citations
- Simão FA, Waterhouse RM, Ioannidis P, Kriventseva EV, Zdobnov EM (2015). BUSCO: Assessing Genome Assembly and Annotation Completeness with Single-Copy Orthologs. Bioinformatics.
- Wang P, Wang F (2022). A Proposed Metric Set for Evaluation of Genome Assembly Quality. Trends in Genetics.

## References
- Homepage: bioconductor.org/packages/cogeqc
- Vignette: https://bioconductor.org/packages/release/bioc/vignettes/cogeqc/inst/doc/genome_assembly_annotation_completeness.html
